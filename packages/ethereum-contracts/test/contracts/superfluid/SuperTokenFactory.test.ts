import {assert, ethers, expect, web3} from "hardhat";

import {
    SuperfluidMock,
    SuperToken,
    SuperTokenFactory,
    SuperTokenFactoryMock42,
    SuperTokenFactoryStorageLayoutTester,
    SuperTokenMock,
    TestGovernance,
    TestToken,
    TestToken__factory,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectCustomError, expectRevertedWith} from "../../utils/expectRevert";

const {expectEvent} = require("@openzeppelin/test-helpers");

describe("SuperTokenFactory Contract", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    const {ZERO_ADDRESS} = t.constants;

    let superfluid: SuperfluidMock;
    let governance: TestGovernance;
    let factory: SuperTokenFactory;
    let testTokenFactory: TestToken__factory;
    let token1: TestToken;

    before(async () => {
        await t.beforeTestSuite({
            isTruffle: true,
            nAccounts: 5,
        });

        testTokenFactory = await ethers.getContractFactory("TestToken");
        token1 = await testTokenFactory.deploy(
            "Test Token 1",
            "TT1",
            18,
            ethers.utils.parseUnits((1e12).toString())
        );
        await t.pushEvmSnapshot();

        ({superfluid, governance} = t.contracts);
        factory = await ethers.getContractAt(
            "SuperTokenFactory",
            await superfluid.getSuperTokenFactory()
        );
    });

    after(async () => {
        await t.popEvmSnapshot();
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(async () => {
        t.afterEachTestCaseBenchmark();
    });

    describe("#1 upgradability", () => {
        it("#1.1 storage layout", async () => {
            const {
                poolAdminNFTProxy,
                poolMemberNFTProxy,
                paNFTLogicAddress,
                pmNFTLogicAddress,
            } = await t.deployNFTContracts();
            const superTokenLogic = await t.deployContract<SuperTokenMock>(
                "SuperTokenMock",
                superfluid.address,
                "0",
                t.constants.ZERO_ADDRESS,
                t.constants.ZERO_ADDRESS,
                poolAdminNFTProxy.address,
                poolMemberNFTProxy.address
            );
            const tester =
                await t.deployContract<SuperTokenFactoryStorageLayoutTester>(
                    "SuperTokenFactoryStorageLayoutTester",
                    superfluid.address,
                    superTokenLogic.address,
                    t.constants.ZERO_ADDRESS,
                    t.constants.ZERO_ADDRESS,
                    paNFTLogicAddress,
                    pmNFTLogicAddress
                );
            await tester.validateStorageLayout();
        });

        it("#1.2 proxiable info", async () => {
            const proxiable = await ethers.getContractAt(
                "UUPSProxiable",
                factory.address
            );
            assert.equal(
                await proxiable.proxiableUUID(),
                web3.utils.sha3(
                    "org.superfluid-finance.contracts.SuperTokenFactory.implementation"
                )
            );
        });

        it("#1.3 only host can update the code", async () => {
            assert.equal(await factory.getHost(), superfluid.address);
            await expectCustomError(
                factory.updateCode(ZERO_ADDRESS),
                factory,
                "SUPER_TOKEN_FACTORY_ONLY_HOST"
            );
        });

        it("#1.4 only can initialize once", async () => {
            await expectRevertedWith(
                factory.initialize(),
                "Initializable: contract is already initialized"
            );
        });

        it("#1.5 block initialization of logic contracts", async () => {
            const factoryLogic = await ethers.getContractAt(
                "SuperTokenFactory",
                await factory.getCodeAddress()
            );

            await expectRevertedWith(
                factoryLogic.initialize(),
                "Initializable: contract is already initialized"
            );

            const superTokenLogic = await ethers.getContractAt(
                "SuperTokenMock",
                await factory.getSuperTokenLogic()
            );

            await expectRevertedWith(
                superTokenLogic.initialize(ZERO_ADDRESS, 0, "", ""),
                "Initializable: contract is already initialized"
            );
        });
    });

    describe("#2 createERC20Wrapper", () => {
        context("#2.a Mock factory", () => {
            async function updateSuperTokenFactory() {
                const {
                    poolAdminNFTProxy,
                    poolMemberNFTProxy,
                    paNFTLogicAddress,
                    pmNFTLogicAddress,
                } = await t.deployNFTContracts();
                const superTokenLogic = await t.deployContract<SuperTokenMock>(
                    "SuperTokenMock",
                    superfluid.address,
                    42,
                    t.constants.ZERO_ADDRESS,
                    t.constants.ZERO_ADDRESS,
                    poolAdminNFTProxy.address,
                    poolMemberNFTProxy.address
                );
                const factory2Logic =
                    await t.deployContract<SuperTokenFactoryMock42>(
                        "SuperTokenFactoryMock42",
                        superfluid.address,
                        superTokenLogic.address,
                        t.constants.ZERO_ADDRESS,
                        t.constants.ZERO_ADDRESS,
                        paNFTLogicAddress,
                        pmNFTLogicAddress
                    );
                await governance.updateContracts(
                    superfluid.address,
                    ZERO_ADDRESS,
                    [],
                    factory2Logic.address,
                    ZERO_ADDRESS
                );
                await superfluid.getSuperTokenFactoryLogic();
            }

            it("#2.a.1 non upgradable super token creation is deprecated", async () => {
                await expectCustomError(
                    factory["createERC20Wrapper(address,uint8,string,string)"](
                        token1.address,
                        0,
                        "",
                        ""
                    ),
                    factory,
                    "SUPER_TOKEN_FACTORY_NON_UPGRADEABLE_IS_DEPRECATED"
                );
            });

            it("#2.a.2 semi upgradable", async () => {
                let superToken1 = await t.sf.createERC20Wrapper(token1, {
                    upgradability: 1,
                });
                await expectEvent(superToken1.tx.receipt, "SuperTokenCreated", {
                    token: superToken1.address,
                });
                superToken1 = await ethers.getContractAt(
                    "SuperTokenMock",
                    superToken1.address
                );
                assert.equal((await superToken1.waterMark()).toString(), "0");
                await updateSuperTokenFactory();
                assert.equal((await superToken1.waterMark()).toString(), "0");
                await governance[
                    "batchUpdateSuperTokenLogic(address,address[])"
                ](superfluid.address, [superToken1.address]);
                assert.equal((await superToken1.waterMark()).toString(), "42");
            });

            it("#2.a.3 full upgradable", async () => {
                let superToken1 = await t.sf.createERC20Wrapper(token1, {
                    upgradability: 2,
                });
                const proxy = await ethers.getContractAt(
                    "FullUpgradableSuperTokenProxy",
                    superToken1.address
                );
                await expectEvent(superToken1.tx.receipt, "SuperTokenCreated", {
                    token: superToken1.address,
                });
                superToken1 = await ethers.getContractAt(
                    "SuperTokenMock",
                    superToken1.address
                );
                await updateSuperTokenFactory();
                assert.equal((await superToken1.waterMark()).toString(), "42");
                await expectRevertedWith(
                    governance["batchUpdateSuperTokenLogic(address,address[])"](
                        superfluid.address,
                        [superToken1.address]
                    ),
                    "UUPSProxiable: not upgradable"
                );
                await expectCustomError(
                    proxy.initialize(),
                    proxy,
                    "FUSTP_ALREADY_INITIALIZED"
                );
            });

            it("#2.a.4 Create Custom Token", async () => {
                const CustomSuperTokenProxyMockFactory =
                    await ethers.getContractFactory(
                        "CustomSuperTokenProxyMock"
                    );
                const customToken = await ethers.getContractAt(
                    "CustomSuperTokenMock",
                    (await CustomSuperTokenProxyMockFactory.deploy()).address
                );
                console.log("initializeCustomSuperToken");
                await expect(
                    factory.initializeCustomSuperToken(customToken.address)
                )
                    .to.emit(factory, "CustomSuperTokenCreated")
                    .withArgs(customToken.address);
            });

            it("#2.a.5 upgrade to custom logic", async () => {
                let superToken1 = await t.sf.createERC20Wrapper(token1, {
                    upgradability: 1,
                });
                await expectEvent(superToken1.tx.receipt, "SuperTokenCreated", {
                    token: superToken1.address,
                });
                superToken1 = await ethers.getContractAt(
                    "SuperTokenMock",
                    superToken1.address
                );
                assert.equal((await superToken1.waterMark()).toString(), "0");
                await updateSuperTokenFactory();
                assert.equal((await superToken1.waterMark()).toString(), "0");

                const {poolAdminNFTProxy, poolMemberNFTProxy} =
                    await t.deployNFTContracts();
                const superTokenLogic = await t.deployContract<SuperTokenMock>(
                    "SuperTokenMock",
                    superfluid.address,
                    69,
                    t.constants.ZERO_ADDRESS,
                    t.constants.ZERO_ADDRESS,
                    poolAdminNFTProxy.address,
                    poolMemberNFTProxy.address
                );

                await governance[
                    "batchUpdateSuperTokenLogic(address,address[],address[])"
                ](
                    superfluid.address,
                    [superToken1.address],
                    [superTokenLogic.address]
                );
                assert.equal((await superToken1.waterMark()).toString(), "69");
            });
        });

        context("#2.b Production Factory", () => {
            it("#2.b.1 use production factory to create different super tokens", async () => {
                const {
                    poolAdminNFTProxy,
                    poolMemberNFTProxy,
                    paNFTLogicAddress,
                    pmNFTLogicAddress,
                } = await t.deployNFTContracts();
                const superTokenLogic = await t.deployContract<SuperToken>(
                    "SuperToken",
                    superfluid.address,
                    t.constants.ZERO_ADDRESS,
                    t.constants.ZERO_ADDRESS,
                    poolAdminNFTProxy.address,
                    poolMemberNFTProxy.address
                );
                const factory2Logic =
                    await t.deployContract<SuperTokenFactoryMock42>(
                        "SuperTokenFactoryMock42",
                        superfluid.address,
                        superTokenLogic.address,
                        t.constants.ZERO_ADDRESS,
                        t.constants.ZERO_ADDRESS,
                        paNFTLogicAddress,
                        pmNFTLogicAddress
                    );
                await governance.updateContracts(
                    superfluid.address,
                    ZERO_ADDRESS,
                    [],
                    factory2Logic.address,
                    ZERO_ADDRESS
                );

                await expectCustomError(
                    factory["createERC20Wrapper(address,uint8,string,string)"](
                        token1.address,
                        0,
                        "",
                        ""
                    ),
                    factory,
                    "SUPER_TOKEN_FACTORY_NON_UPGRADEABLE_IS_DEPRECATED"
                );

                const superToken1 = await t.sf.createERC20Wrapper(token1, {
                    upgradability: 1,
                });
                await expectEvent(superToken1.tx.receipt, "SuperTokenCreated", {
                    token: superToken1.address,
                });
                assert.equal(
                    await superToken1.getUnderlyingToken(),
                    token1.address
                );

                const superToken2 = await t.sf.createERC20Wrapper(token1, {
                    upgradability: 2,
                });
                await expectEvent(superToken2.tx.receipt, "SuperTokenCreated", {
                    token: superToken2.address,
                });
                assert.equal(
                    await superToken2.getUnderlyingToken(),
                    token1.address
                );
            });
        });

        it("#2.c.1 should fail on ZERO_ADDRESS", async () => {
            await expectCustomError(
                factory[
                    "createERC20Wrapper(address,uint8,uint8,string,string)"
                ](ZERO_ADDRESS, 18, 0, "name", "symbol"),
                factory,
                "SUPER_TOKEN_FACTORY_ZERO_ADDRESS"
            );
        });

        context("#2.d Canonical Wrapper Super Token Creation", () => {
            context(
                "#2.d.1 Initialize Canonical Wrapper Super Token Function Tests",
                () => {
                    it("#2.d.1a it should throw if not permitted", async () => {
                        const signers = await ethers.getSigners();
                        // only signers[0] is allowed to initialize
                        await expectCustomError(
                            factory
                                .connect(signers[1])
                                .initializeCanonicalWrapperSuperTokens([]),
                            factory,
                            "SUPER_TOKEN_FACTORY_ONLY_GOVERNANCE_OWNER"
                        );
                    });

                    it("#2.d.1b it should be able to call initialize canonical wrapper super tokens", async () => {
                        // create deploy test token promises
                        const deployUnderlyingTokenPromises = Array(5)
                            .fill("")
                            .map(async (_x, i) => {
                                return await testTokenFactory.deploy(
                                    `Test Token ${i}`,
                                    `TT${i}`,
                                    18,
                                    ethers.utils.parseUnits((1e12).toString())
                                );
                            });
                        const underlyingTokens = await Promise.all(
                            deployUnderlyingTokenPromises
                        );

                        expect(
                            await factory.getCanonicalERC20Wrapper(
                                underlyingTokens[0].address
                            )
                        ).to.equal(ethers.constants.AddressZero);

                        // create compute wrapper super token address promises
                        const addressPromises = underlyingTokens.map(
                            async (x) => ({
                                underlyingToken: x.address,
                                superToken: (
                                    await factory.computeCanonicalERC20WrapperAddress(
                                        x.address
                                    )
                                ).superTokenAddress,
                            })
                        );
                        const addresses = await Promise.all(addressPromises);

                        // initialize list of canonical wrappers
                        await factory.initializeCanonicalWrapperSuperTokens(
                            addresses
                        );

                        expect(
                            await factory.getCanonicalERC20Wrapper(
                                addresses[0].underlyingToken
                            )
                        ).to.equal(addresses[0].superToken);
                    });

                    it("#2.d.1c it should throw if already set", async () => {
                        const computedTokenAddress =
                            await factory.computeCanonicalERC20WrapperAddress(
                                token1.address
                            );
                        await factory.initializeCanonicalWrapperSuperTokens([
                            {
                                underlyingToken: ethers.constants.AddressZero,
                                superToken:
                                    computedTokenAddress.superTokenAddress,
                            },
                        ]);
                        await expectCustomError(
                            factory.initializeCanonicalWrapperSuperTokens([]),
                            factory,
                            "SUPER_TOKEN_FACTORY_ALREADY_EXISTS"
                        );
                    });
                }
            );

            it("#2.d.2 it should throw if attempting to create before initialize", async () => {
                expect(
                    await factory.getCanonicalERC20Wrapper(token1.address)
                ).to.equal(ethers.constants.AddressZero);

                await expectCustomError(
                    factory.createCanonicalERC20Wrapper(token1.address),
                    factory,
                    "SUPER_TOKEN_FACTORY_UNINITIALIZED"
                );
            });

            it("#2.d.3 it should properly compute address and use create2", async () => {
                const computedTokenAddress =
                    await factory.computeCanonicalERC20WrapperAddress(
                        token1.address
                    );
                // Initialize arbitrary address as Native Asset SuperToken address
                // Required before using createCanonicalERC20Wrapper
                await factory.initializeCanonicalWrapperSuperTokens([
                    {
                        underlyingToken: ethers.constants.AddressZero,
                        superToken: t.accounts[1],
                    },
                ]);

                // token1 is not deployed yet, so get should return 0 address
                expect(
                    await factory.getCanonicalERC20Wrapper(token1.address)
                ).to.equal(ethers.constants.AddressZero);
                // and isDeployed should equal false
                expect(computedTokenAddress.isDeployed).to.equal(false);

                await expect(
                    factory.createCanonicalERC20Wrapper(token1.address)
                )
                    .to.emit(factory, "SuperTokenCreated")
                    .withArgs(computedTokenAddress.superTokenAddress);

                // erc20 wrapper created canonically, so it should return originally computed address
                expect(
                    await factory.getCanonicalERC20Wrapper(token1.address)
                ).to.equal(computedTokenAddress.superTokenAddress);

                // computed isDeployed should return true now
                const deployedToken =
                    await factory.computeCanonicalERC20WrapperAddress(
                        token1.address
                    );
                // and isDeployed should equal true
                expect(deployedToken.isDeployed).to.equal(true);
            });

            it("#2.d.4 it should not be able to create token twice in a row", async () => {
                // Initialize arbitrary address as Native Asset SuperToken address
                // Required before using createCanonicalERC20Wrapper
                await factory.initializeCanonicalWrapperSuperTokens([
                    {
                        underlyingToken: ethers.constants.AddressZero,
                        superToken: t.accounts[1],
                    },
                ]);

                const computedTokenAddress =
                    await factory.computeCanonicalERC20WrapperAddress(
                        token1.address
                    );
                // initial creation should emit event
                await expect(
                    factory.createCanonicalERC20Wrapper(token1.address)
                )
                    .to.emit(factory, "SuperTokenCreated")
                    .withArgs(computedTokenAddress.superTokenAddress);

                // subsequent attempt reverts
                await expectCustomError(
                    factory.createCanonicalERC20Wrapper(token1.address),
                    factory,
                    "SUPER_TOKEN_FACTORY_ALREADY_EXISTS"
                );
            });

            it("#2.d.5 it should be able to create multiple canonical erc20 wrappers", async () => {
                // Initialize arbitrary address as Native Asset SuperToken address
                // Required before using createCanonicalERC20Wrapper
                await factory.initializeCanonicalWrapperSuperTokens([
                    {
                        underlyingToken: ethers.constants.AddressZero,
                        superToken: t.accounts[1],
                    },
                ]);

                const computedToken1Address =
                    await factory.computeCanonicalERC20WrapperAddress(
                        token1.address
                    );
                await expect(
                    factory.createCanonicalERC20Wrapper(token1.address)
                )
                    .to.emit(factory, "SuperTokenCreated")
                    .withArgs(computedToken1Address.superTokenAddress);

                const token2 = await testTokenFactory.deploy(
                    "Test Token 2",
                    "TT2",
                    18,
                    ethers.utils.parseUnits((1e12).toString())
                );
                const computedToken2Address =
                    await factory.computeCanonicalERC20WrapperAddress(
                        token2.address
                    );
                await expect(
                    factory.createCanonicalERC20Wrapper(token2.address)
                )
                    .to.emit(factory, "SuperTokenCreated")
                    .withArgs(computedToken2Address.superTokenAddress);
            });
        });
    });
});
