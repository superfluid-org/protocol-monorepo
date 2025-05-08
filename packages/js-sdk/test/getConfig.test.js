const {assert} = require("chai");
const SuperfluidSDK = require("../src");

describe("getConfig", () => {
    before(() => {
        delete process.env.RESOLVER_ADDRESS;
    });

    it("polygon v1", async () => {
        const config = SuperfluidSDK.getConfig(137, "v1");
        assert.isNotEmpty(config.resolverAddress);
        assert.isNotEmpty(config.subgraphQueryEndpoint);
        assert.isUndefined(config.versions);
    });

    it("polygon test", async () => {
        const config = SuperfluidSDK.getConfig(137, "test");
        assert.isNotEmpty(config.resolverAddress);
        assert.isUndefined(config.subgraphQueryEndpoint);
        assert.isUndefined(config.versions);
    });

    it("defaultConfig", async () => {
        // defaultConfig
        const defaultConfig = SuperfluidSDK.getConfig(8888);
        assert.isUndefined(defaultConfig.resolverAddress);
        assert.isUndefined(defaultConfig.versions);
    });

    it("defaultConfig overriding RESOLVER_ADDRESS", async () => {
        // test environment
        process.env.RESOLVER_ADDRESS = "0x42";
        const testConfig = SuperfluidSDK.getConfig(5555);
        assert.equal(testConfig.resolverAddress, "0x42");
        assert.isUndefined(testConfig.versions);
        delete process.env.RESOLVER_ADDRESS;
    });
});
