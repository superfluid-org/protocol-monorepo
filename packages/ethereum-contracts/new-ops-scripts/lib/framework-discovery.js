const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const PACKAGE_ROOT = path.resolve(__dirname, "../..");
const ZERO = ethers.constants.AddressZero;
const UUPS = "contracts/upgradability/UUPSProxy.sol:UUPSProxy";
const BITMAP = "contracts/libs/SlotsBitmapLibrary.sol:SlotsBitmapLibrary";
const POOL_DEPLOYER = "contracts/agreements/gdav1/SuperfluidPoolDeployerLibrary.sol:SuperfluidPoolDeployerLibrary";

function rpcErrorMessage(error) {
    const messages = new Set();
    function collect(value, depth = 0) {
        if (!value || depth > 5) return;
        if (typeof value === "string") {
            messages.add(value);
            return;
        }
        if (value.reason) messages.add(value.reason);
        if (value.message) messages.add(value.message);
        collect(value.error, depth + 1);
        if (value.data && typeof value.data === "object") collect(value.data, depth + 1);
        if (value.body) {
            try { collect(JSON.parse(value.body).error, depth + 1); } catch { /* Non-JSON transport response. */ }
        }
    }
    collect(error);
    return [...messages].join("; ");
}

function parseOptions(argv) {
    const options = { network: argv[0], release: process.env.RELEASE_VERSION || "v1" };
    const values = {
        "--rpc-url": "rpcUrl", "--release": "release", "--host": "host",
        "--resolver": "resolver", "--block": "block", "--constructor-args-file": "constructorArgsFile",
        "--verifier": "verifier", "--verifier-url": "verifierUrl", "--compiler-version": "compilerVersion",
    };
    if (!options.network || options.network.startsWith("-")) throw new Error("A canonical metadata network name is required");
    for (let i = 1; i < argv.length; i++) {
        const arg = argv[i];
        if (arg === "--plan") options.plan = true;
        else if (arg === "--skip-tokens") options.skipTokens = true;
        else if (arg === "--verify-proxy") {
            throw new Error("--verify-proxy explorer association is not implemented. Proxy SOURCE verification is included automatically; link implementations in the explorer separately.");
        } else if (values[arg] && argv[i + 1] && !argv[i + 1].startsWith("--")) options[values[arg]] = argv[++i];
        else throw new Error(`Unknown option or missing value: ${arg}`);
    }
    return options;
}

function loadEnvironment() {
    // Discovery never loads a keystore or creates password files.
    const dotenv = require("dotenv");
    const original = { ...process.env };
    dotenv.config({ path: path.join(PACKAGE_ROOT, ".env"), quiet: true });
    dotenv.config({ path: path.join(PACKAGE_ROOT, "../.env"), override: true, quiet: true });
    Object.assign(process.env, original);
}

