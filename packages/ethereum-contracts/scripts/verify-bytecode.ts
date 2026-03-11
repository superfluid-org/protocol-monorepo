/**
 * Bytecode Verification Script (Hardhat)
 *
 * Compares locally built contract bytecode against deployed contracts on-chain.
 * This is used to verify that deployed contracts match the expected source code
 * before executing governance actions.
 *
 * Usage:
 *   ADDRESSES_FILE=addresses.vars PROVIDER_URL=https://... npx hardhat run scripts/verify-bytecode.ts
 *
 * Environment variables:
 *   ADDRESSES_FILE - Path to addresses file (shell variable format) [REQUIRED]
 *   PROVIDER_URL   - RPC provider URL [REQUIRED if not using --network]
 *   DEBUG          - Set to "true" for verbose output
 *   JSON_OUTPUT    - Set to "true" for JSON-only output
 *
 * The addresses file should contain shell variable assignments like:
 *   SUPERFLUID_HOST_LOGIC=0x...
 *   CFA_LOGIC=0x...
 *   etc.
 *
 * Output: JSON report to stdout with verification results
 */

import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";

// Contract name to artifact mapping (only _LOGIC and direct contract keys)
// _PROXY keys are handled by auto-resolving to their implementation address
const CONTRACT_ARTIFACTS: Record<string, string> = {
    SUPERFLUID_HOST_LOGIC: "Superfluid",
    CFA_LOGIC: "ConstantFlowAgreementV1",
    IDA_LOGIC: "InstantDistributionAgreementV1",
    GDA_LOGIC: "GeneralDistributionAgreementV1",
    SUPER_TOKEN_LOGIC: "SuperToken",
    SUPER_TOKEN_FACTORY_LOGIC: "SuperTokenFactory",
    SUPERFLUID_GOVERNANCE_LOGIC: "SuperfluidGovernanceII",
    POOL_ADMIN_NFT_LOGIC: "PoolAdminNFT",
    POOL_MEMBER_NFT_LOGIC: "PoolMemberNFT",
    SUPERFLUID_POOL_LOGIC: "SuperfluidPool",
    SUPERFLUID_POOL_BEACON: "SuperfluidUpgradeableBeacon",
    RESOLVER: "Resolver",
    SUPERFLUID_LOADER: "SuperfluidLoader",
    CFAV1_FORWARDER: "CFAv1Forwarder",
    GDAV1_FORWARDER: "GDAv1Forwarder",
    TOGA: "TOGA",
    BATCH_LIQUIDATOR: "BatchLiquidator",
    SLOTS_BITMAP_LIBRARY: "SlotsBitmapLibrary",
    SUPERFLUID_POOL_DEPLOYER_LIBRARY: "SuperfluidPoolDeployerLibrary",
    DUMMY_BEACON_PROXY: "BeaconProxy",
    ERC2771_FORWARDER: "ERC2771Forwarder",
    SIMPLE_FORWARDER: "SimpleForwarder",
};

// Mapping from proxy address keys to their corresponding logic address keys.
// When only proxy addresses are available (e.g. from metadata), the script
// auto-resolves implementation addresses via on-chain getCodeAddress() calls.
const PROXY_TO_LOGIC: Record<string, string> = {
    SUPERFLUID_HOST_PROXY: "SUPERFLUID_HOST_LOGIC",
    CFA_PROXY: "CFA_LOGIC",
    IDA_PROXY: "IDA_LOGIC",
    GDA_PROXY: "GDA_LOGIC",
    SUPER_TOKEN_FACTORY_PROXY: "SUPER_TOKEN_FACTORY_LOGIC",
    POOL_ADMIN_NFT_PROXY: "POOL_ADMIN_NFT_LOGIC",
    POOL_MEMBER_NFT_PROXY: "POOL_MEMBER_NFT_LOGIC",
    // SUPERFLUID_GOVERNANCE is a proxy but doesn't follow the _PROXY suffix convention
    SUPERFLUID_GOVERNANCE: "SUPERFLUID_GOVERNANCE_LOGIC",
};

