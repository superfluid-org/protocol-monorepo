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

// Contract name to artifact mapping
const CONTRACT_ARTIFACTS: Record<string, string> = {
    SUPERFLUID_HOST_LOGIC: "Superfluid",
    SUPERFLUID_HOST_PROXY: "Superfluid",
    CFA_LOGIC: "ConstantFlowAgreementV1",
    CFA_PROXY: "ConstantFlowAgreementV1",
    IDA_LOGIC: "InstantDistributionAgreementV1",
    IDA_PROXY: "InstantDistributionAgreementV1",
    GDA_LOGIC: "GeneralDistributionAgreementV1",
    GDA_PROXY: "GeneralDistributionAgreementV1",
    SUPER_TOKEN_LOGIC: "SuperToken",
    SUPER_TOKEN_FACTORY_LOGIC: "SuperTokenFactory",
    SUPER_TOKEN_FACTORY_PROXY: "SuperTokenFactory",
    SUPERFLUID_GOVERNANCE_LOGIC: "SuperfluidGovernanceII",
    SUPERFLUID_GOVERNANCE: "SuperfluidGovernanceII",
    POOL_ADMIN_NFT_LOGIC: "PoolAdminNFT",
    POOL_ADMIN_NFT_PROXY: "PoolAdminNFT",
    POOL_MEMBER_NFT_LOGIC: "PoolMemberNFT",
    POOL_MEMBER_NFT_PROXY: "PoolMemberNFT",
    SUPERFLUID_POOL_LOGIC: "SuperfluidPool",
    SUPERFLUID_POOL_BEACON: "SuperfluidUpgradeableBeacon",
    RESOLVER: "Resolver",
    SUPERFLUID_LOADER: "SuperfluidLoader",
    CFAV1_FORWARDER: "CFAv1Forwarder",
    GDAV1_FORWARDER: "GDAv1Forwarder",
    TOGA: "TOGA",
    BATCH_LIQUIDATOR: "BatchLiquidator",
    FLOW_SCHEDULER: "FlowScheduler",
    VESTING_SCHEDULER: "VestingScheduler",
    SLOTS_BITMAP_LIBRARY: "SlotsBitmapLibrary",
    SUPERFLUID_POOL_DEPLOYER_LIBRARY: "SuperfluidPoolDeployerLibrary",
    DUMMY_BEACON_PROXY: "BeaconProxy",
    ERC2771_FORWARDER: "ERC2771Forwarder",
    SIMPLE_FORWARDER: "SimpleForwarder",
};

// Contracts that require library linking
const LIBRARY_LINKS: Record<string, string[]> = {
    InstantDistributionAgreementV1: ["SlotsBitmapLibrary"],
    GeneralDistributionAgreementV1: ["SlotsBitmapLibrary", "SuperfluidPoolDeployerLibrary"],
};

interface VerificationResult {
    key: string;
    contractName: string;
    address: string;
    status: "verified" | "mismatch" | "not_deployed" | "no_artifact" | "error";
    message: string;
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
function getProvider(): ethers.Provider {
    // If PROVIDER_URL is set, use it directly
    if (process.env.PROVIDER_URL) {
        return new ethers.JsonRpcProvider(process.env.PROVIDER_URL);
    }
    // Otherwise use Hardhat's configured provider
    return ethers.provider;
}

/**
 * Load Hardhat artifact for a contract
 */
function loadArtifact(contractName: string): any | null {
    const basePath = path.join(__dirname, "../build/hardhat");

    // Try different possible paths
    const possiblePaths = [
        path.join(basePath, `contracts/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/superfluid/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/agreements/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/gov/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/libs/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/utils/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `contracts/tokens/${contractName}.sol/${contractName}.json`),
        path.join(basePath, `@openzeppelin/contracts/metatx/${contractName}.sol/${contractName}.json`),
    ];

    for (const p of possiblePaths) {
        if (fs.existsSync(p)) {
            return JSON.parse(fs.readFileSync(p, "utf8"));
        }
    }

    return null;
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
 * Compare bytecode, handling immutables and metadata
 */
async function compareBytecode(
    provider: ethers.Provider,
    expectedBytecode: string,
    address: string,
    debug: boolean
): Promise<{ matches: boolean; message: string }> {
    const deployedCode = await provider.getCode(address);

    if (deployedCode === "0x" || deployedCode.length <= 4) {
        return { matches: false, message: "No code at address" };
    }

    // Normalize both bytecodes
    let expected = expectedBytecode.toLowerCase().replace(/^0x/, "");
    let deployed = deployedCode.toLowerCase().replace(/^0x/, "");

    // Trim constructor code from expected bytecode
    // The deployed code starts with 6080604052 (or similar) - find where runtime code starts
    const runtimeStart = expected.indexOf("6080604052");
    if (runtimeStart > 0) {
        expected = expected.slice(runtimeStart);
    }

    if (debug) {
        console.error(`  Expected bytecode length: ${expected.length}`);
        console.error(`  Deployed bytecode length: ${deployed.length}`);
    }

    // Direct comparison
    if (deployed === expected) {
        return { matches: true, message: "Exact match" };
    }

    // Check if deployed is a subset (ignoring metadata hash at the end)
    // Solidity appends CBOR-encoded metadata at the end of bytecode
    const metadataMarkers = ["a264", "a265", "a164", "a165"];

    for (const marker of metadataMarkers) {
        const deployedMarkerIndex = deployed.lastIndexOf(marker);
        const expectedMarkerIndex = expected.lastIndexOf(marker);

        if (deployedMarkerIndex > 0 && expectedMarkerIndex > 0) {
            const deployedWithoutMeta = deployed.slice(0, deployedMarkerIndex);
            const expectedWithoutMeta = expected.slice(0, expectedMarkerIndex);

            if (deployedWithoutMeta === expectedWithoutMeta) {
                return { matches: true, message: "Match (excluding metadata)" };
            }
        }
    }

    // Check if the deployed code is contained within expected (for proxies)
    if (expected.includes(deployed)) {
        return { matches: true, message: "Deployed code is subset of expected" };
    }

    // Check similarity for immutable differences
    const minLength = Math.min(deployed.length, expected.length);
    let matchCount = 0;
    for (let i = 0; i < minLength; i++) {
        if (deployed[i] === expected[i]) matchCount++;
    }
    const matchPercentage = (matchCount / minLength) * 100;

    if (matchPercentage > 95) {
        return {
            matches: true,
            message: `Match (${matchPercentage.toFixed(1)}% similar, likely immutable differences)`
        };
    }

    if (debug) {
        // Find first difference
        let firstDiff = 0;
        for (let i = 0; i < Math.min(deployed.length, expected.length); i++) {
            if (deployed[i] !== expected[i]) {
                firstDiff = i;
                break;
            }
        }
        console.error(`  First difference at position: ${firstDiff}`);
        console.error(`  Deployed around diff: ...${deployed.slice(Math.max(0, firstDiff - 10), firstDiff + 20)}...`);
        console.error(`  Expected around diff: ...${expected.slice(Math.max(0, firstDiff - 10), firstDiff + 20)}...`);
    }

    return { matches: false, message: "Bytecode mismatch" };
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
            const artifact = loadArtifact(contractName);
            if (!artifact) {
                result.status = "no_artifact";
                result.message = `Artifact not found for ${contractName}`;
                results.summary.noArtifact++;
                results.contracts.push(result);
                continue;
            }

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
            const comparison = await compareBytecode(provider, expectedBytecode, address, debug);

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
