const {test} = require("node:test");
const assert = require("node:assert/strict");
const {spawn, spawnSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const {ethers} = require("ethers");
const root = path.resolve(__dirname, "../..");

test(
    "Safe CLI defaults to no proposal and rejects simulated or wrong-chain submissions",
    {timeout: 60000},
    async () => {
        const port = process.env.SAFE_LOCAL_PORT || "19601";
        const rpc = `http://127.0.0.1:${port}`;
        const anvil = spawn("anvil", ["--port", port, "--silent"], {
            stdio: "ignore",
        });
        const provider = new ethers.providers.JsonRpcProvider(rpc);
        fs.mkdirSync(path.join(root, ".tmp"), {recursive: true});
        const dir = fs.mkdtempSync(path.join(root, ".tmp/safe-local-"));
        const file = path.join(dir, "payload.jsonl");
        const payload = {
            safeAddress: "0x0000000000000000000000000000000000000001",
            to: "0x0000000000000000000000000000000000000002",
            data: "0x",
            chainId: "31337",
            simulated: true,
        };
        const invoke = (broadcast = false) =>
            spawnSync(
                "node",
                [
                    "-r",
                    "ts-node/register",
                    "new-ops-scripts/safe-ops.ts",
                    "propose-file",
                    "--rpc-url",
                    rpc,
                    "--payload-file",
                    file,
                    "--mode",
                    "single",
                    ...(broadcast ? ["--broadcast"] : []),
                ],
                {
                    cwd: root,
                    env: {...process.env, SAFE_PROPOSER_PK: ""},
                    encoding: "utf8",
                }
            );
        try {
            for (let i = 0; ; ++i) {
                try {
                    await provider.getBlockNumber();
                    break;
                } catch {
                    assert.ok(i < 60, "anvil startup");
                    await new Promise((resolve) => setTimeout(resolve, 100));
                }
            }
            fs.writeFileSync(file, JSON.stringify(payload));
            const preview = invoke();
            assert.equal(preview.status, 0, preview.stderr);
            assert.match(preview.stdout, /Captured Safe transaction payloads/);
            const simulated = invoke(true);
            assert.notEqual(simulated.status, 0);
            assert.match(simulated.stderr, /Simulated or unbound Safe payload/);
            payload.simulated = false;
            fs.writeFileSync(file, JSON.stringify(payload));
            const requiresSigner = invoke(true);
            assert.notEqual(requiresSigner.status, 0);
            assert.match(requiresSigner.stderr, /SAFE_PROPOSER_PK/);
            payload.chainId = "1";
            fs.writeFileSync(file, JSON.stringify(payload));
            const wrongChain = invoke();
            assert.notEqual(wrongChain.status, 0);
            assert.match(wrongChain.stderr, /chainId does not match RPC/);
        } finally {
            anvil.kill();
            fs.rmSync(dir, {recursive: true, force: true});
        }
    }
);