async function discoverFramework(options) {
    const rows = JSON.parse(fs.readFileSync(process.env.METADATA_JSON || path.join(PACKAGE_ROOT, "../metadata/networks.json"), "utf8"));
    const row = rows.find((r) => r.name === options.network);
    if (!row) throw new Error(`Unsupported metadata network: ${options.network}`);
    const rpcUrl = options.rpcUrl || process.env.RPC_URL || process.env.PROVIDER_URL_OVERRIDE ||
        process.env.PROVIDER_URL_TEMPLATE?.replace(/\{\{NETWORK\}\}/g, row.name) || row.publicRPCs?.[0];
    if (!rpcUrl) throw new Error("No RPC URL configured");
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const chainId = (await provider.getNetwork()).chainId;
    if (chainId !== row.chainId) throw new Error(`RPC chain ${chainId} does not match ${row.name} (${row.chainId})`);
    const block = options.block === undefined ? await provider.getBlockNumber() : Number(options.block);
    if (!Number.isSafeInteger(block) || block < 0) throw new Error("--block must be a nonnegative block number");
    const header = await provider.getBlock(block);
    if (!header) throw new Error(`Block ${block} not found`);
    const overrides = options.constructorArgsFile ? JSON.parse(fs.readFileSync(options.constructorArgsFile, "utf8")) : {};
    const constructorArgs = new Map(Object.entries(overrides).map(([address, args]) => {
        if (!ethers.utils.isAddress(address) || !ethers.utils.isHexString(args)) {
            throw new Error("Constructor overrides must be an address -> ABI-encoded hex JSON object");
        }
        return [address.toLowerCase(), args];
    }));
    const result = {
        schemaVersion: 1, network: row.name, chainId, release: options.release,
        blockNumber: block, blockHash: header.hash,
        addresses: {}, contracts: [], errors: [], unsupported: [],
        metadataContracts: row.contractsV1 || {},
        notes: [
            "Read-only snapshot. No signing, transactions, artifact mutation, or explorer requests during discovery/plan.",
            "Proxy source verification is distinct from explorer proxy/implementation association (--verify-proxy is unsupported).",
            "Underlying ERC20s are reported, not verified: arbitrary token sources and private TestToken mint-limit constructors are not inferable from ERC20 getters.",
            "Use the source checkout/compiler settings of the deployment; current sources cannot verify historical bytecode changed by a later release.",
        ],
    };
    const addresses = result.addresses;
    async function attempt(label, fn) {
        try { return await fn(); }
        catch (error) {
            result.errors.push({ component: label, message: rpcErrorMessage(error) });
            return undefined;
        }
    }
    async function read(address, signature, args = []) {
        const iface = new ethers.utils.Interface([`function ${signature}`]);
        const fragment = Object.values(iface.functions)[0];
        const data = await provider.call({ to: address, data: iface.encodeFunctionData(fragment, args) }, block);
        return iface.decodeFunctionResult(fragment, data)[0];
    }
    async function address(key, value, optional = false) {
        const resolved = ethers.utils.getAddress(await value);
        addresses[key] = resolved;
        if (resolved === ZERO && optional) return undefined;
        if (resolved === ZERO || await provider.getCode(resolved, block) === "0x") throw new Error(`${key} has no deployed code at ${resolved}`);
        return resolved;
    }
    function add(label, deployedAddress, source, types = [], values = [], libraries = {}, implementation) {
        const encoded = constructorArgs.get(deployedAddress.toLowerCase()) || ethers.utils.defaultAbiCoder.encode(types, values);
        const existing = result.contracts.find((c) => c.address.toLowerCase() === deployedAddress.toLowerCase() && c.contract === source);
        if (existing) return;
        result.contracts.push({ label, address: deployedAddress, contract: source, constructorArgs: encoded, libraries, ...(implementation ? { implementation } : {}) });
    }
    async function proxy(key, proxyAddress, source = UUPS) {
        const implementation = await address(`${key}_LOGIC`, read(proxyAddress, "getCodeAddress() view returns (address)"));
        add(`${key} proxy`, proxyAddress, source, [], [], {}, implementation);
        return implementation;
    }
    const resolver = await attempt("resolver", async () => {
        const value = await address("RESOLVER", options.resolver || process.env.RESOLVER_ADDRESS || row.contractsV1.resolver);
        add("resolver", value, "contracts/utils/Resolver.sol:Resolver");
        return value;
    });
    const host = await attempt("host", async () => address("SUPERFLUID_HOST_PROXY", options.host ||
        (resolver ? read(resolver, "get(string) view returns (address)", [`Superfluid.${options.release}`]) : Promise.reject(new Error("Resolver unavailable; pass --host")))));
    if (!host) return result;
    const hostLogic = await attempt("host proxy", () => proxy("SUPERFLUID_HOST", host));
    if (hostLogic) await attempt("host logic and dependencies", async () => {
        const nonUpgradable = await read(hostLogic, "NON_UPGRADABLE_DEPLOYMENT() view returns (bool)");
        if (nonUpgradable) throw new Error("Non-upgradeable production frameworks are unsupported");
        const whitelist = await read(hostLogic, "APP_WHITE_LISTING_ENABLED() view returns (bool)");
        const callbackGas = await read(hostLogic, "CALLBACK_GAS_LIMIT() view returns (uint64)");
        const simple = await address("SIMPLE_FORWARDER", read(hostLogic, "SIMPLE_FORWARDER() view returns (address)"));
        const erc2771 = await address("ERC2771_FORWARDER", read(hostLogic, "getERC2771Forwarder() view returns (address)"));
        const acl = await address("SIMPLE_ACL", read(hostLogic, "getSimpleACL() view returns (address)"));
        add("host logic", hostLogic, "contracts/superfluid/Superfluid.sol:Superfluid",
            ["bool", "bool", "uint64", "address", "address", "address"], [nonUpgradable, whitelist, callbackGas, simple, erc2771, acl]);
        add("simple forwarder", simple, "contracts/utils/SimpleForwarder.sol:SimpleForwarder");
        add("ERC2771 forwarder", erc2771, "contracts/utils/ERC2771Forwarder.sol:ERC2771Forwarder");
        add("ACL", acl, "contracts/utils/SimpleACL.sol:SimpleACL");
    });
    await attempt("governance", async () => {
        const gov = await address("SUPERFLUID_GOVERNANCE", read(host, "getGovernance() view returns (address)"));
        // Use the implementation slot rather than swallowing failed getCodeAddress RPCs.
        const slot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
        const storage = await provider.getStorageAt(gov, slot, block);
        const logic = ethers.utils.getAddress(`0x${storage.slice(-40)}`);
        if (logic !== ZERO) {
            await address("SUPERFLUID_GOVERNANCE_LOGIC", logic);
            add("governance proxy", gov, "contracts/gov/SuperfluidGovernanceII.sol:SuperfluidGovernanceIIProxy", [], [], {}, logic);
            add("governance logic", logic, "contracts/gov/SuperfluidGovernanceII.sol:SuperfluidGovernanceII");
        } else if (row.isTestnet) add("test governance", gov, "contracts/utils/TestGovernance.sol:TestGovernance");
        else throw new Error("Governance has no UUPS implementation; cannot infer a mainnet governance source");
    });
    if (resolver) await attempt("loader", async () => {
        const loader = await address("SUPERFLUID_LOADER", read(resolver, "get(string) view returns (address)", ["SuperfluidLoader-v1"]), true);
        if (loader) add("loader", loader, "contracts/utils/SuperfluidLoader.sol:SuperfluidLoader", ["address"], [resolver]);
    });
    const agreements = {};
    for (const [key, name, source] of [
        ["CFA", "ConstantFlow", "contracts/agreements/ConstantFlowAgreementV1.sol:ConstantFlowAgreementV1"],
        ["IDA", "InstantDistribution", "contracts/agreements/InstantDistributionAgreementV1.sol:InstantDistributionAgreementV1"],
        ["GDA", "GeneralDistribution", "contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol:GeneralDistributionAgreementV1"],
    ]) {
        await attempt(`${key} agreement`, async () => {
            const agreement = await address(`${key}_PROXY`, read(host, "getAgreementClass(bytes32) view returns (address)", [ethers.utils.id(`org.superfluid-finance.agreements.${name}Agreement.v1`)]));
            agreements[key] = agreement;
            const logic = await proxy(key, agreement);
            if (key === "CFA") add("CFA logic", logic, source, ["address"], [host]);
            else {
                const bitmap = await address(`${key}_SLOTS_BITMAP_LIBRARY`, read(logic, "SLOTS_BITMAP_LIBRARY_ADDRESS() view returns (address)"));
                add(`${key} bitmap library`, bitmap, BITMAP);
                const libraries = { [BITMAP]: bitmap };
                if (key === "IDA") {
                    add("IDA logic", logic, source, ["address", "bool", "uint32"], [host,
                        await read(logic, "NEW_ACTIVITY_FROZEN() view returns (bool)"),
                        await read(logic, "MAX_NUM_SUBSCRIPTIONS() view returns (uint32)")], libraries);
                } else {
                    const deployer = await address("SUPERFLUID_POOL_DEPLOYER_LIBRARY", read(logic, "SUPERFLUID_POOL_DEPLOYER_ADDRESS() view returns (address)"));
                    const beacon = await address("SUPERFLUID_POOL_BEACON", read(logic, "superfluidPoolBeacon() view returns (address)"));
                    libraries[POOL_DEPLOYER] = deployer;
                    add("pool deployer library", deployer, POOL_DEPLOYER);
                    add("GDA logic", logic, source, ["address", "address"], [host, beacon], libraries);
                }
            }
        });
    }
    const beacon = addresses.SUPERFLUID_POOL_BEACON;
    if (beacon) {
        await attempt("pool logic", async () => {
            const logic = await address("SUPERFLUID_POOL_LOGIC", read(beacon, "implementation() view returns (address)"));
            add("pool logic", logic, "contracts/agreements/gdav1/SuperfluidPool.sol:SuperfluidPool", ["address"], [await read(logic, "GDA() view returns (address)")]);
        });
        await attempt("beacon constructor", async () => {
            const override = constructorArgs.get(beacon.toLowerCase());
            if (override) {
                add("pool beacon", beacon, "contracts/upgradability/SuperfluidUpgradeableBeacon.sol:SuperfluidUpgradeableBeacon");
                return;
            }
            // OZ4 beacons do NOT emit Upgraded in their constructors. Ownership's
            // zero-previous-owner event identifies creation without archive state.
            const range = Number(row.logsQueryRange) || 10000;
            let creation;
            for (let start = Number(row.startBlockV1) || 0; start <= block && !creation; start += range * 4) {
                const pages = await Promise.all(Array.from({ length: 4 }, async (_, i) => {
                    const fromBlock = start + i * range;
                    if (fromBlock > block) return [];
                    const toBlock = Math.min(fromBlock + range - 1, block);
                    try {
                        return await provider.getLogs({
                            address: beacon, fromBlock, toBlock,
                            topics: [ethers.utils.id("OwnershipTransferred(address,address)"), ethers.constants.HashZero],
                        });
                    } catch (error) {
                        throw new Error(`Beacon creation logs ${fromBlock}-${toBlock}: ${rpcErrorMessage(error)}. Supply --constructor-args-file with the original beacon constructor if historical logs are unavailable.`);
                    }
                }));
                creation = pages.flat().sort((a, b) => a.blockNumber - b.blockNumber || a.logIndex - b.logIndex)[0];
            }
            if (!creation) throw new Error("No beacon creation ownership event found; supply --constructor-args-file with the ORIGINAL beacon constructor");
            // Some RPCs prune the transaction-hash index, but retain block bodies.
            const creationBlock = await provider.getBlockWithTransactions(creation.blockNumber);
            const transaction = creationBlock?.transactions.find((tx) => tx.hash === creation.transactionHash);
            if (!transaction) throw new Error(`Creation transaction ${creation.transactionHash} is unavailable in block ${creation.blockNumber}; supply --constructor-args-file`);
            if (transaction.to || ethers.utils.getContractAddress(transaction).toLowerCase() !== beacon.toLowerCase()) {
                throw new Error(`Beacon was created internally by ${creation.transactionHash}; its original constructor requires --constructor-args-file`);
            }
            if (transaction.data.length < 66) throw new Error("Beacon creation input is too short to contain its address constructor");
            const encoded = `0x${transaction.data.slice(-64)}`;
            const originalImplementation = ethers.utils.defaultAbiCoder.decode(["address"], encoded)[0];
            addresses.SUPERFLUID_POOL_BEACON_INITIAL_IMPLEMENTATION = originalImplementation;
            result.beaconCreation = { blockNumber: creation.blockNumber, transactionHash: creation.transactionHash };
            add("pool beacon", beacon, "contracts/upgradability/SuperfluidUpgradeableBeacon.sol:SuperfluidUpgradeableBeacon", ["address"], [originalImplementation]);
        });
    }
    await attempt("factory and token logic", async () => {
        const factory = await address("SUPER_TOKEN_FACTORY_PROXY", read(host, "getSuperTokenFactory() view returns (address)"));
        const factoryLogic = await proxy("SUPER_TOKEN_FACTORY", factory);
        const tokenLogic = await address("SUPER_TOKEN_LOGIC", read(factoryLogic, "getSuperTokenLogic() view returns (address)"));
        const adminLogic = await address("POOL_ADMIN_NFT_FACTORY_LOGIC", read(factoryLogic, "POOL_ADMIN_NFT_LOGIC() view returns (address)"), true);
        const memberLogic = await address("POOL_MEMBER_NFT_FACTORY_LOGIC", read(factoryLogic, "POOL_MEMBER_NFT_LOGIC() view returns (address)"), true);
        add("factory logic", factoryLogic, "contracts/superfluid/SuperTokenFactory.sol:SuperTokenFactory", ["address", "address", "address", "address"], [host, tokenLogic, adminLogic || ZERO, memberLogic || ZERO]);
        const admin = await address("POOL_ADMIN_NFT_PROXY", read(tokenLogic, "POOL_ADMIN_NFT() view returns (address)"), true);
        const member = await address("POOL_MEMBER_NFT_PROXY", read(tokenLogic, "POOL_MEMBER_NFT() view returns (address)"), true);
        add("SuperToken logic", tokenLogic, "contracts/superfluid/SuperToken.sol:SuperToken", ["address", "address"], [host, admin || ZERO]);
        if (member || memberLogic) throw new Error("Nonzero PoolMemberNFT has no source in this release; use the matching historical source checkout");
        const nftLogics = new Set(adminLogic ? [adminLogic] : []);
        if (admin) nftLogics.add(await proxy("POOL_ADMIN_NFT", admin));
        for (const logic of nftLogics) {
            add("PoolAdminNFT logic", logic, "contracts/agreements/gdav1/PoolAdminNFT.sol:PoolAdminNFT", ["address", "address"], [
                await read(logic, "HOST() view returns (address)"),
                await read(logic, "GENERAL_DISTRIBUTION_AGREEMENT_V1() view returns (address)"),
            ]);
        }
    });
    if (!options.skipTokens && resolver) {
        const symbols = row.isTestnet ? ["fDAIx", "fUSDCx", "fTUSDx"] : [];
        if (row.nativeTokenSymbol) symbols.push(`${row.nativeTokenSymbol}x`);
        for (const symbol of symbols) await attempt(`token ${symbol}`, async () => {
            const token = await address(`SUPER_TOKEN_${symbol.toUpperCase()}`, read(resolver, "get(string) view returns (address)", [`supertokens.${options.release}.${symbol}`]), true);
            if (!token) return;
            const tokenHost = await read(token, "getHost() view returns (address)");
            if (tokenHost.toLowerCase() !== host.toLowerCase()) throw new Error(`Resolver token ${symbol} belongs to another framework; use --skip-tokens for an unregistered --host deployment`);
            const underlying = await read(token, "getUnderlyingToken() view returns (address)");
            addresses[`UNDERLYING_${symbol.toUpperCase()}`] = underlying;
            const implementation = await address(`SUPER_TOKEN_${symbol.toUpperCase()}_LOGIC`, read(token, "getCodeAddress() view returns (address)"));
            const source = underlying === ZERO ? "contracts/tokens/SETH.sol:SETHProxy" : UUPS;
            add(`token ${symbol} proxy`, token, source, [], [], {}, implementation);
            if (implementation !== addresses.SUPER_TOKEN_LOGIC) {
                let adminNFT;
                try {
                    adminNFT = await read(implementation, "POOL_ADMIN_NFT() view returns (address)");
                } catch (error) {
                    if (error.code !== "CALL_EXCEPTION" || error.data !== "0x") throw error;
                    result.unsupported.push({
                        component: `token ${symbol} historical logic`, address: implementation,
                        reason: "Implementation does not expose this release's POOL_ADMIN_NFT API. Its historical SuperToken source/constructor is not inferable from the current API; verify from its matching source checkout. Proxy source verification remains included.",
                    });
                    return;
                }
                add(`token ${symbol} logic`, implementation, "contracts/superfluid/SuperToken.sol:SuperToken",
                    ["address", "address"], [await read(implementation, "getHost() view returns (address)"), adminNFT]);
            }
        });
    }
    for (const [field, name] of [
        ["cfaV1Forwarder", "CFAv1Forwarder"], ["gdaV1Forwarder", "GDAv1Forwarder"],
        ["macroForwarder", "BlindMacroForwarder"], ["clearMacroForwarderV1WithPermit2", "ClearMacroForwarderV1WithPermit2"],
        ["batchLiquidator", "BatchLiquidator"], ["toga", "TOGA"],
    ]) {
        // Metadata periphery belongs to v1, not an operator's alternate release/host.
        if (options.release !== "v1" || host.toLowerCase() !== row.contractsV1.host.toLowerCase()) continue;
        if (!row.contractsV1[field]) continue;
        await attempt(name, async () => {
            const deployedAddress = await address(name, row.contractsV1[field]);
            const types = name === "TOGA" ? ["address", "uint256"] : ["address"];
            const values = name === "TOGA" ? [host, await read(deployedAddress, "minBondDuration() view returns (uint256)")] : [host];
            add(name, deployedAddress, `contracts/utils/${name}.sol:${name}`, types, values);
        });
    }
    return result;
}

module.exports = { PACKAGE_ROOT, discoverFramework, loadEnvironment, parseOptions };
