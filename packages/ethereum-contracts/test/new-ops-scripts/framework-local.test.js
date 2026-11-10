const {test} = require("node:test");
const assert = require("node:assert/strict");
const {spawn, spawnSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const {ethers} = require("ethers");
const root = path.resolve(__dirname, "../..");
const bin = process.env.FOUNDRY_BIN || path.join(process.env.HOME, ".foundry/bin");
const rpc = "http://127.0.0.1:19645";
const key = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const owner = new ethers.Wallet(key).address;
const env = {...process.env, PATH: `${bin}:${process.env.PATH}`, RPC_URL: rpc, PRIVATE_KEY: key,
    RESOLVER_ADDRESS: "0x0000000000000000000000000000000000000000"};
function run(command, args, extra = {}) {
    const r = spawnSync(command, args, {cwd: root, env: {...env, ...extra}, encoding: "utf8", timeout: 240000, maxBuffer: 20000000});
    assert.equal(r.status, 0, `${command} ${args.join(" ")}\n${r.stdout}\n${r.stderr}`);
    return r.stdout;
}
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test("fresh simulation, interrupted broadcast and native resume", {timeout: 300000}, async () => {
    // Keep local test broadcast artifacts separate from operator invocations.
    fs.mkdirSync(path.join(root, ".tmp"), {recursive: true});
    const artifacts = fs.mkdtempSync(path.join(root, ".tmp/framework-local-"));
    const localEnv = {FOUNDRY_BROADCAST: artifacts};
    const anvil = spawn(`${bin}/anvil`, ["--port", "19645", "--gas-limit", "100000000", "--block-time", "1", "--silent"], {stdio: "ignore"});
    const provider = new ethers.providers.JsonRpcProvider(rpc);
    let deployment;
    try {
        for (let i = 0; ; ++i) {
            try { await provider.getBlockNumber(); break; } catch { assert.ok(i < 60, "anvil startup"); await pause(250); }
        }
        run("new-ops-scripts/deploy-erc1820.sh", ["eth-sepolia", "--broadcast"]);
        const nonce = await provider.getTransactionCount(owner);
        const plan = run("new-ops-scripts/framework.sh", ["eth-sepolia", "fresh"], localEnv);
        assert.equal(await provider.getTransactionCount(owner), nonce, "dry-run broadcast");
        const host = plan.match(/HOST_ADDRESS (0x[0-9a-fA-F]{40})/)[1];
        const resolver = plan.match(/RESOLVER_ADDRESS (0x[0-9a-fA-F]{40})/)[1];
        assert.equal(await provider.getCode(host), "0x");
        let output = "";
        deployment = spawn("new-ops-scripts/framework.sh", ["eth-sepolia", "fresh", "--broadcast"],
            {cwd: root, env: {...env, ...localEnv}, detached: true, stdio: ["ignore", "pipe", "pipe"]});
        deployment.stdout.on("data", (d) => { output += d; });
        deployment.stderr.on("data", (d) => { output += d; });
        const stopped = new Promise((resolve) => deployment.once("exit", resolve));
        for (let i = 0; ; ++i) {
            assert.equal(deployment.exitCode, null, output);
            if ((await provider.getTransactionCount(owner)) >= nonce + 5) break;
            assert.ok(i < 240, output);
            await pause(250);
        }
        process.kill(-deployment.pid, "SIGINT");
        await stopped;
        const partialNonce = await provider.getTransactionCount(owner);
        const resume = run("new-ops-scripts/framework.sh", ["eth-sepolia", "fresh", "--resume"], localEnv);
        assert.match(resume, /ONCHAIN EXECUTION COMPLETE/);
        assert.ok(await provider.getTransactionCount(owner) > partialNonce, "No remaining transactions resumed");
        assert.notEqual(await provider.getCode(host), "0x");
        // Run the maintained validator directly with the actual local provider.
        run("node", ["-r", "ts-node/register", "-e", `const h=require('hardhat'); h.ethers.provider=new h.ethers.providers.JsonRpcProvider('${rpc}'); require('./new-ops-scripts/validate-deployment.ts');`],
            {RESOLVER_ADDRESS: resolver});
        const finalNonce = await provider.getTransactionCount(owner);
        run("new-ops-scripts/framework.sh", ["eth-sepolia", "fresh", "--resume"], localEnv);
        assert.equal(await provider.getTransactionCount(owner), finalNonce, "Completed resume deployed duplicates");
        const duplicate = spawnSync("new-ops-scripts/framework.sh", ["eth-sepolia", "fresh", "--broadcast"],
            {cwd: root, env: {...env, ...localEnv}, encoding: "utf8"});
        assert.notEqual(duplicate.status, 0);
        assert.match(duplicate.stderr, /Fresh broadcast artifacts already exist/);
        const refused = spawnSync("new-ops-scripts/framework.sh", ["eth-sepolia", "fresh", "--broadcast"],
            {cwd: root, env: {...env, ...localEnv, NON_UPGRADABLE: "true"}, encoding: "utf8"});
        assert.notEqual(refused.status, 0);
        assert.match(refused.stderr, /NON_UPGRADABLE is retired/);
        const all = spawnSync("new-ops-scripts/framework.sh", ["eth-sepolia", "upgrade-tokens", "ALL", "--broadcast"],
            {cwd: root, env: {...env, ...localEnv}, encoding: "utf8"});
        assert.notEqual(all.status, 0);
        assert.match(all.stderr, /ALL token discovery is not implemented/);
        assert.equal(await provider.getTransactionCount(owner), finalNonce, "Unsupported command broadcast");
        run("new-ops-scripts/framework.sh", ["eth-sepolia", "provision-test-token", "Fake USDC", "fUSDC", "6", "1000000000000", "--broadcast"],
            {...localEnv, RESOLVER_ADDRESS: resolver});
        const r = new ethers.Contract(resolver, ["function get(string) view returns(address)"], provider);
        const faucet = new ethers.Contract(await r.get("tokens.fUSDC"), ["function decimals() view returns(uint8)"], provider);
        assert.equal(await faucet.decimals(), 6);
        assert.notEqual(await r.get("supertokens.v1.fUSDCx"), ethers.constants.AddressZero);
        console.log(JSON.stringify({host, resolver, nonce, partialNonce, finalNonce, result: "validator passed; resume deployed no duplicates"}));
    } finally {
        if (deployment && deployment.exitCode === null) { try { process.kill(-deployment.pid, "SIGTERM"); } catch {} }
        anvil.kill();
        fs.rmSync(artifacts, {recursive: true, force: true});
    }
});