// Contracts that require library linking
const LIBRARY_LINKS: Record<string, string[]> = {
    InstantDistributionAgreementV1: ["SlotsBitmapLibrary"],
    GeneralDistributionAgreementV1: ["SlotsBitmapLibrary", "SuperfluidPoolDeployerLibrary"],
};

interface ImmutableValue {
    name: string;           // variable name from AST, or "unknown_<id>"
    value: string;          // hex value extracted from deployed bytecode
    positions: number[];    // byte offsets in deployed bytecode
}

interface MetadataInfo {
    deployedSolcVersion: string;
    expectedSolcVersion: string;
    solcMatch: boolean;
    deployedIpfsHash: string;
    expectedIpfsHash: string;
    ipfsMatch: boolean;
}

interface BytecodeComparison {
    deployedLength: number;
    expectedLength: number;
    deployedHash: string;
    expectedHash: string;
    similarityPercent: number;
    firstDiffOffset: number | null;
    diffContext: { deployed: string; expected: string } | null;
    segmentMap: string;
    matchMethod: string;
    immutables: ImmutableValue[];
    metadata: MetadataInfo | null;
}

interface VerificationResult {
    key: string;
    contractName: string;
    address: string;
    status: "verified" | "mismatch" | "not_deployed" | "no_artifact" | "error";
    message: string;
    bytecodeComparison?: BytecodeComparison;
}

interface VerificationReport {
    network: number;
    timestamp: string;
    contracts: VerificationResult[];
    summary: {
        total: number;
        verified: number;
        mismatch: number;
        notDeployed: number;
        noArtifact: number;
        errors: number;
    };
}

/**
 * Parse addresses.vars file format
 * Format: KEY=VALUE (shell variable format)
 */
function parseAddressesFile(filePath: string): Record<string, string> {
    const content = fs.readFileSync(filePath, "utf8");
    const addresses: Record<string, string> = {};

    content.split("\n").forEach(line => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith("#")) return;

        const match = trimmed.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
        if (match) {
            const [, key, value] = match;
            // Remove quotes if present
            addresses[key] = value.replace(/^["']|["']$/g, "");
        }
    });

    return addresses;
}

/**
 * Get the provider - either from Hardhat network or from PROVIDER_URL env var
 */
function getProvider(): ethers.providers.Provider {
    // If PROVIDER_URL is set, use it directly
    if (process.env.PROVIDER_URL) {
        return new ethers.providers.JsonRpcProvider(process.env.PROVIDER_URL);
    }
    // Otherwise use Hardhat's configured provider
    return ethers.provider;
}

/**
 * Resolve a UUPS proxy address to its implementation (logic) address
 * by calling getCodeAddress() on the proxy contract.
 */
async function resolveImplementation(
    provider: ethers.providers.Provider,
    proxyAddress: string
): Promise<string | null> {
    try {
        const iface = new ethers.utils.Interface([
            "function getCodeAddress() view returns (address)",
        ]);
        const calldata = iface.encodeFunctionData("getCodeAddress");
        const result = await provider.call({ to: proxyAddress, data: calldata });
        const decoded = iface.decodeFunctionResult("getCodeAddress", result);
        return decoded[0];
    } catch {
        return null;
    }
}

/**
 * Load Hardhat artifact for a contract.
 * Returns both the artifact JSON and the file path (needed to locate build-info).
 */
