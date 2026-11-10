#!/usr/bin/env node
/**
 * Full framework source verification using Foundry's project compiler settings.
 * Usage: bash new-ops-scripts/verify-framework.sh NETWORK [--plan]
 *   [--rpc-url URL] [--release v1] [--host ADDRESS] [--resolver ADDRESS]
 *   [--block NUMBER] [--skip-tokens] [--constructor-args-file FILE]
 *   [--verifier sourcify|etherscan|blockscout] [--verifier-url URL]
 *   [--compiler-version VERSION]
 *
 * Default Sourcify needs no API key. Etherscan uses ETHERSCAN_API_KEY or the
 * existing operator ETHERSCAN_API_V2_KEY. Blockscout requires --verifier-url.
 * --plan only makes RPC reads and writes JSON to stdout: no forge invocation,
 * explorer request, artifact mutation, signing, files, or transactions.
 * Constructor overrides: JSON {"0xDEPLOYED_ADDRESS":"0xABI_ENCODED_ARGS"}.
 * In particular an upgraded beacon needs its ORIGINAL implementation constructor,
 * recovered from its creation ownership log and transaction, never today's logic.
 * Proxy source verification is included; --verify-proxy explorer association is
 * explicitly unsupported. Retry the command after resolving reported failures;
 * forge/explorers recognize already-verified contracts. No bespoke resume state.
 * Verify historical deployments from their matching source checkout/settings.
 * Plans report unsupported historical token implementations separately, without
 * fabricating current-source targets. Actual verification exits unsuccessfully
 * if any discovered implementation remains unsupported.
 */
const { spawnSync } = require("child_process");
const { PACKAGE_ROOT, discoverFramework, loadEnvironment, parseOptions } = require("./lib/framework-discovery");

function verificationArgs(target, snapshot, options) {
    const args = ["verify-contract", target.address, target.contract,
        "--chain-id", String(snapshot.chainId), "--verifier", options.verifier,
        "--watch"];
    if (target.constructorArgs !== "0x") args.push("--constructor-args", target.constructorArgs);
    for (const [library, address] of Object.entries(target.libraries)) args.push("--libraries", `${library}:${address}`);
    if (options.verifierUrl) args.push("--verifier-url", options.verifierUrl);
    if (options.compilerVersion) args.push("--compiler-version", options.compilerVersion);
    return args;
}

async function main() {
    loadEnvironment();
    const options = parseOptions(process.argv.slice(2));
    options.verifier = options.verifier || "sourcify";
    if (!["sourcify", "etherscan", "blockscout"].includes(options.verifier)) throw new Error("Unsupported verifier (choose sourcify, etherscan or blockscout)");
    if (options.verifier === "blockscout" && !options.verifierUrl) throw new Error("Blockscout requires --verifier-url URL");
    const apiKey = process.env.ETHERSCAN_API_KEY || process.env.ETHERSCAN_API_V2_KEY;
    if (!options.plan && options.verifier === "etherscan" && !apiKey) throw new Error("Etherscan verification requires ETHERSCAN_API_KEY (or ETHERSCAN_API_V2_KEY); --plan and Sourcify need no key");
    const snapshot = await discoverFramework(options);
    const commands = snapshot.contracts.map((target) => ({
        label: target.label, address: target.address,
        executable: process.env.FORGE || "forge", args: verificationArgs(target, snapshot, options),
    }));
    if (options.plan) {
        process.stdout.write(`${JSON.stringify({ ...snapshot, mode: "plan", verifier: options.verifier, commands }, null, 2)}\n`);
        if (snapshot.errors.length) process.exitCode = 1;
        return;
    }
    const results = [];
    for (const command of commands) {
        console.error(`Verifying ${command.label} at ${command.address}`);
        const run = spawnSync(command.executable, command.args, {
            cwd: PACKAGE_ROOT,
            env: { ...process.env, ...(apiKey ? { ETHERSCAN_API_KEY: apiKey } : {}) },
            // Reserve stdout for the aggregate machine-readable report.
            stdio: ["ignore", 2, 2],
        });
        results.push({ label: command.label, address: command.address, success: run.status === 0,
            ...(run.status !== 0 ? { exitCode: run.status, error: run.error?.message || run.signal || "forge verification failed; see stderr" } : {}) });
    }
    const failed = results.filter((result) => !result.success);
    process.stdout.write(`${JSON.stringify({ ...snapshot, mode: "verify", verifier: options.verifier, results, failedCount: failed.length + snapshot.errors.length + snapshot.unsupported.length }, null, 2)}\n`);
    if (failed.length || snapshot.errors.length || snapshot.unsupported.length) process.exitCode = 1;
}

if (require.main === module) main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
});

module.exports = { verificationArgs };
