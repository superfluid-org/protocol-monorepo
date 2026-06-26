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
            const {poolAdminNFTProxy, paNFTLogicAddress} =
                await t.deployNFTContracts();
            const superTokenLogic = await t.deployContract<SuperTokenMock>(
                "SuperTokenMock",
                superfluid.address,
                "0",
                poolAdminNFTProxy.address
            );
            const tester =
                await t.deployContract<SuperTokenFactoryStorageLayoutTester>(
                    "SuperTokenFactoryStorageLayoutTester",
                    superfluid.address,
                    superTokenLogic.address,
                    paNFTLogicAddress,
                    ZERO_ADDRESS
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
                const {poolAdminNFTProxy, paNFTLogicAddress} =
                    await t.deployNFTContracts();
                const superTokenLogic = await t.deployContract<SuperTokenMock>(
                    "SuperTokenMock",
                    superfluid.address,
                    42,
                    poolAdminNFTProxy.address
                );
                const factory2Logic =
                    await t.deployContract<SuperTokenFactoryMock42>(
                        "SuperTokenFactoryMock42",
                        superfluid.address,
                        superTokenLogic.address,
                        paNFTLogicAddress,
                        ZERO_ADDRESS
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

                const {poolAdminNFTProxy} = await t.deployNFTContracts();
                const superTokenLogic = await t.deployContract<SuperTokenMock>(
                    "SuperTokenMock",
                    superfluid.address,
                    69,
                    poolAdminNFTProxy.address
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
                const {poolAdminNFTProxy, paNFTLogicAddress} =
                    await t.deployNFTContracts();
                const superTokenLogic = await t.deployContract<SuperToken>(
                    "SuperToken",
                    superfluid.address,
                    poolAdminNFTProxy.address
                );
                const factory2Logic =
                    await t.deployContract<SuperTokenFactoryMock42>(
                        "SuperTokenFactoryMock42",
                        superfluid.address,
                        superTokenLogic.address,
                        paNFTLogicAddress,
                        ZERO_ADDRESS
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
    });
});