function loadArtifact(contractName: string): { artifact: any; artifactPath: string } | null {
    const basePath = path.join(__dirname, "../build/hardhat");

    // Try different possible paths
    const possiblePaths = [
        path.join(basePath, `contracts/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/superfluid/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/agreements/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/agreements/gdav1/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/gov/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/libs/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/utils/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/tokens/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `@openzeppelin/contracts/metatx/${contractName}.sol/${contractName}.json`),
    ];

    for (const p of possiblePaths) {
        if (fs.existsSync(p)) {
            return { artifact: JSON.parse(fs.readFileSync(p, "utf8")), artifactPath: p };
        }
    }

    return null;
}

/**
 * Immutable reference: a byte range in deployed bytecode that holds an immutable value.
 */
interface ImmutableRef {
    start: number;  // byte offset in deployed bytecode
    length: number; // byte length (typically 32)
}

/**
 * Immutable variable info grouped by AST node ID, with variable name resolved from the AST.
 */
interface ImmutableVariable {
    id: string;
    name: string;
    refs: ImmutableRef[];
}

/**
 * Walk an AST node tree to find a node with the given numeric ID and return its name.
 */
function findAstNodeName(node: any, targetId: number): string | null {
    if (!node || typeof node !== "object") return null;
    if (node.id === targetId && node.name) return node.name;
    for (const key of Object.keys(node)) {
        const val = node[key];
        if (Array.isArray(val)) {
            for (const child of val) {
                const found = findAstNodeName(child, targetId);
                if (found) return found;
            }
        } else if (val && typeof val === "object") {
            const found = findAstNodeName(val, targetId);
            if (found) return found;
        }
    }
    return null;
}

/**
 * Load immutable references from the Hardhat build-info.
 * Returns variables grouped by AST ID with resolved names.
 */
function loadImmutableReferences(artifactPath: string, contractName: string): ImmutableVariable[] {
    try {
        const dbgPath = artifactPath.replace(/\.json$/, ".dbg.json");
        if (!fs.existsSync(dbgPath)) return [];

        const dbg = JSON.parse(fs.readFileSync(dbgPath, "utf8"));
        const buildInfoPath = path.resolve(path.dirname(dbgPath), dbg.buildInfo);
        if (!fs.existsSync(buildInfoPath)) return [];

        const buildInfo = JSON.parse(fs.readFileSync(buildInfoPath, "utf8"));

        // Search all source files for the contract
        const contracts = buildInfo.output?.contracts || {};
        for (const sourceFile of Object.keys(contracts)) {
            const contractOutput = contracts[sourceFile]?.[contractName];
            if (contractOutput) {
                const refs = contractOutput.evm?.deployedBytecode?.immutableReferences || {};
                const variables: ImmutableVariable[] = [];

                // Resolve variable names from AST
                const sources = buildInfo.output?.sources || {};
                for (const [astId, locations] of Object.entries(refs) as Array<[string, Array<{ start: number; length: number }>]>) {
                    let name: string | null = null;
                    const numericId = parseInt(astId, 10);
                    for (const src of Object.values(sources) as any[]) {
                        if (src?.ast) {
                            name = findAstNodeName(src.ast, numericId);
                            if (name) break;
                        }
                    }
                    variables.push({
                        id: astId,
                        name: name || `immutable_${astId}`,
                        refs: locations.map(l => ({ start: l.start, length: l.length })),
                    });
                }
                return variables;
            }
        }
    } catch {
        // Fall through
    }
    return [];
}

/**
 * Extract immutable values from deployed bytecode and substitute them into expected bytecode.
 * Returns the patched expected bytecode and the extracted immutable values for reporting.
 *
 * This is the key verification step: we take the actual on-chain immutable values,
 * plug them into the compiler output, and then require a 100% exact match.
 * The extracted values are reported so reviewers can verify them independently.
 */
function substituteImmutables(
    deployed: string,
    expected: string,
    variables: ImmutableVariable[]
): { patched: string; extractedValues: ImmutableValue[] } {
    const patchedChars = expected.split("");
    const extractedValues: ImmutableValue[] = [];

    for (const v of variables) {
        // Extract value from the first occurrence in deployed bytecode
        const firstRef = v.refs[0];
        const hexStart = firstRef.start * 2;
        const hexEnd = hexStart + firstRef.length * 2;
        const value = "0x" + deployed.slice(hexStart, hexEnd);

        // Substitute into all occurrences in expected bytecode
        for (const ref of v.refs) {
            const s = ref.start * 2;
            const e = s + ref.length * 2;
            const deployedSlice = deployed.slice(s, e);
            for (let i = s; i < e && i < patchedChars.length; i++) {
                patchedChars[i] = deployedSlice[i - s];
            }
        }

        extractedValues.push({
            name: v.name,
            value,
            positions: v.refs.map(r => r.start),
        });
    }

    return { patched: patchedChars.join(""), extractedValues };
}

/**
 * Find positions of unlinked library placeholders in expected bytecode
 * and zero out those 20-byte (40 hex char) regions in both bytecodes.
 * Hardhat format: __$<34-char-hash>$__ (40 hex chars total, replacing a 20-byte address)
 */
function maskUnlinkedLibraries(deployed: string, expected: string): { deployed: string; expected: string } {
    const re = /__\$[a-f0-9]{34}\$__/gi;
    let match;
    const regions: { start: number; length: number }[] = [];
    while ((match = re.exec(expected)) !== null) {
        regions.push({ start: match.index, length: 40 });
    }
    if (regions.length === 0) return { deployed, expected };

    const dChars = deployed.split("");
    const eChars = expected.split("");
    for (const r of regions) {
        for (let i = r.start; i < r.start + r.length; i++) {
            if (i < dChars.length) dChars[i] = "0";
            if (i < eChars.length) eChars[i] = "0";
        }
    }
    return { deployed: dChars.join(""), expected: eChars.join("") };
}

/**
 * Parse a single CBOR metadata blob string to extract solc version and IPFS hash.
 *
 * CBOR metadata structure (53 bytes / 106 hex chars):
 *   a2                       - CBOR map(2)
 *   64 69706673              - text(4) "ipfs"
 *   58 22                    - bytes(34)
 *   12 20 <32 bytes>         - multihash: sha2-256, 32-byte digest
 *   64 736f6c63              - text(4) "solc"
 *   43 <3 bytes>             - bytes(3) = compiler version (major.minor.patch)
 *   00 33                    - CBOR metadata length (51 = 0x33)
 */
function parseMetadataBlob(blob: string): { solcVersion: string; ipfsHash: string } {
    const re = /a2646970667358221220([0-9a-f]{64})64736f6c6343([0-9a-f]{6})0033/;
    const m = blob.match(re);
    if (!m) return { solcVersion: "unknown", ipfsHash: "unknown" };
    const vHex = m[2];
    const major = parseInt(vHex.slice(0, 2), 16);
    const minor = parseInt(vHex.slice(2, 4), 16);
    const patch = parseInt(vHex.slice(4, 6), 16);
    return {
        solcVersion: `${major}.${minor}.${patch}`,
        ipfsHash: m[1],
    };
}

/**
 * Extract CBOR metadata from both bytecodes, verify solc versions match,
 * and substitute deployed metadata blobs into expected bytecode.
 *
 * The IPFS hash changes between compilations (different file paths, build env)
 * — this is expected and not a security concern.
 * The solc version MUST match — a mismatch indicates different compiler versions.
 *
 * By substituting (not masking), the final exact comparison covers the entire
 * bytecode including metadata regions, with no hidden differences.
 */
function substituteMetadata(deployed: string, expected: string): {
    patched: string;
    metadata: MetadataInfo | null;
} {
    const re = /a26469706673582212[0-9a-f]{66}64736f6c6343[0-9a-f]{6}0033/g;

    const deployedBlobs: { match: string; index: number }[] = [];
    const expectedBlobs: { match: string; index: number }[] = [];

    let m;
    while ((m = re.exec(deployed)) !== null) {
        deployedBlobs.push({ match: m[0], index: m.index });
    }
    re.lastIndex = 0;
    while ((m = re.exec(expected)) !== null) {
        expectedBlobs.push({ match: m[0], index: m.index });
    }

    // Parse the last (outermost = contract's own) blob from each for reporting
    const parsedDeployed = deployedBlobs.length > 0
        ? parseMetadataBlob(deployedBlobs[deployedBlobs.length - 1].match) : null;
    const parsedExpected = expectedBlobs.length > 0
        ? parseMetadataBlob(expectedBlobs[expectedBlobs.length - 1].match) : null;

    let metadata: MetadataInfo | null = null;
    if (parsedDeployed && parsedExpected) {
        metadata = {
            deployedSolcVersion: parsedDeployed.solcVersion,
            expectedSolcVersion: parsedExpected.solcVersion,
            solcMatch: parsedDeployed.solcVersion === parsedExpected.solcVersion,
            deployedIpfsHash: parsedDeployed.ipfsHash,
            expectedIpfsHash: parsedExpected.ipfsHash,
            ipfsMatch: parsedDeployed.ipfsHash === parsedExpected.ipfsHash,
        };
    }

    // If blob counts differ, cannot substitute — return unmodified
    if (deployedBlobs.length !== expectedBlobs.length || deployedBlobs.length === 0) {
        return { patched: expected, metadata };
    }

    // Substitute each expected blob with corresponding deployed blob
    // (from end to start to preserve indices)
    let patched = expected;
    for (let i = expectedBlobs.length - 1; i >= 0; i--) {
        const eBlob = expectedBlobs[i];
        const dBlob = deployedBlobs[i];
        patched = patched.slice(0, eBlob.index) + dBlob.match + patched.slice(eBlob.index + eBlob.match.length);
    }

    return { patched, metadata };
}

/**
 * Get deployed bytecode from artifact, applying library links
 */
function getLinkedBytecode(
    artifact: any,
    libraryAddresses: Record<string, string>
): string {
    let bytecode = artifact.deployedBytecode || artifact.bytecode || "";

    // Replace library placeholders with actual addresses
    // Hardhat uses __$<hash>$__ format for library placeholders
    Object.entries(libraryAddresses).forEach(([libName, libAddr]) => {
        if (!libAddr) return;

        const addrWithoutPrefix = libAddr.toLowerCase().replace("0x", "");

        // Match Hardhat's library placeholder format: __$<34-char-hash>$__
        const placeholderRegex = /__\$[a-f0-9]{34}\$__/gi;
        bytecode = bytecode.replace(placeholderRegex, addrWithoutPrefix);

        // Also try Truffle-style placeholder
        const trufflePlaceholder = `__${libName}${"_".repeat(Math.max(0, 38 - libName.length))}`;
        bytecode = bytecode.replace(new RegExp(trufflePlaceholder, "gi"), addrWithoutPrefix);
    });

    return bytecode.toLowerCase();
}

/**
 * Build a segment map: divide bytecode into chunks and mark each as matching (=) or different (X)
 */
function buildSegmentMap(deployed: string, expected: string, segmentSize: number = 64): string {
    const maxLen = Math.max(deployed.length, expected.length);
    let map = "";
    for (let i = 0; i < maxLen; i += segmentSize) {
        const dSeg = deployed.slice(i, i + segmentSize);
        const eSeg = expected.slice(i, i + segmentSize);
        map += dSeg === eSeg ? "=" : "X";
    }
    return map;
}

/**
 * Compute similarity percentage between two hex strings
 */
function computeSimilarity(deployed: string, expected: string): number {
    const minLength = Math.min(deployed.length, expected.length);
    if (minLength === 0) return 0;
    let matchCount = 0;
    for (let i = 0; i < minLength; i++) {
        if (deployed[i] === expected[i]) matchCount++;
    }
    return (matchCount / minLength) * 100;
}

/**
 * Extract hex context around a divergence point (in hex char units)
 */
function extractDiffContext(deployed: string, expected: string, firstDiffHexPos: number, contextChars: number = 40): { deployed: string; expected: string } | null {
    if (firstDiffHexPos < 0) return null;
    const start = Math.max(0, firstDiffHexPos - contextChars);
    const end = firstDiffHexPos + contextChars;
    return {
        deployed: deployed.slice(start, end),
        expected: expected.slice(start, end),
    };
}

/**
 * Compare bytecode with full verification:
 *   1. Extract immutable values from deployed code and substitute into expected
 *   2. Mask unlinked library placeholders (substitute deployed addresses)
 *   3. Mask CBOR metadata hashes (compiler-specific, not security-relevant)
 *   4. Require 100% exact match — no fuzzy similarity fallbacks
 *
 * The extracted immutable values are included in the report for manual verification.
 */
async function compareBytecode(
    provider: ethers.providers.Provider,
    expectedBytecode: string,
    address: string,
    debug: boolean,
    immutableVars: ImmutableVariable[] = []
): Promise<{ matches: boolean; message: string; comparison: BytecodeComparison | null }> {
    const deployedCode = await provider.getCode(address);

    if (deployedCode === "0x" || deployedCode.length <= 4) {
        return { matches: false, message: "No code at address", comparison: null };
    }

    // Normalize both bytecodes
    let expected = expectedBytecode.toLowerCase().replace(/^0x/, "");
    let deployed = deployedCode.toLowerCase().replace(/^0x/, "");

    // Trim constructor code from expected bytecode
    const runtimeStart = expected.indexOf("6080604052");
    if (runtimeStart > 0) {
        expected = expected.slice(runtimeStart);
    }

    // Substitute unlinked library placeholders (extract addresses from deployed)
    const libSubst = maskUnlinkedLibraries(deployed, expected);
    deployed = libSubst.deployed;
    expected = libSubst.expected;

    if (debug) {
        console.error(`  Expected bytecode length: ${expected.length}`);
        console.error(`  Deployed bytecode length: ${deployed.length}`);
    }

    // Substitute immutable values: extract from deployed, plug into expected
    let extractedImmutables: ImmutableValue[] = [];
    if (immutableVars.length > 0) {
        const result = substituteImmutables(deployed, expected, immutableVars);
        expected = result.patched;
        extractedImmutables = result.extractedValues;
    }

    // Substitute CBOR metadata: extract from both, verify solc version, substitute deployed into expected
    const metaResult = substituteMetadata(deployed, expected);
    expected = metaResult.patched;
    const metadataInfo = metaResult.metadata;

    // Fail early if solc version doesn't match — this is a real problem
    if (metadataInfo && !metadataInfo.solcMatch) {
        const deployedHash = crypto.createHash("sha256").update(deployed).digest("hex");
        const expectedHash = crypto.createHash("sha256").update(expected).digest("hex");
        return {
            matches: false,
            message: `Solc version mismatch: deployed=${metadataInfo.deployedSolcVersion} expected=${metadataInfo.expectedSolcVersion}`,
            comparison: {
                deployedLength: deployed.length / 2,
                expectedLength: expected.length / 2,
                deployedHash,
                expectedHash,
                similarityPercent: parseFloat(computeSimilarity(deployed, expected).toFixed(2)),
                firstDiffOffset: null,
                diffContext: null,
                segmentMap: buildSegmentMap(deployed, expected),
                matchMethod: "none",
                immutables: extractedImmutables,
                metadata: metadataInfo,
            },
        };
    }

    // Precompute comparison data (after ALL substitutions: immutables + metadata)
    const deployedHash = crypto.createHash("sha256").update(deployed).digest("hex");
    const expectedHash = crypto.createHash("sha256").update(expected).digest("hex");
    const similarityPercent = computeSimilarity(deployed, expected);
    const firstDiffCharPos = (() => {
        const minLen = Math.min(deployed.length, expected.length);
        for (let i = 0; i < minLen; i++) {
            if (deployed[i] !== expected[i]) return i;
        }
        return deployed.length !== expected.length ? minLen : -1;
    })();
    const firstDiffOffset = firstDiffCharPos >= 0 ? Math.floor(firstDiffCharPos / 2) : null;
    const diffContext = firstDiffCharPos >= 0 ? extractDiffContext(deployed, expected, firstDiffCharPos) : null;
    const segmentMap = buildSegmentMap(deployed, expected);

    const buildResult = (matches: boolean, message: string, matchMethod: string) => ({
        matches,
        message,
        comparison: {
            deployedLength: deployed.length / 2,
            expectedLength: expected.length / 2,
            deployedHash,
            expectedHash,
            similarityPercent: parseFloat(similarityPercent.toFixed(2)),
            firstDiffOffset,
            diffContext,
            segmentMap,
            matchMethod,
            immutables: extractedImmutables,
            metadata: metadataInfo,
        },
    });

    // Single exact comparison (after immutable + metadata substitution)
    if (deployed === expected) {
        const parts: string[] = [];
        if (extractedImmutables.length > 0) parts.push(`${extractedImmutables.length} immutables extracted`);
        if (metadataInfo) parts.push(`solc ${metadataInfo.deployedSolcVersion} verified`);

        const method = ["exact",
            extractedImmutables.length > 0 ? "immutables" : "",
            metadataInfo ? "metadata" : "",
        ].filter(Boolean).join("+");

        const msg = parts.length > 0
            ? `Exact match (${parts.join(", ")})`
            : "Exact match";
        return buildResult(true, msg, method);
    }

    // No match — report as mismatch with full diagnostics
    if (debug && firstDiffOffset !== null) {
        console.error(`  First difference at byte offset: ${firstDiffOffset}`);
        if (diffContext) {
            console.error(`  Deployed around diff: ...${diffContext.deployed}...`);
            console.error(`  Expected around diff: ...${diffContext.expected}...`);
        }
    }

    return buildResult(false, "Bytecode mismatch", "none");
}

async function main() {
    const addressesFile = process.env.ADDRESSES_FILE;
    const debug = process.env.DEBUG === "true";
    const jsonOutput = process.env.JSON_OUTPUT === "true";

    if (!addressesFile) {
        console.error("Error: ADDRESSES_FILE environment variable is required");
        console.error("Usage: ADDRESSES_FILE=addresses.vars npx hardhat run scripts/verify-bytecode.ts --network <network>");
        process.exit(1);
    }

    if (!fs.existsSync(addressesFile)) {
        console.error(`Error: Addresses file not found: ${addressesFile}`);
        process.exit(1);
    }

    const addresses = parseAddressesFile(addressesFile);
    const provider = getProvider();
    const network = await provider.getNetwork();
    const networkId = Number(network.chainId);

    if (!jsonOutput) {
        console.error(`Verifying bytecode on network ${networkId}...`);
    }

    // Auto-resolve proxy addresses to their implementation (logic) addresses.
    // This allows the script to work with proxy-only addresses from metadata.
    if (!jsonOutput) {
        console.error("Resolving proxy → implementation addresses...");
    }
    for (const [proxyKey, logicKey] of Object.entries(PROXY_TO_LOGIC)) {
        if (addresses[proxyKey] && !addresses[logicKey]) {
            const implAddress = await resolveImplementation(provider, addresses[proxyKey]);
            if (implAddress) {
                addresses[logicKey] = implAddress;
                if (!jsonOutput) {
                    console.error(`  ${proxyKey} (${addresses[proxyKey]}) → ${logicKey} (${implAddress})`);
                }
            } else if (!jsonOutput) {
                console.error(`  ${proxyKey}: could not resolve implementation (may not be a UUPS proxy)`);
            }
        }
    }
    if (!jsonOutput) {
        console.error("");
    }

    // Build library addresses map
    const libraryAddresses: Record<string, string> = {
        SlotsBitmapLibrary: addresses.SLOTS_BITMAP_LIBRARY || "",
        SuperfluidPoolDeployerLibrary: addresses.SUPERFLUID_POOL_DEPLOYER_LIBRARY || "",
    };

    const results: VerificationReport = {
        network: networkId,
        timestamp: new Date().toISOString(),
        contracts: [],
        summary: {
            total: 0,
            verified: 0,
            mismatch: 0,
            notDeployed: 0,
            noArtifact: 0,
            errors: 0,
        },
    };

    // Process each contract address
    for (const [key, address] of Object.entries(addresses)) {
        // Skip non-contract entries
        if (!address || !address.startsWith("0x") || address.length !== 42) {
            continue;
        }

        // Skip special keys
        if (key === "NETWORK_ID" || key.startsWith("NON_SUPER_TOKEN_") || key === "IS_TESTNET") {
            continue;
        }

        const contractName = CONTRACT_ARTIFACTS[key];
        if (!contractName) {
            if (debug) {
                console.error(`Skipping unknown contract key: ${key}`);
            }
            continue;
        }

        results.summary.total++;

        const result: VerificationResult = {
            key,
            contractName,
            address,
            status: "error",
            message: "",
        };

        try {
            // Check if address has code
            const code = await provider.getCode(address);
            if (code === "0x" || code.length <= 4) {
                result.status = "not_deployed";
                result.message = "No code at address";
                results.summary.notDeployed++;
                results.contracts.push(result);
                continue;
            }

            // Load artifact
            const loaded = loadArtifact(contractName);
            if (!loaded) {
                result.status = "no_artifact";
                result.message = `Artifact not found for ${contractName}`;
                results.summary.noArtifact++;
                results.contracts.push(result);
                continue;
            }

            const { artifact, artifactPath } = loaded;

            // Load immutable references from build-info
            const immutableRefs = loadImmutableReferences(artifactPath, contractName);

            // Get linked bytecode
            const requiredLibraries = LIBRARY_LINKS[contractName] || [];
            const libsToLink: Record<string, string> = {};
            for (const libName of requiredLibraries) {
                if (libraryAddresses[libName]) {
                    libsToLink[libName] = libraryAddresses[libName];
                }
            }

            const expectedBytecode = getLinkedBytecode(artifact, libsToLink);

            // Compare bytecode
            const comparison = await compareBytecode(provider, expectedBytecode, address, debug, immutableRefs);

            if (comparison.comparison) {
                result.bytecodeComparison = comparison.comparison;
            }

            if (comparison.matches) {
                result.status = "verified";
                result.message = comparison.message;
                results.summary.verified++;
            } else {
                result.status = "mismatch";
                result.message = comparison.message;
                results.summary.mismatch++;
            }
        } catch (err: any) {
            result.status = "error";
            result.message = err.message;
            results.summary.errors++;
        }

        results.contracts.push(result);

        if (!jsonOutput) {
            const statusIcon: Record<string, string> = {
                verified: "\u2705",
                mismatch: "\u274C",
                not_deployed: "\u26A0\uFE0F",
                no_artifact: "\u2753",
                error: "\u274C",
            };
            console.error(`${statusIcon[result.status] || "?"} ${key}: ${result.status} - ${result.message}`);
        }
    }

    // Output results
    if (!jsonOutput) {
        console.error("\n=== Verification Summary ===");
        console.error(`Total contracts: ${results.summary.total}`);
        console.error(`Verified: ${results.summary.verified}`);
        console.error(`Mismatch: ${results.summary.mismatch}`);
        console.error(`Not deployed: ${results.summary.notDeployed}`);
        console.error(`No artifact: ${results.summary.noArtifact}`);
        console.error(`Errors: ${results.summary.errors}`);
    }

    // Always output JSON to stdout for piping
    console.log(JSON.stringify(results, null, 2));

    // Exit with error if any mismatches
    if (results.summary.mismatch > 0 || results.summary.errors > 0) {
        process.exit(1);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
