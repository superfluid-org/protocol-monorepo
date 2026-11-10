// Real local-anvil transactions only. Live endpoints are used solely as read-only fork sources.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {spawn, spawnSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const {ethers} = require("ethers");
const networks = require("../../../metadata/networks.json");
const root = path.resolve(__dirname, "../..");
const bin = process.env.FOUNDRY_BIN || path.join(process.env.HOME, ".foundry/bin");
const key = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const account = new ethers.Wallet(key).address;
const zero = ethers.constants.AddressZero;
const abi = ["function CALLBACK_GAS_LIMIT() view returns(uint64)", "function APP_WHITE_LISTING_ENABLED() view returns(bool)",
    "function NON_UPGRADABLE_DEPLOYMENT() view returns(bool)", "function getGovernance() view returns(address)",
    "function owner() view returns(address)", "function getCodeAddress() view returns(address)",
    "function proxiableUUID() view returns(bytes32)", "function getAgreementClass(bytes32) view returns(address)",
    "function NEW_ACTIVITY_FROZEN() view returns(bool)", "function MAX_NUM_SUBSCRIPTIONS() view returns(uint32)",
    "function getPPPConfig(address,address) view returns(uint256,uint256)", "function getRewardAddress(address,address) view returns(address)",
    "function get(string) view returns(address)", "function getSuperTokenFactory() view returns(address)",
    "function getSuperTokenFactoryLogic() view returns(address)", "function getSuperTokenLogic() view returns(address)",
    "function POOL_ADMIN_NFT() view returns(address)", "function POOL_ADMIN_NFT_LOGIC() view returns(address)",
    "function superfluidPoolBeacon() view returns(address)", "function implementation() view returns(address)",
    "function SIMPLE_FORWARDER() view returns(address)", "function getERC2771Forwarder() view returns(address)",
    "function getSimpleACL() view returns(address)",
    "function isTrustedForwarder(address) view returns(bool)"];
const typeHash = (name) => ethers.utils.id(`org.superfluid-finance.agreements.${name}.v1`);
function run(command, args, env = {}) {
    const r = spawnSync(command, args, {cwd: root, env: {...process.env, PATH: `${bin}:${process.env.PATH}`, ...env},
        encoding: "utf8", timeout: 240000, maxBuffer: 32 * 1024 * 1024});
    assert.equal(r.status, 0, `${command} ${args.join(" ")}\n${r.stdout}\n${r.stderr}`);
    return r.stdout;
}
async function startFork(network, port) {
    const child = spawn(`${bin}/anvil`, ["--port", String(port), "--fork-url", `https://${network}.rpc.x.superfluid.dev`,
        "--gas-limit", "100000000", "--silent"], {stdio: ["ignore", "pipe", "pipe"]});
    let errors = "";
    child.stderr.on("data", (chunk) => { errors += chunk; });
    const provider = new ethers.providers.JsonRpcProvider(`http://127.0.0.1:${port}`);
    for (let i = 0; i < 120; ++i) {
        if (child.exitCode !== null) throw Error(`anvil exited: ${errors}`);
        try { await provider.getBlockNumber(); return {child, provider}; } catch {}
        await new Promise((resolve) => setTimeout(resolve, 500));
    }
    child.kill();
    throw Error(`anvil did not start: ${errors}`);
}
async function snapshot(provider, nw) {
    const contract = (a) => new ethers.Contract(a, abi, provider);
    const host = contract(nw.contractsV1.host);
    const gov = contract(await host.getGovernance());
    const ida = contract(await host.getAgreementClass(typeHash("InstantDistributionAgreement")));
    const resolver = contract(nw.contractsV1.resolver);
    const resolverEntries = {};
    for (const key of ["Superfluid.v1", "SuperfluidLoader-v1", "CFAv1Forwarder", "GDAv1Forwarder",
        "BlindMacroForwarder", "ClearMacroForwarderV1WithPermit2", "TOGA", "BatchLiquidator"]) {
        resolverEntries[key] = await resolver.get(key);
    }
    return {callback: String(await host.CALLBACK_GAS_LIMIT()), whitelist: await host.APP_WHITE_LISTING_ENABLED(),
        frozen: await ida.NEW_ACTIVITY_FROZEN(), slots: String(await ida.MAX_NUM_SUBSCRIPTIONS()),
        ppp: (await gov.getPPPConfig(host.address, zero)).map(String), reward: await gov.getRewardAddress(host.address, zero),
        resolverEntries, simpleForwarder: await host.SIMPLE_FORWARDER(),
        erc2771Forwarder: await host.getERC2771Forwarder(), acl: await host.getSimpleACL()};
}
async function validate(provider, nw) {
    const c = (a) => new ethers.Contract(a, abi, provider);
    const h = c(nw.contractsV1.host);
    assert.equal(await h.NON_UPGRADABLE_DEPLOYMENT(), false);
    const factory = c(await h.getSuperTokenFactory());
    assert.equal(await factory.getCodeAddress(), await h.getSuperTokenFactoryLogic());
    const token = c(await factory.getSuperTokenLogic());
    assert.equal(await token.proxiableUUID(), ethers.utils.id("org.superfluid-finance.contracts.SuperToken.implementation"));
    assert.equal(await c(await token.POOL_ADMIN_NFT()).getCodeAddress(), await factory.POOL_ADMIN_NFT_LOGIC());
    for (const name of ["ConstantFlowAgreement", "InstantDistributionAgreement", "GeneralDistributionAgreement"]) {
        assert.notEqual(await h.getAgreementClass(typeHash(name)), zero);
    }
    const gda = c(await h.getAgreementClass(typeHash("GeneralDistributionAgreement")));
    const pool = c(await c(await gda.superfluidPoolBeacon()).implementation());
    assert.equal(await pool.proxiableUUID(), ethers.utils.id("org.superfluid-finance.contracts.SuperfluidPool.implementation"));
    assert.equal(await h.isTrustedForwarder(nw.contractsV1.cfaV1Forwarder), true);
}

