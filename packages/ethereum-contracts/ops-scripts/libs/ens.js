"use strict";

const sfMeta = require("@superfluid-finance/metadata");
const { ethers } = require("ethers");

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const ENS_REGISTRY_ADDRESS = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e";
const PUBLIC_RESOLVER_NAME = "resolver.eth";
const ETH_MAINNET_CHAIN_ID = 1;
const ETH_SEPOLIA_CHAIN_ID = 11155111;
const REVERSE_REGISTRAR_L1_MAINNET = "0xa58E81fe9b61B5c3fE2AFD33CF304c454AbFc7Cb";
const REVERSE_REGISTRAR_L1_TESTNET = "0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6";
const REVERSE_REGISTRAR_L2_MAINNET = "0x0000000000D8e504002cC26E3Ec46D81971C1664";
const REVERSE_REGISTRAR_L2_TESTNET = "0x00000BeEF055f7934784D6d81b6BC86665630dbA";
const NETWORK_ALIASES = {
    "eth-mainnet": ["mainnet"],
    "eth-sepolia": ["sepolia"],
};

const REGISTRY_ABI = [
    {
        inputs: [{ internalType: "bytes32", name: "node", type: "bytes32" }],
        name: "owner",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ internalType: "bytes32", name: "node", type: "bytes32" }],
        name: "resolver",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "bytes32", name: "node", type: "bytes32" },
            { internalType: "address", name: "resolver", type: "address" },
        ],
        name: "setResolver",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "bytes32", name: "node", type: "bytes32" },
            { internalType: "bytes32", name: "label", type: "bytes32" },
            { internalType: "address", name: "owner", type: "address" },
            { internalType: "address", name: "resolver", type: "address" },
            { internalType: "uint64", name: "ttl", type: "uint64" },
        ],
        name: "setSubnodeRecord",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
];

const RESOLVER_ABI = [
    {
        inputs: [{ internalType: "bytes32", name: "node", type: "bytes32" }],
        name: "addr",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "bytes32", name: "node", type: "bytes32" },
            { internalType: "address", name: "a", type: "address" },
        ],
        name: "setAddr",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
];

