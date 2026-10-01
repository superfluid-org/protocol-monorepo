/**
 * Fetch Pending Safe Transactions Script (Hardhat)
 *
 * Fetches and decodes pending governance transactions from a Gnosis Safe.
 * This is used to verify what governance actions are pending before execution.
 *
 * Usage:
 *   NETWORK=xdai-mainnet npx hardhat run scripts/fetch-safe-pending-tx.ts
 *
 * Environment variables:
 *   NETWORK                 - Superfluid network name (used with PROVIDER_URL_TEMPLATE)
 *   PROVIDER_URL_TEMPLATE   - RPC URL with {{NETWORK}} placeholder (optional; default:
 *                             https://rpc-endpoints.superfluid.dev/{{NETWORK}})
 *   PROVIDER_URL            - Explicit RPC URL override (optional)
 *   SAFE_ADDRESS            - Safe address to query (auto-detected from governance if not specified)
 *   TX_INDEX         - Specific transaction nonce to fetch (defaults to latest pending)
 *   OUTPUT_FILE      - Output file path for JSON (defaults to stdout)
 *   RESOLVER_ADDRESS - Resolver address for auto-detecting governance Safe
 *
 * Output: Decoded governance action with contract addresses
 */

import { ethers } from "hardhat";
import * as fs from "fs";

// Safe Transaction Service network slugs by chain ID
// https://api.safe.global/tx-service/{slug}/api/v2/...
const SAFE_TX_SERVICE_SLUGS: Record<number, string> = {
    1: "eth",
    10: "oeth",
    56: "bnb",
    100: "gno",
    137: "pol",
    8453: "base",
    42161: "arb1",
    42220: "celo",
    43114: "avax",
    534352: "scr",
    11155111: "sep",
};

// Known governance function selectors → human-readable name for reporting.
// These are looked up by the 4-byte selector extracted from calldata.
const GOVERNANCE_SELECTORS: Record<string, string> = {
    "0x42148deb": "batchUpdateSuperTokenLogic",
    "0x01a89b38": "batchUpdateSuperTokenLogic",
    "0x870299c0": "batchUpdateSuperTokenLogic",
    "0x8e12552f": "updateContracts",
    "0x44864b25": "replaceGovernance",
    "0xcadf8f85": "registerAgreementClass",
    "0x46951954": "updateCode", // UUPSProxiable
    "0x3659cfe6": "upgradeTo", // UUPSUpgradeable
    "0x4f1ef286": "upgradeToAndCall",
};

// ABI fragments for decoding governance calls.
// Each overload is a separate ABI entry so ethers can match by selector.
const GOVERNANCE_ABIS: Record<string, string[]> = {
    "0x42148deb": ["function batchUpdateSuperTokenLogic(address host, address[] tokens)"],
    "0x01a89b38": ["function batchUpdateSuperTokenLogic(address host, address[] tokens, address tokenLogic)"],
    "0x870299c0": ["function batchUpdateSuperTokenLogic(address host, address[] tokens, address[] tokenLogics)"],
    "0x8e12552f": ["function updateContracts(address host, address hostNewLogic, address[] agreementClassNewLogics, address superTokenFactoryNewLogic, address poolBeaconNewLogic)"],
    "0x44864b25": ["function replaceGovernance(address host, address newGov)"],
    "0xcadf8f85": ["function registerAgreementClass(address host, address agreementClass)"],
    "0x46951954": ["function updateCode(address newAddress)"],
    "0x3659cfe6": ["function upgradeTo(address newImplementation)"],
    "0x4f1ef286": ["function upgradeToAndCall(address newImplementation, bytes data)"],
};

interface SafeTransaction {
    nonce: number;
    to: string;
    value: string;
    data: string;
    safeTxHash: string;
    confirmations: { owner: string }[];
    confirmationsRequired: number;
    submissionDate: string;
}

interface DecodedAction {
    selector: string;
    functionName: string;
    params?: Record<string, any>;
    decodeError?: string;
    raw?: string;
}