const selected = (process.env.FRAMEWORK_FORK_NETWORKS || "optimism-sepolia,eth-mainnet,optimism-mainnet,arc-mainnet").split(",");
for (const [index, name] of selected.entries()) {
    test(`framework upgrade preserves ${name}`, {timeout: 300000}, async () => {
        const nw = networks.find((n) => n.name === name);
        assert.ok(nw, `Unknown metadata network ${name}`);
        fs.mkdirSync(path.join(root, ".tmp"), {recursive: true});
        const artifacts = fs.mkdtempSync(path.join(root, ".tmp/framework-fork-"));
        const {child, provider} = await startFork(name, 19545 + index);
        const payloadFile = `.tmp/framework-${name}-safe.jsonl`;
        try {
            const before = await snapshot(provider, nw);
            const h = new ethers.Contract(nw.contractsV1.host, abi, provider);
            const oldLogic = await h.getCodeAddress();
            const gov = new ethers.Contract(await h.getGovernance(), abi, provider);
            const owner = await gov.owner();
            const safe = await provider.getCode(owner) !== "0x";
            const sender = safe ? account : owner;
            await provider.send("anvil_setBalance", [sender, "0x3635c9adc5dea00000"]);
            await provider.send("anvil_impersonateAccount", [sender]);
            const env = {DEPLOYER: sender, HOST_ADDRESS: h.address, SAFE_PAYLOADS_FILE: payloadFile,
                FOUNDRY_BROADCAST: artifacts};
            const nonce = await provider.getTransactionCount(sender);
            run(`${bin}/forge`, ["script", "foundry-scripts/Framework.s.sol:FrameworkScript", "--sig", "upgrade()",
                "--rpc-url", provider.connection.url, "--sender", sender], env);
            assert.equal(await provider.getTransactionCount(sender), nonce, "simulation broadcast a transaction");
            fs.writeFileSync(path.join(root, payloadFile), "");
            run(`${bin}/forge`, ["script", "foundry-scripts/Framework.s.sol:FrameworkScript", "--sig", "upgrade()",
                "--rpc-url", provider.connection.url, "--sender", sender, "--unlocked", "--broadcast", "--slow"], env);
            if (safe) {
                const payloads = fs.readFileSync(path.join(root, payloadFile), "utf8").trim().split("\n").map(JSON.parse);
                assert.equal(payloads.length, 1);
                const payload = payloads[0];
                assert.equal(payload.safeAddress.toLowerCase(), owner.toLowerCase());
                assert.equal(payload.to.toLowerCase(), gov.address.toLowerCase());
                assert.equal(payload.value, "0");
                assert.equal(payload.operation, "0");
                assert.equal(payload.data.slice(0, 10), ethers.utils.id("updateContracts(address,address,address[],address,address)").slice(0, 10));
                await provider.send("anvil_impersonateAccount", [owner]);
                await provider.send("anvil_setBalance", [owner, "0x3635c9adc5dea00000"]);
                await (await provider.getSigner(owner).sendTransaction({to: payload.to, data: payload.data, gasLimit: 20000000})).wait();
            }
            const after = await snapshot(provider, nw);
            assert.deepEqual(after, before);
            assert.notEqual(await h.getCodeAddress(), oldLogic);
            await validate(provider, nw);
            run("node", ["-r", "ts-node/register", "-e",
                `const h=require('hardhat'); h.ethers.provider=new h.ethers.providers.JsonRpcProvider('${provider.connection.url}'); require('./new-ops-scripts/validate-deployment.ts');`],
                {RESOLVER_ADDRESS: nw.contractsV1.resolver, RELEASE_VERSION: "v1"});
            console.log(JSON.stringify({network: name, before, after, route: safe ? "Safe payload + local impersonation" : "EOA direct"}));
        } finally { child.kill(); fs.rmSync(artifacts, {recursive: true, force: true}); }
    });
}
