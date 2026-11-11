const assert = require("node:assert/strict");
const test = require("node:test");
const {verificationArgs} = require("../../new-ops-scripts/verify-framework");
const {parseOptions} = require("../../new-ops-scripts/lib/framework-discovery");
const {
    discoverFramework,
} = require("../../new-ops-scripts/lib/framework-discovery");
const http = require("node:http");

test("forge payload preserves constructor arguments and independently addressed linked libraries", () => {
    const target = {
        address: "0x0000000000000000000000000000000000000001",
        contract:
            "contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol:GeneralDistributionAgreementV1",
        constructorArgs: `0x${"12".repeat(32)}`,
        libraries: {
            "contracts/libs/SlotsBitmapLibrary.sol:SlotsBitmapLibrary":
                "0x0000000000000000000000000000000000000002",
            "contracts/agreements/gdav1/SuperfluidPoolDeployerLibrary.sol:SuperfluidPoolDeployerLibrary":
                "0x0000000000000000000000000000000000000003",
        },
    };
    const args = verificationArgs(
        target,
        {chainId: 11155111},
        {verifier: "sourcify"}
    );
    assert.deepEqual(args, [
        "verify-contract",
        target.address,
        target.contract,
        "--chain-id",
        "11155111",
        "--verifier",
        "sourcify",
        "--watch",
        "--constructor-args",
        target.constructorArgs,
        "--libraries",
        "contracts/libs/SlotsBitmapLibrary.sol:SlotsBitmapLibrary:0x0000000000000000000000000000000000000002",
        "--libraries",
        "contracts/agreements/gdav1/SuperfluidPoolDeployerLibrary.sol:" +
            "SuperfluidPoolDeployerLibrary:0x0000000000000000000000000000000000000003",
    ]);
    assert.ok(!args.some((arg) => /broadcast|private-key|account/.test(arg)));
});

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

test("discovery honors environment host and explicit host takes precedence", async () => {
    const server = http.createServer(async (req, res) => {
        let body = "";
        for await (const chunk of req) body += chunk;
        const request = JSON.parse(body);
        const results = {
            eth_chainId: "0xaa36a7",
            net_version: "11155111",
            eth_getCode: "0x",
            eth_getBlockByNumber: {
                hash: `0x${"11".repeat(32)}`,
                parentHash: `0x${"22".repeat(32)}`,
                number: "0x0",
                timestamp: "0x1",
                nonce: "0x0000000000000000",
                difficulty: "0x0",
                gasLimit: "0x100000",
                gasUsed: "0x0",
                miner: "0x0000000000000000000000000000000000000001",
                extraData: "0x",
                transactions: [],
            },
        };
        res.setHeader("content-type", "application/json");
        res.end(
            JSON.stringify({
                jsonrpc: "2.0",
                id: request.id,
                result: results[request.method],
            })
        );
    });
    await new Promise((resolve) => server.listen(19330, "127.0.0.1", resolve));
    const original = process.env.HOST_ADDRESS;
    try {
        const environmentHost = "0x0000000000000000000000000000000000000011";
        const explicitHost = "0x0000000000000000000000000000000000000022";
        process.env.HOST_ADDRESS = environmentHost;
        const options = {
            network: "eth-sepolia",
            release: "v1",
            block: 0,
            rpcUrl: "http://127.0.0.1:19330",
            skipTokens: true,
        };
        assert.equal(
            (await discoverFramework(options)).addresses.SUPERFLUID_HOST_PROXY,
            environmentHost
        );
        assert.equal(
            (await discoverFramework({...options, host: explicitHost}))
                .addresses.SUPERFLUID_HOST_PROXY,
            explicitHost
        );
    } finally {
        if (original === undefined) delete process.env.HOST_ADDRESS;
        else process.env.HOST_ADDRESS = original;
        await new Promise((resolve) => server.close(resolve));
    }
});
