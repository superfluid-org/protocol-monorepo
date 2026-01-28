/**
 * Fetch Pending Safe Transactions Script (Hardhat)
 *
 * Fetches and decodes pending governance transactions from a Gnosis Safe.
 * This is used to verify what governance actions are pending before execution.
 *
 * Usage:
 *   PROVIDER_URL=https://... npx hardhat run scripts/fetch-safe-pending-tx.ts
 *
 * Environment variables:
 *   PROVIDER_URL     - RPC provider URL [REQUIRED]
 *   SAFE_ADDRESS     - Safe address to query (auto-detected from governance if not specified)
 *   TX_INDEX         - Specific transaction nonce to fetch (defaults to latest pending)
 *   OUTPUT_FILE      - Output file path for JSON (defaults to stdout)
 *   RESOLVER_ADDRESS - Resolver address for auto-detecting governance Safe
 *
 * Output: Decoded governance action with contract addresses
 */

import { ethers } from "hardhat";
import * as fs from "fs";

// Safe Transaction Service URLs by chain ID
const SAFE_TX_SERVICE_URLS: Record<number, string> = {
    // Mainnets
    1: "https://safe-transaction-mainnet.safe.global",
    10: "https://safe-transaction-optimism.safe.global",
    56: "https://safe-transaction-bsc.safe.global",
    100: "https://safe-transaction-gnosis-chain.safe.global",
    137: "https://safe-transaction-polygon.safe.global",
    8453: "https://safe-transaction-base.safe.global",
    42161: "https://safe-transaction-arbitrum.safe.global",
    42220: "https://safe-transaction-celo.safe.global",
    43114: "https://safe-transaction-avalanche.safe.global",
    534352: "https://safe-transaction-scroll.safe.global",
    // Testnets
    11155111: "https://safe-transaction-sepolia.safe.global",
};

// Known governance function selectors
const GOVERNANCE_SELECTORS: Record<string, string> = {
    // SuperfluidGovernanceII functions
    "0x91ebc872": "batchUpdateSuperTokenLogic",
    "0x5f9e7d77": "updateContracts",
    "0x8d6e2782": "replaceGovernance",
    "0x2467cf55": "registerAgreementClass",
    "0x7b1039d5": "updateCode", // UUPSProxiable
    "0x3659cfe6": "upgradeTo", // UUPSUpgradeable
    "0x4f1ef286": "upgradeToAndCall",
};

// ABI fragments for decoding governance calls
const GOVERNANCE_ABI = [
    "function batchUpdateSuperTokenLogic(address host, address[] tokens)",
    "function updateContracts(address host, address hostNewLogic, address[] agreementClassNewLogics, address superTokenFactoryNewLogic, address poolBeaconNewLogic)",
    "function replaceGovernance(address host, address newGov)",
    "function registerAgreementClass(address host, address agreementClass)",
    "function updateCode(address newAddress)",
    "function upgradeTo(address newImplementation)",
    "function upgradeToAndCall(address newImplementation, bytes data)",
];

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
 * Fetch pending transactions from Safe Transaction Service
 */
async function fetchPendingTransactions(safeAddress: string, chainId: number): Promise<SafeTransaction[]> {
    const baseUrl = SAFE_TX_SERVICE_URLS[chainId];
    if (!baseUrl) {
        throw new Error(`No Safe Transaction Service URL for chain ${chainId}`);
    }

    const url = `${baseUrl}/api/v1/safes/${safeAddress}/multisig-transactions/?executed=false&trusted=true`;

    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`Failed to fetch pending transactions: ${response.statusText}`);
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
        const iface = new ethers.Interface(GOVERNANCE_ABI);
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
        decoded.fragment.inputs.forEach((input, i) => {
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

/**
 * Extract contract addresses from decoded governance action
 */
function extractAddressesFromAction(decoded: DecodedAction): Record<string, string> {
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
            // Agreement class logics (CFA, IDA, GDA)
            if (Array.isArray(params.agreementClassNewLogics)) {
                const keys = ["CFA_LOGIC", "IDA_LOGIC", "GDA_LOGIC"];
                params.agreementClassNewLogics.forEach((addr: string, i: number) => {
                    if (addr !== ZERO_ADDRESS && keys[i]) {
                        addresses[keys[i]] = addr;
                    }
                });
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
async function detectSafeAddress(provider: ethers.Provider, resolverAddress?: string): Promise<string> {
    // If resolver address provided, use SDK pattern
    if (resolverAddress) {
        const resolverABI = ["function get(string key) view returns (address)"];
        const resolver = new ethers.Contract(resolverAddress, resolverABI, provider);

        const hostAddr = await resolver.get("Superfluid.v1");
        if (hostAddr === ethers.ZeroAddress) {
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
    const extractedAddresses = extractAddressesFromAction(decoded);

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