const REVERSE_REGISTRAR_ABI = [
    {
        inputs: [],
        name: "defaultResolver",
        outputs: [{ internalType: "address", name: "", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ internalType: "string", name: "name", type: "string" }],
        name: "setName",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
];

function normalizeAddress(address) {
    return (address || "").toLowerCase();
}

function normalizeChainId(chainId) {
    if (typeof chainId === "string" && chainId.startsWith("0x")) {
        return parseInt(chainId, 16);
    }
    return Number(chainId);
}

function isL1Chain(chainId) {
    const normalizedChainId = normalizeChainId(chainId);
    return normalizedChainId === ETH_MAINNET_CHAIN_ID || normalizedChainId === ETH_SEPOLIA_CHAIN_ID;
}

/**
 * Resolve the reverse registrar from the four deployment buckets we support:
 * L1 mainnet, L1 testnet, L2 mainnet, and L2 testnet.
 */
function getReverseRegistrarAddressByNetwork(chainId) {
    const normalizedChainId = normalizeChainId(chainId);

    if (normalizedChainId === ETH_MAINNET_CHAIN_ID) {
        return REVERSE_REGISTRAR_L1_MAINNET;
    }
    if (normalizedChainId === ETH_SEPOLIA_CHAIN_ID) {
        return REVERSE_REGISTRAR_L1_TESTNET;
    }

    const network = sfMeta.getNetworkByChainId(normalizedChainId);
    if (!network) {
        return null;
    }

    return network.isTestnet
        ? REVERSE_REGISTRAR_L2_TESTNET
        : REVERSE_REGISTRAR_L2_MAINNET;
}

function getEnvValue(networkName, key) {
    const aliases = NETWORK_ALIASES[networkName] || [];
    const keysToTry = [networkName, ...aliases]
        .map((name) => name.replace(/-/g, "_").toUpperCase() + "_" + key)
        .concat("DEFAULT_" + key);
    const values = keysToTry.map((envKey) => process.env[envKey]).filter(Boolean);
    return values[0];
}

function getProviderUrlByTemplate(networkName) {
    if (process.env.PROVIDER_URL_OVERRIDE !== undefined) {
        return process.env.PROVIDER_URL_OVERRIDE;
    }
    if (process.env.PROVIDER_URL_TEMPLATE !== undefined) {
        if (!process.env.PROVIDER_URL_TEMPLATE.includes("{{NETWORK}}")) {
            throw new Error("env var PROVIDER_URL_TEMPLATE has invalid value");
        }
        return process.env.PROVIDER_URL_TEMPLATE.replace("{{NETWORK}}", networkName);
    }
}

function createProviderConfig(networkName) {
    const config = {
        url: getEnvValue(networkName, "PROVIDER_URL") || getProviderUrlByTemplate(networkName),
        addressIndex: 0,
        numberOfAddresses: 10,
        shareNonce: true,
    };
    config.mnemonic = getEnvValue(networkName, "MNEMONIC");
    if (!config.mnemonic) {
        const privateKey = getEnvValue(networkName, "PRIVATE_KEY");
        if (privateKey) {
            config.privateKeys = [privateKey];
        }
    }
    return config;
}

function parseSubdomain(name) {
    const parts = name.split(".");
    if (parts.length < 2) {
        return null;
    }

    return {
        label: parts[0],
        parentName: parts.slice(1).join("."),
    };
}

async function getEnsRegistry(web3) {
    const code = await web3.eth.getCode(ENS_REGISTRY_ADDRESS);
    if (!code || code === "0x") {
        throw new Error(
            `ENS registry not found at ${ENS_REGISTRY_ADDRESS} on the connected network.`
        );
    }

    return new web3.eth.Contract(REGISTRY_ABI, ENS_REGISTRY_ADDRESS);
}

async function resolvePublicResolverAddress({ web3, registry }) {
    const node = ethers.utils.namehash(PUBLIC_RESOLVER_NAME);
    const resolverAddress = await registry.methods.resolver(node).call();
    if (normalizeAddress(resolverAddress) === normalizeAddress(ZERO_ADDRESS)) {
        throw new Error(`ENS name "${PUBLIC_RESOLVER_NAME}" has no resolver.`);
    }

    const resolver = new web3.eth.Contract(RESOLVER_ABI, resolverAddress);
    const publicResolverAddress = await resolver.methods.addr(node).call();
    if (normalizeAddress(publicResolverAddress) === normalizeAddress(ZERO_ADDRESS)) {
        throw new Error(
            `ENS name "${PUBLIC_RESOLVER_NAME}" does not resolve to a public resolver address.`
        );
    }

    const code = await web3.eth.getCode(publicResolverAddress);
    if (!code || code === "0x") {
        throw new Error(
            `Resolved public resolver ${publicResolverAddress} has no code.`
        );
    }

    return publicResolverAddress;
}

async function getForwardNameState({ registry, ensName }) {
    const node = ethers.utils.namehash(ensName);
    const owner = await registry.methods.owner(node).call();
    if (normalizeAddress(owner) !== normalizeAddress(ZERO_ADDRESS)) {
        return { node, owner, exists: true };
    }

    const subdomain = parseSubdomain(ensName);
    if (!subdomain) {
        return { node, owner, exists: false };
    }

    const parentNode = ethers.utils.namehash(subdomain.parentName);
    const parentOwner = await registry.methods.owner(parentNode).call();
    return {
        node,
        owner,
        exists: false,
        subdomain,
        parentNode,
        parentOwner,
    };
}

function getChainSpecificEvmCoinType(chainId) {
    const normalizedChainId = normalizeChainId(chainId);
    return (0x80000000 | normalizedChainId) >>> 0;
}

function getReverseNamespaceCandidates(chainId) {
    const chainSpecificNamespace = `${getChainSpecificEvmCoinType(chainId).toString(16)}.reverse`;
    return [chainSpecificNamespace, "addr.reverse"];
}

/**
 * On L1, discover the registrar from ENS registry ownership of the reverse namespace.
 * On L2, use the current ENS deployment model buckets instead of querying a local registry.
 */
async function resolveReverseRegistrarAddress({ web3, chainId, override }) {
    if (override) {
        return override;
    }

    if (isL1Chain(chainId)) {
        const registry = await getEnsRegistry(web3);
        for (const reverseNamespace of getReverseNamespaceCandidates(chainId)) {
            const reverseNamespaceNode = ethers.utils.namehash(reverseNamespace);
            const registrarAddress = await registry.methods.owner(reverseNamespaceNode).call();
            if (normalizeAddress(registrarAddress) !== normalizeAddress(ZERO_ADDRESS)) {
                return registrarAddress;
            }
        }
    }

    return getReverseRegistrarAddressByNetwork(chainId);
}

async function assertReverseRegistrarUsable({
    web3,
    registrarAddress,
    name,
    caller,
}) {
    const code = await web3.eth.getCode(registrarAddress);
    if (!code || code === "0x") {
        throw new Error(
            `Reverse registrar check failed: ${registrarAddress} has no code.`
        );
    }

    const registrar = new web3.eth.Contract(REVERSE_REGISTRAR_ABI, registrarAddress);

    let defaultResolver;
    let registrarKind = "L2ReverseRegistrar-compatible";
    try {
        defaultResolver = await registrar.methods.defaultResolver().call();
        registrarKind = "ReverseRegistrar-compatible";
    } catch (_) {
        // L2ReverseRegistrar does not expose defaultResolver().
    }

    if (defaultResolver !== undefined) {
        if (!defaultResolver || /^0x0{40}$/i.test(defaultResolver)) {
            throw new Error(
                `Reverse registrar check failed: defaultResolver() returned zero address for ${registrarAddress}.`
            );
        }

        const resolverCode = await web3.eth.getCode(defaultResolver);
        if (!resolverCode || resolverCode === "0x") {
            throw new Error(
                `Reverse registrar check failed: default resolver ${defaultResolver} has no code.`
            );
        }
    }

    try {
        await registrar.methods.setName(name).call({ from: caller });
    } catch (error) {
        throw new Error(
            `Reverse registrar check failed: setName("${name}") reverts when simulated from ${caller}. ` +
            `This usually means the reverse registrar or resolver setup on this chain is incompatible. ` +
            `Original error: ${error.message}`
        );
    }

    const details = defaultResolver !== undefined
        ? `default resolver ${defaultResolver}`
        : "no defaultResolver() method";
    console.log(
        `ENS reverse registrar OK: ${registrarKind} at ${registrarAddress}, ${details}`
    );
}

async function ensureNameExists({ from, ensName, registry, publicResolver }) {
    const nameState = await getForwardNameState({ registry, ensName });
    if (nameState.exists) {
        return { node: nameState.node };
    }

    if (!nameState.subdomain) {
        throw new Error(
            `ENS name "${ensName}" is not registered and cannot be created automatically.`
        );
    }

    if (normalizeAddress(nameState.parentOwner) !== normalizeAddress(from)) {
        throw new Error(
            `Cannot create "${ensName}": ${from} does not own parent "${nameState.subdomain.parentName}" (owner: ${nameState.parentOwner}).`
        );
    }

    const labelHash = ethers.utils.id(nameState.subdomain.label);
    console.log(`  ENS: creating subdomain ${ensName}...`);
    const tx = await registry.methods
        .setSubnodeRecord(nameState.parentNode, labelHash, from, publicResolver, 0)
        .send({ from });

    return { node: nameState.node, txHash: tx.transactionHash };
}

async function ensureResolver({ from, node, ensName, registry, publicResolver }) {
    const resolver = await registry.methods.resolver(node).call();
    if (normalizeAddress(resolver) !== normalizeAddress(ZERO_ADDRESS)) {
        return { resolver };
    }

    console.log(`  ENS: setting resolver for ${ensName}...`);
    const tx = await registry.methods
        .setResolver(node, publicResolver)
        .send({ from });

    return {
        resolver: publicResolver,
        txHash: tx.transactionHash,
    };
}

async function getForwardResolutionState({ web3, ensName, expectedAddr }) {
    const registry = await getEnsRegistry(web3);
    const nameState = await getForwardNameState({ registry, ensName });
    const { node, owner } = nameState;

    if (!nameState.exists) {
        return {
            ok: false,
            status: "missing_name",
            registry,
            node,
            owner,
            resolverAddress: ZERO_ADDRESS,
        };
    }

    const resolverAddress = await registry.methods.resolver(node).call();
    if (normalizeAddress(resolverAddress) === normalizeAddress(ZERO_ADDRESS)) {
        return {
            ok: false,
            status: "missing_resolver",
            registry,
            node,
            owner,
            resolverAddress,
        };
    }

    const resolver = new web3.eth.Contract(RESOLVER_ABI, resolverAddress);
    const resolvedAddress = await resolver.methods.addr(node).call();
    if (normalizeAddress(resolvedAddress) !== normalizeAddress(expectedAddr)) {
        return {
            ok: false,
            status: "mismatch",
            registry,
            node,
            owner,
            resolverAddress,
            resolvedAddress,
        };
    }

    return {
        ok: true,
        status: "ok",
        registry,
        node,
        owner,
        resolverAddress,
        resolvedAddress,
    };
}

function formatForwardResolutionWarning({ ensName, expectedAddr, state }) {
    switch (state.status) {
        case "missing_name":
            return `ENS forward record for "${ensName}" is missing; expected ${expectedAddr}.`;
        case "missing_resolver":
            return `ENS forward record for "${ensName}" has no resolver; expected ${expectedAddr}.`;
        case "mismatch":
            return `ENS forward resolution mismatch: "${ensName}" resolves to ${state.resolvedAddress || ZERO_ADDRESS}, expected ${expectedAddr}.`;
        default:
            return `ENS forward resolution for "${ensName}" does not match ${expectedAddr}.`;
    }
}

async function getForwardResolutionAuthority({ from, ensName, registry }) {
    const nameState = await getForwardNameState({ registry, ensName });
    if (nameState.exists) {
        if (normalizeAddress(nameState.owner) === normalizeAddress(from)) {
            return { canManage: true };
        }
        return {
            canManage: false,
            reason: `${from} does not own "${ensName}" (owner: ${nameState.owner}).`,
        };
    }

    if (!nameState.subdomain) {
        return {
            canManage: false,
            reason: `"${ensName}" is not registered and cannot be created automatically.`,
        };
    }

    if (normalizeAddress(nameState.parentOwner) === normalizeAddress(from)) {
        return { canManage: true };
    }

    return {
        canManage: false,
        reason: `${from} does not own parent "${nameState.subdomain.parentName}" (owner: ${nameState.parentOwner}).`,
    };
}

async function checkForwardResolution({ web3, ensName, expectedAddr }) {
    const state = await getForwardResolutionState({ web3, ensName, expectedAddr });
    if (!state.ok) {
        if (state.status === "missing_name") {
            throw new Error(`ENS forward resolution failed: "${ensName}" is not registered.`);
        }
        if (state.status === "missing_resolver") {
            throw new Error(`ENS forward resolution failed: "${ensName}" has no resolver.`);
        }
        throw new Error(
            `ENS forward resolution mismatch: "${ensName}" resolves to ${state.resolvedAddress || ZERO_ADDRESS}, expected ${expectedAddr}.`
        );
    }

    return { ok: true, resolvedAddress: state.resolvedAddress };
}

/**
 * Ensure a forward ENS record exists and points at the expected address.
 * This may create the subdomain, set its resolver, and/or update the address record.
 */
async function ensureForwardResolution({ web3, from, ensName, expectedAddr }) {
    const registry = await getEnsRegistry(web3);
    const publicResolver = await resolvePublicResolverAddress({ web3, registry });
    const { node, txHash: createTxHash } = await ensureNameExists({
        from,
        ensName,
        registry,
        publicResolver,
    });
    const { resolver, txHash: resolverTxHash } = await ensureResolver({
        from,
        node,
        ensName,
        registry,
        publicResolver,
    });

    const resolverContract = new web3.eth.Contract(RESOLVER_ABI, resolver);
    const currentAddress = await resolverContract.methods.addr(node).call();
    if (normalizeAddress(currentAddress) === normalizeAddress(expectedAddr)) {
        return {
            action: createTxHash || resolverTxHash ? "created_or_updated" : "ok",
            txHashes: [createTxHash, resolverTxHash].filter(Boolean),
        };
    }

    console.log(`  ENS: setting address record for ${ensName} -> ${expectedAddr}...`);
    const tx = await resolverContract.methods.setAddr(node, expectedAddr).send({ from });
    await checkForwardResolution({ web3, ensName, expectedAddr });

    return {
        action: "set",
        txHashes: [createTxHash, resolverTxHash, tx.transactionHash].filter(Boolean),
    };
}

/**
 * Direct CLI entrypoint for ENS forward sync.
 * Keeps the reusable ENS logic in this file while avoiding a separate truffle-only wrapper.
 */
async function runEnsureForwardResolutionCli() {
    require("dotenv").config();
    const HDWalletProvider = require("@truffle/hdwallet-provider");
    const Web3 = require("web3");

    const [, , networkName, ensName, expectedAddr] = process.argv;
    if (!networkName || !ensName || !expectedAddr) {
        throw new Error(
            "Usage: node ops-scripts/libs/ens.js <network> <ENS_NAME> <ADDRESS>"
        );
    }

    const providerConfig = createProviderConfig(networkName);
    if (!providerConfig.url) {
        throw new Error(`No provider URL configured for network "${networkName}".`);
    }
    if (!providerConfig.mnemonic && (!providerConfig.privateKeys || providerConfig.privateKeys.length === 0)) {
        throw new Error(`No signer configured for network "${networkName}".`);
    }

    const provider = new HDWalletProvider(providerConfig);
    const web3 = new Web3(provider);

    try {
        const accounts = await web3.eth.getAccounts();
        const from = accounts[0];
        if (!from) {
            throw new Error(`No signer account resolved for network "${networkName}".`);
        }

        console.log("======== Ensure ENS forward resolution ========");
        console.log("ENS network:", networkName);
        console.log("ENS name:", ensName);
        console.log("Expected address:", expectedAddr);
        console.log("ENS owner:", from);

        const network = sfMeta.getNetworkByName(networkName);
        const isTestnet = network ? network.isTestnet : networkName === "eth-sepolia";
        const state = await getForwardResolutionState({ web3, ensName, expectedAddr });

        if (state.ok) {
            console.log(`ENS forward resolution OK: ${ensName} -> ${expectedAddr}`);
            return;
        }

        console.warn(`WARNING: ${formatForwardResolutionWarning({ ensName, expectedAddr, state })}`);
        if (!isTestnet) {
            return;
        }

        const authority = await getForwardResolutionAuthority({
            from,
            ensName,
            registry: state.registry,
        });
        if (!authority.canManage) {
            console.warn(`WARNING: ENS forward record was not updated: ${authority.reason}`);
            return;
        }

        const result = await ensureForwardResolution({
            web3,
            from,
            ensName,
            expectedAddr,
        });

        console.log(`ENS forward record ensured: ${ensName} -> ${expectedAddr}`);
        for (const txHash of result.txHashes) {
            console.log(`  tx: ${txHash}`);
        }
    } finally {
        if (provider.engine && typeof provider.engine.stop === "function") {
            provider.engine.stop();
        }
    }
}

module.exports = {
    resolveReverseRegistrarAddress,
    assertReverseRegistrarUsable,
    checkForwardResolution,
    ensureForwardResolution,
};

if (require.main === module) {
    runEnsureForwardResolutionCli().catch((error) => {
        console.error(error);
        process.exit(1);
    });
}
