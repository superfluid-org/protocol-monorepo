const assert = require("node:assert/strict");
const test = require("node:test");
const {verificationArgs} = require("../../new-ops-scripts/verify-framework");
const {parseOptions} = require("../../new-ops-scripts/lib/framework-discovery");

test("UUPS proxy source verification has no constructor or implementation constructor arguments", () => {
    const args = verificationArgs(
        {
            address: "0x0000000000000000000000000000000000000001",
            contract: "contracts/upgradability/UUPSProxy.sol:UUPSProxy",
            constructorArgs: "0x",
            libraries: {},
        },
        {chainId: 1},
        {verifier: "blockscout", verifierUrl: "https://example.invalid/api"}
    );
    assert.ok(!args.includes("--constructor-args"));
    assert.deepEqual(args.slice(-2), [
        "--verifier-url",
        "https://example.invalid/api",
    ]);
});

test("unsupported explorer proxy association fails during argument parsing", () => {
    assert.throws(
        () => parseOptions(["eth-sepolia", "--verify-proxy"]),
        /not implemented/
    );
    assert.throws(
        () => parseOptions(["eth-sepolia", "--constructor-args-file"]),
        /missing value/
    );
});
