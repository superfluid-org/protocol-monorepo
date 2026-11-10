#!/usr/bin/env node
/**
 * Read-only framework discovery, JSON on stdout (never shell assignments).
 * Usage: node new-ops-scripts/info-print-contract-addresses.js NETWORK
 *   [--rpc-url URL] [--release v1] [--resolver ADDRESS] [--host ADDRESS]
 *   [--block NUMBER] [--skip-tokens] [--constructor-args-file FILE]
 * FILE is a JSON object mapping deployed addresses to ABI-encoded constructor hex.
 * No explorer keys, artifacts, signer or build are required.
 */
const { discoverFramework, loadEnvironment, parseOptions } = require("./lib/framework-discovery");

async function main() {
    loadEnvironment();
    const result = await discoverFramework(parseOptions(process.argv.slice(2)));
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    if (result.errors.length) process.exitCode = 1;
}

if (require.main === module) main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
});
