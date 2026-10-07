const {expect} = require("chai");

const Web3 = require("web3");

const TestEnvironment = require("@superfluid-finance/ethereum-contracts/test/TestEnvironment");
const deployTestToken = require("@superfluid-finance/ethereum-contracts/ops-scripts/deploy-test-token");
const deploySuperToken = require("@superfluid-finance/ethereum-contracts/ops-scripts/deploy-super-token");
const SuperfluidSDK = require("../src");

describe("Framework class", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    let admin;

    before(async function () {
        await t.beforeTestSuite({
            isTruffle: false,
            web3,
            nAccounts: 1,
        });

        ({admin} = t.aliases);

        await deployTestToken(t.createErrorHandler(), [":", "fDAI"], {
            isTruffle: false,
            web3,
        });
        await deployTestToken(t.createErrorHandler(), [":", "fUSDC"], {
            isTruffle: false,
            web3,
        });
        await deploySuperToken(t.createErrorHandler(), [":", "ETH"], {
            isTruffle: false,
            web3,
        });
        await deploySuperToken(t.createErrorHandler(), [":", "fDAI"], {
            isTruffle: false,
            web3,
        });
        await deploySuperToken(t.createErrorHandler(), [":", "fUSDC"], {
            isTruffle: false,
            web3,
        });
        await t.pushEvmSnapshot();
    });

    after(async () => {
        await t.popEvmSnapshot();
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
    });

    describe("initialization", () => {
        function testLoadedContracts(sf) {
            const {
                IERC20,
                IResolver,
                IERC20Metadata,
                ISuperfluid,
                ISuperToken,
                ISuperTokenFactory,
                IConstantFlowAgreementV1,
                IInstantDistributionAgreementV1,
            } = sf.contracts;

            assert.isDefined(IERC20.abi);
            assert.equal(IERC20.contractName, "IERC20");
            assert.isTrue(
                IERC20.abi.filter((i) => i.name === "Transfer").length > 0
            );

            assert.isDefined(IResolver.abi);
            assert.equal(IResolver.contractName, "IResolver");
            assert.isTrue(
                IResolver.abi.filter((i) => i.name === "get").length > 0
            );

            assert.isDefined(IERC20Metadata.abi);
            assert.equal(IERC20Metadata.contractName, "IERC20Metadata");
            assert.isTrue(
                IERC20Metadata.abi.filter((i) => i.name === "symbol").length > 0
            );

            assert.isDefined(ISuperfluid.abi);
            assert.equal(ISuperfluid.contractName, "ISuperfluid");
            assert.isTrue(
                ISuperfluid.abi.filter((i) => i.name === "callAgreement")
                    .length > 0
            );

            assert.isDefined(ISuperToken.abi);
            assert.equal(ISuperToken.contractName, "ISuperToken");
            assert.isTrue(
                ISuperToken.abi.filter((i) => i.name === "upgrade").length > 0
            );

            assert.isDefined(ISuperTokenFactory.abi);
            assert.equal(ISuperTokenFactory.contractName, "ISuperTokenFactory");
            assert.isTrue(
                ISuperTokenFactory.abi.filter(
                    (i) => i.name === "createERC20Wrapper"
                ).length > 0
            );

            assert.isDefined(IConstantFlowAgreementV1.abi);
            assert.equal(
                IConstantFlowAgreementV1.contractName,
                "IConstantFlowAgreementV1"
            );
            assert.isTrue(
                IConstantFlowAgreementV1.abi.filter(
                    (i) => i.name === "updateFlow"
                ).length > 0
            );

            assert.isDefined(IInstantDistributionAgreementV1.abi);
            assert.equal(
                IInstantDistributionAgreementV1.contractName,
                "IInstantDistributionAgreementV1"
            );
            assert.isTrue(
                IInstantDistributionAgreementV1.abi.filter(
                    (i) => i.name === "createIndex"
                ).length > 0
            );
        }

        it("with native truffle environment", async () => {
            const sf = new SuperfluidSDK.Framework({
                isTruffle: true,
                version: "test",
            });
            await sf.initialize();
            testLoadedContracts(sf);
        });

        it("with non-native truffle environment", async () => {
            const sf = new SuperfluidSDK.Framework({
                web3: new Web3(web3.currentProvider),
                version: "test",
            });
            await sf.initialize();
            testLoadedContracts(sf);
        });

        it("Fail generating gas report without setting gas report type", async () => {
            const sf = new SuperfluidSDK.Framework({
                isTruffle: true,
                version: "test",
            });
            await sf.initialize();
            try {
                sf.generateGasReport("noname");
            } catch (e) {
                assert.equal(e.message, "No gas metering configured");
            }
        });

        it("defaults to version v1", () => {
            const sf = new SuperfluidSDK.Framework({
                isTruffle: true,
            });
            assert.equal(sf.version, "v1");
        });

        describe("token loading", () => {
            it("isSuperTokenListed", async () => {
                const sf = new SuperfluidSDK.Framework({
                    isTruffle: true,
                    tokens: ["ETH", "fUSDC", "fDAI"],
                    version: "test",
                });
                await sf.initialize();

                assert.isTrue(await sf.isSuperTokenListed("ETHx"));
                assert.isTrue(await sf.isSuperTokenListed("fUSDCx"));
                assert.isTrue(await sf.isSuperTokenListed("fDAIx"));

                assert.isFalse(await sf.isSuperTokenListed("ETH"));
                assert.isFalse(await sf.isSuperTokenListed("fUSDC"));
                assert.isFalse(await sf.isSuperTokenListed("fDAI"));
                assert.isFalse(await sf.isSuperTokenListed("fTUSDx"));
                assert.isFalse(await sf.isSuperTokenListed("ABC"));

                assert.isFalse(await sf.isSuperTokenListed(sf.address));
                assert.isFalse(
                    await sf.isSuperTokenListed(sf.tokens.fUSDC.address)
                );
                assert.isTrue(
                    await sf.isSuperTokenListed(sf.tokens.fUSDCx.address)
                );
            });

            it("load all tokens", async () => {
                const sf = new SuperfluidSDK.Framework({
                    isTruffle: true,
                    tokens: ["ETH", "fUSDC", "fDAI"],
                    version: "test",
                });
                await sf.initialize();

                assert.equal(sf.superTokens.ETHx, sf.tokens.ETHx);
                assert.equal(await sf.superTokens.ETHx.symbol(), "ETHx");
                assert.isUndefined(sf.superTokens.ETHx.underlyingToken);

                assert.equal(sf.superTokens.fUSDCx, sf.tokens.fUSDCx);
                assert.equal(await sf.superTokens.fUSDCx.symbol(), "fUSDCx");
                assert.equal(await sf.tokens.fUSDC.symbol(), "fUSDC");
                assert.equal(sf.tokens.fUSDCx.underlyingToken, sf.tokens.fUSDC);

                assert.equal(sf.superTokens.ETHx, sf.tokens.ETHx);
                assert.equal(await sf.superTokens.fDAIx.symbol(), "fDAIx");
                assert.equal(await sf.tokens.fDAI.symbol(), "fDAI");
                assert.equal(sf.tokens.fDAIx.underlyingToken, sf.tokens.fDAI);
            });

            it("load by superToken key", async () => {
                const sf = new SuperfluidSDK.Framework({
                    isTruffle: true,
                    tokens: ["fDAIx"],
                    version: "test",
                });
                await sf.initialize();

                assert.equal(sf.superTokens.fDAIx, sf.tokens.fDAIx);
                assert.equal(await sf.superTokens.fDAIx.symbol(), "fDAIx");
                assert.equal(
                    await sf.tokens.fDAIx.underlyingToken.symbol(),
                    "fDAI"
                );
            });

            it("load by native token symbol", async () => {
                const sf = new SuperfluidSDK.Framework({
                    isTruffle: true,
                    tokens: ["ETH"],
                    version: "test",
                });
                await sf.initialize();

                assert.equal(sf.superTokens.ETHx, sf.tokens.ETHx);
                assert.equal(sf.superTokens.ETHx.superTokenCustomType, "SETH");
                assert.equal(await sf.superTokens.ETHx.symbol(), "ETHx");
            });

            it("use loadSuperNativeToken option", async () => {
                const sf = new SuperfluidSDK.Framework({
                    isTruffle: true,
                    loadSuperNativeToken: true,
                    version: "test",
                });
                await sf.initialize();

                assert.equal(sf.superTokens.ETHx, sf.tokens.ETHx);
                assert.equal(sf.superTokens.ETHx.superTokenCustomType, "SETH");
                assert.equal(await sf.superTokens.ETHx.symbol(), "ETHx");
            });

            it("load by native token symbol plus x", async () => {
                const sf = new SuperfluidSDK.Framework({
                    isTruffle: true,
                    tokens: ["ETHx"],
                    version: "test",
                });
                await sf.initialize();

                assert.equal(sf.superTokens.ETHx, sf.tokens.ETHx);
                assert.equal(sf.superTokens.ETHx.superTokenCustomType, "SETH");
                assert.equal(await sf.superTokens.ETHx.symbol(), "ETHx");
            });

            it("load by superToken address", async () => {
                const sf = new SuperfluidSDK.Framework({
                    isTruffle: true,
                    version: "test",
                });
                await sf.initialize();

                const fDAIxAddress = (
                    await sf.resolver.get("supertokens.test.fDAIx")
                ).toLowerCase();
                await sf.loadToken(fDAIxAddress);

                assert.equal(
                    sf.superTokens[fDAIxAddress].address.toLowerCase(),
                    fDAIxAddress
                );
                assert.equal(
                    await sf.superTokens[fDAIxAddress].symbol(),
                    "fDAIx"
                );
                assert.isUndefined(await sf.tokens.fDAI);
                assert.isUndefined(await sf.tokens.fDAIx);
                assert.equal(
                    await sf.superTokens[fDAIxAddress].underlyingToken.symbol(),
                    "fDAI"
                );
            });

            it("registered in resolver", async () => {
                const sf = new SuperfluidSDK.Framework({
                    isTruffle: true,
                    tokens: ["fUSDCx", "fDAIx"],
                    version: "test",
                });
                await sf.initialize();
                assert.equal(await sf.tokens.fUSDC.symbol(), "fUSDC");
                assert.equal(await sf.tokens.fDAI.symbol(), "fDAI");
                assert.equal(await sf.tokens.fUSDCx.symbol(), "fUSDCx");
                assert.equal(await sf.tokens.fDAIx.symbol(), "fDAIx");
            });

            it("failed due to unregistered in resolver", async () => {
                const sf = new SuperfluidSDK.Framework({
                    tokens: ["fML"],
                    isTruffle: true,
                    version: "test",
                });
                try {
                    await sf.initialize();
                    expect.fail("expected initialize to revert");
                } catch (error) {
                    expect(error.message).to.include(
                        "Super Token for fML cannot be found"
                    );
                }
            });

            it("failed due to no super token wrapper", async () => {
                await deployTestToken(
                    t.createErrorHandler(),
                    [":", "SASHIMI"],
                    {
                        from: admin,
                        isTruffle: true,
                    }
                );
                const sf = new SuperfluidSDK.Framework({
                    isTruffle: true,
                    tokens: ["SASHIMI"],
                    version: "test",
                });
                try {
                    await sf.initialize();
                    expect.fail("expected initialize to revert");
                } catch (error) {
                    expect(error.message).to.include(
                        "Super Token for SASHIMI cannot be found"
                    );
                }
            });
        });
    });

    describe("createERC20Wrapper", () => {
        let sf;

        beforeEach(async () => {
            sf = new SuperfluidSDK.Framework({
                isTruffle: true,
                gasReportType: "HTML",
                version: "test",
            });

            await sf.initialize();
        });

        it("create new super token", async () => {
            await deployTestToken(t.createErrorHandler(), [":", "MISO"], {
                isTruffle: true,
                from: admin,
            });
            const misoAddress = await sf.resolver.get("tokens.MISO");
            const misoToken = await sf.contracts.IERC20Metadata.at(misoAddress);
            const superMisoToken = await sf.createERC20Wrapper(misoToken, {
                from: admin,
            });
            assert.equal(
                await superMisoToken.getUnderlyingToken.call(),
                misoAddress
            );
        });

        after(() => {
            sf.generateGasReport("Framework.test");
        });
    });
});