interface FetchResult {
    safe: string;
    chainId: number;
    transaction?: {
        nonce: number;
        to: string;
        value: string;
        data: string;
        safeTxHash: string;
        confirmations: number;
        confirmationsRequired: number;
        submissionDate: string;
    };
    decodedAction?: DecodedAction;
    extractedAddresses: Record<string, string>;
    allPendingTransactions: {
        nonce: number;
        to: string;
        safeTxHash: string;
        confirmations: number;
    }[];
    message?: string;
}

const DEFAULT_PROVIDER_URL_TEMPLATE =
    "https://rpc-endpoints.superfluid.dev/{{NETWORK}}";

/**
 * Resolve RPC URL from PROVIDER_URL / RPC_URL / PROVIDER_URL_OVERRIDE /
 * PROVIDER_URL_TEMPLATE (with NETWORK). Template is optional.
 */
function resolveRpcUrl(): string | undefined {
    if (process.env.PROVIDER_URL) return process.env.PROVIDER_URL;
    if (process.env.RPC_URL) return process.env.RPC_URL;
    if (process.env.PROVIDER_URL_OVERRIDE) return process.env.PROVIDER_URL_OVERRIDE;
    const network = process.env.NETWORK;
    if (!network) return undefined;
    const tpl = process.env.PROVIDER_URL_TEMPLATE || DEFAULT_PROVIDER_URL_TEMPLATE;
    if (!tpl.includes("{{NETWORK}}")) {
        throw new Error("PROVIDER_URL_TEMPLATE must contain {{NETWORK}}");
    }
    return tpl.replace(/\{\{NETWORK\}\}/g, network);
}

/**
 * Get the provider from env RPC settings, or Hardhat's configured network.
 */
function getProvider(): ethers.providers.Provider {
    const url = resolveRpcUrl();
    if (url) {
        return new ethers.providers.JsonRpcProvider(url);
    }
    return ethers.provider;
}

/**
 * Fetch pending transactions from Safe Transaction Service
 */
async function fetchPendingTransactions(safeAddress: string, chainId: number): Promise<SafeTransaction[]> {
    const slug = SAFE_TX_SERVICE_SLUGS[chainId];
    if (!slug) {
        throw new Error(`No Safe Transaction Service slug for chain ${chainId}`);
    }

    const url = `https://api.safe.global/tx-service/${slug}/api/v2/safes/${safeAddress}/multisig-transactions?executed=false&limit=100`;
    const headers: Record<string, string> = {};
    if (process.env.SAFE_API_KEY) {
        headers.Authorization = `Bearer ${process.env.SAFE_API_KEY}`;
    }

    const response = await fetch(url, { headers });
    if (!response.ok) {
        throw new Error(`Failed to fetch pending transactions: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    return data.results || [];
}

/**
 * Decode governance action calldata
 */
function decodeGovernanceAction(data: string): DecodedAction {
    if (!data || data.length < 10) {
        return {
            selector: "",
            functionName: "unknown",
            raw: data,
        };
    }

    const selector = data.slice(0, 10).toLowerCase();
    const functionName = GOVERNANCE_SELECTORS[selector];

    if (!functionName) {
        return {
            selector,
            functionName: "unknown",
            raw: data,
        };
    }

    try {
        const abi = GOVERNANCE_ABIS[selector];
        if (!abi) {
            return {
                selector,
                functionName,
                decodeError: "No ABI for selector",
                raw: data,
            };
        }
        const iface = new ethers.utils.Interface(abi);
        const decoded = iface.parseTransaction({ data });

        if (!decoded) {
            return {
                selector,
                functionName,
                decodeError: "Failed to parse transaction",
                raw: data,
            };
        }

        const params: Record<string, any> = {};
        const fragment = decoded.functionFragment || (decoded as any).fragment;
        fragment.inputs.forEach((input: any, i: number) => {
            const value = decoded.args[i];
            // Convert BigInt and arrays to strings for JSON serialization
            if (typeof value === "bigint") {
                params[input.name] = value.toString();
            } else if (Array.isArray(value)) {
                params[input.name] = value.map(v =>
                    typeof v === "bigint" ? v.toString() : v
                );
            } else {
                params[input.name] = value;
            }
        });

        return {
            selector,
            functionName,
            params,
        };
    } catch (err: any) {
        return {
            selector,
            functionName,
            decodeError: err.message,
            raw: data,
        };
    }
}

const AGREEMENT_TYPE_TO_KEY: Record<string, string> = {
    [ethers.utils.id("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")]: "CFA_LOGIC",
    [ethers.utils.id("org.superfluid-finance.agreements.InstantDistributionAgreement.v1")]: "IDA_LOGIC",
    [ethers.utils.id("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1")]: "GDA_LOGIC",
};

async function identifyAgreementLogicKey(
    provider: ethers.providers.Provider,
    addr: string
): Promise<string | null> {
    const iface = new ethers.utils.Interface(["function agreementType() view returns (bytes32)"]);
    try {
        const result = await provider.call({ to: addr, data: iface.encodeFunctionData("agreementType") });
        const typeHash: string = iface.decodeFunctionResult("agreementType", result)[0];
        return AGREEMENT_TYPE_TO_KEY[typeHash] || null;
    } catch {
        return null;
    }
}

async function readAddressGetter(
    provider: ethers.providers.Provider,
    addr: string,
    signature: string
): Promise<string | null> {
    const iface = new ethers.utils.Interface([`function ${signature}`]);
    const name = signature.slice(0, signature.indexOf("("));
    try {
        const result = await provider.call({ to: addr, data: iface.encodeFunctionData(name) });
        const value: string = iface.decodeFunctionResult(name, result)[0];
        if (!value || value === ethers.constants.AddressZero) return null;
        return value;
    } catch {
        return null;
    }
}

/**
 * Extract contract addresses from decoded governance action.
 * Agreement class logics are identified via on-chain agreementType(), not array order
 * (updateContracts often passes CFA+GDA without IDA).
 */
async function extractAddressesFromAction(
    provider: ethers.providers.Provider,
    decoded: DecodedAction
): Promise<Record<string, string>> {
    const addresses: Record<string, string> = {};
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

    if (!decoded || !decoded.params) {
        return addresses;
    }

    const { functionName, params } = decoded;

    switch (functionName) {
        case "updateContracts":
            if (params.hostNewLogic && params.hostNewLogic !== ZERO_ADDRESS) {
                addresses.SUPERFLUID_HOST_LOGIC = params.hostNewLogic;
            }
            if (params.superTokenFactoryNewLogic && params.superTokenFactoryNewLogic !== ZERO_ADDRESS) {
                addresses.SUPER_TOKEN_FACTORY_LOGIC = params.superTokenFactoryNewLogic;
            }
            if (params.poolBeaconNewLogic && params.poolBeaconNewLogic !== ZERO_ADDRESS) {
                addresses.SUPERFLUID_POOL_LOGIC = params.poolBeaconNewLogic;
            }
            if (Array.isArray(params.agreementClassNewLogics)) {
                for (const addr of params.agreementClassNewLogics as string[]) {
                    if (!addr || addr === ZERO_ADDRESS) continue;
                    const key = await identifyAgreementLogicKey(provider, addr);
                    if (key) {
                        addresses[key] = addr;
                    } else {
                        console.error(`  warning: could not identify agreementType for ${addr}`);
                    }
                }
                if (addresses.GDA_LOGIC) {
                    const slots = await readAddressGetter(provider, addresses.GDA_LOGIC, "SLOTS_BITMAP_LIBRARY_ADDRESS() view returns (address)");
                    const poolLib = await readAddressGetter(provider, addresses.GDA_LOGIC, "SUPERFLUID_POOL_DEPLOYER_ADDRESS() view returns (address)");
                    if (slots) addresses.SLOTS_BITMAP_LIBRARY = slots;
                    if (poolLib) addresses.SUPERFLUID_POOL_DEPLOYER_LIBRARY = poolLib;
                } else if (addresses.IDA_LOGIC) {
                    const slots = await readAddressGetter(provider, addresses.IDA_LOGIC, "SLOTS_BITMAP_LIBRARY_ADDRESS() view returns (address)");
                    if (slots) addresses.SLOTS_BITMAP_LIBRARY = slots;
                }
            }
            break;

        case "batchUpdateSuperTokenLogic":
            // Three overloads:
            //   (host, tokens[])                - uses default logic from factory
            //   (host, tokens[], tokenLogic)    - single new logic for all tokens
            //   (host, tokens[], tokenLogics[]) - per-token logic addresses
            if (params.tokenLogic && params.tokenLogic !== ZERO_ADDRESS) {
                addresses.SUPER_TOKEN_LOGIC = params.tokenLogic;
            }
            if (Array.isArray(params.tokenLogics)) {
                const uniqueLogics = [...new Set(
                    params.tokenLogics.filter((a: string) => a !== ZERO_ADDRESS)
                )];
                if (uniqueLogics.length === 1) {
                    addresses.SUPER_TOKEN_LOGIC = uniqueLogics[0] as string;
                } else {
                    uniqueLogics.forEach((addr, i) => {
                        addresses[`SUPER_TOKEN_LOGIC_${i}`] = addr as string;
                    });
                }
            }
            break;

        case "replaceGovernance":
            if (params.newGov) {
                addresses.SUPERFLUID_GOVERNANCE_LOGIC = params.newGov;
            }
            break;

        case "registerAgreementClass":
            if (params.agreementClass) {
                addresses.NEW_AGREEMENT_CLASS = params.agreementClass;
            }
            break;

        case "updateCode":
            if (params.newAddress) {
                addresses.NEW_IMPLEMENTATION = params.newAddress;
            }
            break;

        case "upgradeTo":
            if (params.newImplementation) {
                addresses.NEW_IMPLEMENTATION = params.newImplementation;
            }
            break;

        case "upgradeToAndCall":
            if (params.newImplementation) {
                addresses.NEW_IMPLEMENTATION = params.newImplementation;
            }
            break;
    }

    return addresses;
}

/**
 * Auto-detect Safe address from governance contract ownership
 */
async function detectSafeAddress(provider: ethers.providers.Provider, resolverAddress?: string): Promise<string> {
    // If resolver address provided, use SDK pattern
    if (resolverAddress) {
        const resolverABI = ["function get(string key) view returns (address)"];
        const resolver = new ethers.Contract(resolverAddress, resolverABI, provider);

        const hostAddr = await resolver.get("Superfluid.v1");
        if (hostAddr === ethers.constants.AddressZero) {
            throw new Error("Could not find Superfluid host from resolver");
        }

        const hostABI = ["function getGovernance() view returns (address)"];
        const host = new ethers.Contract(hostAddr, hostABI, provider);
        const govAddr = await host.getGovernance();

        const ownableABI = ["function owner() view returns (address)"];
        const gov = new ethers.Contract(govAddr, ownableABI, provider);
        const owner = await gov.owner();

        return owner;
    }

    throw new Error("SAFE_ADDRESS or RESOLVER_ADDRESS environment variable is required");
}

async function main() {
    let safeAddress = process.env.SAFE_ADDRESS;
    const txIndex = process.env.TX_INDEX ? parseInt(process.env.TX_INDEX, 10) : undefined;
    const outputFile = process.env.OUTPUT_FILE;
    const resolverAddress = process.env.RESOLVER_ADDRESS;

    const provider = getProvider();
    const network = await provider.getNetwork();
    const chainId = Number(network.chainId);
    console.error(`Chain ID: ${chainId}`);

    // Auto-detect Safe address if not provided
    if (!safeAddress) {
        console.error("Auto-detecting Safe address from governance...");
        try {
            safeAddress = await detectSafeAddress(provider, resolverAddress);
            console.error(`Detected governance owner (Safe): ${safeAddress}`);
        } catch (err: any) {
            console.error(`Error detecting Safe address: ${err.message}`);
            console.error("Please provide SAFE_ADDRESS or RESOLVER_ADDRESS environment variable");
            process.exit(1);
        }
    }

    console.error(`Fetching pending transactions for Safe: ${safeAddress}`);

    let pendingTxs: SafeTransaction[];
    try {
        pendingTxs = await fetchPendingTransactions(safeAddress, chainId);
    } catch (err: any) {
        console.error(`Error fetching pending transactions: ${err.message}`);
        const result: FetchResult = {
            safe: safeAddress,
            chainId,
            extractedAddresses: {},
            allPendingTransactions: [],
            message: `Error: ${err.message}`,
        };
        console.log(JSON.stringify(result, null, 2));
        if (outputFile) {
            fs.writeFileSync(outputFile, JSON.stringify(result, null, 2));
        }
        process.exit(1);
    }

    console.error(`Found ${pendingTxs.length} pending transaction(s)`);

    if (pendingTxs.length === 0) {
        const result: FetchResult = {
            safe: safeAddress,
            chainId,
            extractedAddresses: {},
            allPendingTransactions: [],
            message: "No pending transactions found",
        };

        console.log(JSON.stringify(result, null, 2));
        if (outputFile) {
            fs.writeFileSync(outputFile, JSON.stringify(result, null, 2));
        }
        return;
    }

    // Select transaction to analyze
    const txToAnalyze = txIndex !== undefined
        ? pendingTxs.find((tx) => tx.nonce === txIndex) || pendingTxs[0]
        : pendingTxs[0]; // Latest pending tx

    console.error(`\nAnalyzing transaction with nonce ${txToAnalyze.nonce}`);
    console.error(`  To: ${txToAnalyze.to}`);
    console.error(`  Value: ${txToAnalyze.value}`);
    console.error(`  Confirmations: ${txToAnalyze.confirmations?.length || 0}/${txToAnalyze.confirmationsRequired}`);

    // Decode the governance action
    const decoded = decodeGovernanceAction(txToAnalyze.data);
    const extractedAddresses = await extractAddressesFromAction(provider, decoded);

    const result: FetchResult = {
        safe: safeAddress,
        chainId,
        transaction: {
            nonce: txToAnalyze.nonce,
            to: txToAnalyze.to,
            value: txToAnalyze.value,
            data: txToAnalyze.data,
            safeTxHash: txToAnalyze.safeTxHash,
            confirmations: txToAnalyze.confirmations?.length || 0,
            confirmationsRequired: txToAnalyze.confirmationsRequired,
            submissionDate: txToAnalyze.submissionDate,
        },
        decodedAction: decoded,
        extractedAddresses,
        allPendingTransactions: pendingTxs.map((tx) => ({
            nonce: tx.nonce,
            to: tx.to,
            safeTxHash: tx.safeTxHash,
            confirmations: tx.confirmations?.length || 0,
        })),
    };

    // Output to stderr for humans
    console.error("\n=== Decoded Governance Action ===");
    console.error(`Function: ${decoded?.functionName || "unknown"}`);
    if (decoded?.params) {
        console.error("Parameters:");
        Object.entries(decoded.params).forEach(([key, value]) => {
            console.error(`  ${key}: ${JSON.stringify(value)}`);
        });
    }

    console.error("\n=== Extracted Contract Addresses ===");
    Object.entries(extractedAddresses).forEach(([key, addr]) => {
        console.error(`  ${key}=${addr}`);
    });

    // Output JSON to stdout
    console.log(JSON.stringify(result, null, 2));

    if (outputFile) {
        fs.writeFileSync(outputFile, JSON.stringify(result, null, 2));
        console.error(`\nResults written to: ${outputFile}`);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
