import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {expect} from "chai";
import {Interface} from "ethers/lib/utils";
import {artifacts, assert, ethers, web3} from "hardhat";

import {
    AgreementMock,
    AgreementMock__factory,
    ERC777SenderRecipientMock,
    ForwarderMock,
    SuperAppMock,
    SuperAppMock__factory,
    SuperAppMockWithRegistrationKey__factory,
    SuperfluidMock,
    SuperToken,
    SuperTokenFactory,
    SuperTokenMock,
    TestGovernance,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {
    expectCustomError,
    expectReverted,
    expectRevertedWith,
} from "../../utils/expectRevert";
import {toBN, toWad} from "../utils/helpers";

describe("Superfluid Host Contract", function () {
    this.timeout(300e3);

    const t = TestEnvironment.getSingleton();
    let superAppMockFactory: SuperAppMock__factory;
    let superAppMockInterface: Interface;
    let agreementMockFactory: AgreementMock__factory;
    let agreementMockInterface: Interface;

    let admin: string, alice: string, bob: string;
    const {MAX_UINT256, ZERO_ADDRESS} = t.constants;

    context("Upgradable deployment", () => {
        let governance: TestGovernance;
        let superfluid: SuperfluidMock;

        before(async () => {
            await t.beforeTestSuite({
                isTruffle: true,
                nAccounts: 3,
            });

            ({admin, alice, bob} = t.aliases);
            ({superfluid, governance} = t.contracts);
            agreementMockFactory =
                await ethers.getContractFactory("AgreementMock");
            agreementMockInterface = agreementMockFactory.interface;
            superAppMockFactory =
                await ethers.getContractFactory("SuperAppMock");
            superAppMockInterface = superAppMockFactory.interface;
        });

        beforeEach(async function () {
            await t.beforeEachTestCase();
            t.beforeEachTestCaseBenchmark(this);
        });

        afterEach(async () => {
            t.afterEachTestCaseBenchmark();
        });

        async function createAgreementMock(type: string, version: number) {
            const agreementMockFactory =
                await ethers.getContractFactory("AgreementMock");
            return agreementMockFactory.deploy(
                superfluid.address,
                type,
                version
            );
        }

        describe("#1 upgradability", () => {
            it("#1.1 storage layout", async () => {
                const T = artifacts.require("SuperfluidUpgradabilityTester");
                const tester = await T.new();
                await tester.validateStorageLayout();
            });

            it("#1.2 proxiable info", async () => {
                assert.equal(
                    await superfluid.proxiableUUID(),
                    web3.utils.sha3(
                        "org.superfluid-finance.contracts.Superfluid.implementation"
                    )
                );
            });

            it("#1.3 only governance can update the code", async () => {
                await expectCustomError(
                    superfluid.updateCode(ZERO_ADDRESS),
                    superfluid,
                    "HOST_ONLY_GOVERNANCE"
                );
            });

            it("#1.4 only can be initialized once", async () => {
                await expectRevertedWith(
                    superfluid.initialize(ZERO_ADDRESS),
                    "Initializable: contract is already initialized"
                );
            });

            it("#1.5 update the code by governance", async () => {
                const sfMockFactory =
                    await ethers.getContractFactory("SuperfluidMock");
                const mock1 = await sfMockFactory.deploy(
                    false /* nonUpgradable */,
                    false /* appWhiteListingEnabled */,
                    3000000 /* callbackGasLimit */,
                    ZERO_ADDRESS /* simpleForwarder */,
                    ZERO_ADDRESS /* erc2771Forwarder */
                );
                const mock2 = await sfMockFactory.deploy(
                    true /* nonUpgradable */,
                    false /* appWhiteListingEnabled */,
                    3000000 /* callbackGasLimit */,
                    ZERO_ADDRESS /* simpleForwarder */,
                    ZERO_ADDRESS /* erc2771Forwarder */
                );
                await governance.updateContracts(
                    superfluid.address,
                    mock1.address,
                    [],
                    ZERO_ADDRESS,
                    ZERO_ADDRESS
                );

                // don't allow initialization of logic contract
                await expectRevertedWith(
                    mock1.initialize(ZERO_ADDRESS),
                    "Initializable: contract is already initialized"
                );

                assert.equal(await superfluid.getCodeAddress(), mock1.address);
                await expectCustomError(
                    governance.updateContracts(
                        superfluid.address,
                        mock2.address,
                        [],
                        ZERO_ADDRESS,
                        ZERO_ADDRESS
                    ),
                    superfluid,
                    "HOST_CANNOT_DOWNGRADE_TO_NON_UPGRADEABLE"
                );
            });

            it("#1.6 context struct layout", async () => {
                const T = artifacts.require("SuperfluidUpgradabilityTester");
                const tester = await T.new();
                await tester.validateContextStructLayout();
            });
        });

        describe("#2 Agreement Whitelisting", async () => {
            it("#2.1 Agreement whitelisting operations", async () => {
                const N_DEFAULT_AGREEMENTS = (
                    await superfluid.mapAgreementClasses(MAX_UINT256)
                ).length;
                const typeA = web3.utils.sha3("typeA")!;
                const typeB = web3.utils.sha3("typeB")!;
                const mockA = await createAgreementMock(typeA, 1);
                const mockAFake = await createAgreementMock(typeA, 42);
                const mockB = await createAgreementMock(typeB, 1);
                const mockA2 = await createAgreementMock(typeA, 2);
                assert.isFalse(await superfluid.isAgreementTypeListed(typeA));
                assert.isFalse(await superfluid.isAgreementTypeListed(typeB));
                assert.equal(await mockA.agreementType(), typeA);
                // register typeA
                await governance.registerAgreementClass(
                    superfluid.address,
                    mockA.address
                );
                console.debug(
                    "Agreement classes",
                    await superfluid.mapAgreementClasses(MAX_UINT256)
                );
                const mockAProxy = await ethers.getContractAt(
                    "AgreementMock",
                    await superfluid.getAgreementClass(typeA)
                );
                assert.equal((await mockAProxy.version()).toString(), "1");
                assert.equal(
                    await mockA.agreementType(),
                    await mockAProxy.agreementType()
                );
                assert.isTrue(await superfluid.isAgreementTypeListed(typeA));
                assert.isTrue(
                    await superfluid.isAgreementClassListed(mockAProxy.address)
                );
                assert.isFalse(
                    await superfluid.isAgreementClassListed(mockA.address)
                );
                assert.isFalse(
                    await superfluid.isAgreementClassListed(mockAFake.address)
                );
                assert.isFalse(await superfluid.isAgreementTypeListed(typeB));
                assert.deepEqual(
                    (await superfluid.mapAgreementClasses(MAX_UINT256)).slice(
                        -1
                    ),
                    [mockAProxy.address]
                );

                // register typeB
                console.log("registerAgreementClass typeB started");
                await governance.registerAgreementClass(
                    superfluid.address,
                    mockB.address
                );
                console.debug(
                    "Agreement classes",
                    await superfluid.mapAgreementClasses(MAX_UINT256)
                );
                const mockBProxy = await ethers.getContractAt(
                    "AgreementMock",
                    await superfluid.getAgreementClass(typeB)
                );
                assert.equal((await mockBProxy.version()).toString(), "1");
                assert.equal(
                    await mockB.agreementType(),
                    await mockBProxy.agreementType()
                );
                assert.isTrue(await superfluid.isAgreementTypeListed(typeA));
                assert.isTrue(
                    await superfluid.isAgreementClassListed(mockAProxy.address)
                );
                assert.isTrue(await superfluid.isAgreementTypeListed(typeB));
                assert.isTrue(
                    await superfluid.isAgreementClassListed(mockBProxy.address)
                );
                assert.deepEqual(
                    (await superfluid.mapAgreementClasses(MAX_UINT256)).slice(
                        -2
                    ),
                    [mockAProxy.address, mockBProxy.address]
                );

                // upgrade typeA
                await governance.updateContracts(
                    superfluid.address,
                    ZERO_ADDRESS,
                    [mockA2.address],
                    ZERO_ADDRESS,
                    ZERO_ADDRESS
                );
                console.debug(
                    "Agreement classes",
                    await superfluid.mapAgreementClasses(MAX_UINT256)
                );
                const mockAProxy2 = await ethers.getContractAt(
                    "AgreementMock",
                    await superfluid.getAgreementClass(typeA)
                );
                assert.equal(mockAProxy2.address, mockAProxy.address);
                assert.equal((await mockAProxy2.version()).toString(), "2");

                // bitmap operations
                assert.equal(
                    toBN(MAX_UINT256)
                        .xor(
                            toBN(
                                await superfluid.removeFromAgreementClassesBitmap(
                                    MAX_UINT256,
                                    typeA
                                )
                            )
                        )
                        .toString(),
                    toBN(1).shl(N_DEFAULT_AGREEMENTS).toString()
                );
                assert.equal(
                    toBN(MAX_UINT256)
                        .xor(
                            toBN(
                                await superfluid.removeFromAgreementClassesBitmap(
                                    MAX_UINT256,
                                    typeB
                                )
                            )
                        )
                        .toString(),
                    toBN(1)
                        .shl(N_DEFAULT_AGREEMENTS + 1)
                        .toString()
                );
                assert.equal(
                    (
                        await superfluid.addToAgreementClassesBitmap(
                            (
                                await superfluid.removeFromAgreementClassesBitmap(
                                    MAX_UINT256,
                                    typeA
                                )
                            ).toString(),
                            typeA
                        )
                    ).toString(),
                    MAX_UINT256.toString()
                );
            });

            it("#2.2 only governance can update agreement listings", async () => {
                await expectCustomError(
                    superfluid.registerAgreementClass(ZERO_ADDRESS),
                    superfluid,
                    "HOST_ONLY_GOVERNANCE"
                );
                await expectCustomError(
                    superfluid.updateAgreementClass(ZERO_ADDRESS),
                    superfluid,
                    "HOST_ONLY_GOVERNANCE"
                );
            });

            it("#2.3 only host can update agreement code", async () => {
                await expectCustomError(
                    t.contracts.ida.updateCode(ZERO_ADDRESS),
                    t.contracts.ida,
                    "AGREEMENT_BASE_ONLY_HOST"
                );
            });

            it("#2.4 agreement cannot be registered twice", async () => {
                const typeA = web3.utils.sha3("typeA")!;
                const mockA = await createAgreementMock(typeA, 1);
                const mockA2 = await createAgreementMock(typeA, 2);

                await governance.registerAgreementClass(
                    superfluid.address,
                    mockA.address
                );
                await expectCustomError(
                    governance.registerAgreementClass(
                        superfluid.address,
                        mockA2.address
                    ),
                    superfluid,
                    "HOST_AGREEMENT_ALREADY_REGISTERED"
                );
            });

            // @note previous #2.5 moved to foundry

            it("#2.5 agreement must be registered first", async () => {
                const typeA = web3.utils.sha3("typeA")!;
                const mockA = await createAgreementMock(typeA, 1);

                await expectCustomError(
                    governance.updateContracts(
                        superfluid.address,
                        ZERO_ADDRESS,
                        [mockA.address],
                        ZERO_ADDRESS,
                        ZERO_ADDRESS
                    ),
                    superfluid,
                    "HOST_AGREEMENT_IS_NOT_REGISTERED"
                );

                await expectCustomError(
                    superfluid.getAgreementClass(typeA),
                    superfluid,
                    "HOST_AGREEMENT_IS_NOT_REGISTERED"
                );
                await expectCustomError(
                    superfluid.addToAgreementClassesBitmap(0, typeA),
                    superfluid,
                    "HOST_AGREEMENT_IS_NOT_REGISTERED"
                );
                await expectCustomError(
                    superfluid.removeFromAgreementClassesBitmap(0, typeA),
                    superfluid,
                    "HOST_AGREEMENT_IS_NOT_REGISTERED"
                );
            });

            it("#2.6 mapAgreementClasses", async () => {
                const agreements = await superfluid.mapAgreementClasses(1);
                assert.equal(agreements.length, 1);
                assert.equal(agreements[0], t.contracts.cfa.address);
            });
        });

        describe("#3 Super Token Factory", () => {
            it("#3.1 only governance can update super token factory", async () => {
                await expectCustomError(
                    superfluid.updateSuperTokenFactory(ZERO_ADDRESS),
                    superfluid,
                    "HOST_ONLY_GOVERNANCE"
                );
                await expectCustomError(
                    superfluid.updateSuperTokenLogic(
                        ZERO_ADDRESS,
                        ZERO_ADDRESS
                    ),
                    superfluid,
                    "HOST_ONLY_GOVERNANCE"
                );
            });

            it("#3.2 update super token factory", async () => {
                const factory = await superfluid.getSuperTokenFactory();
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
                const factory2LogicFactory =
                    await ethers.getContractFactory("SuperTokenFactory");
                const factory2Logic = await factory2LogicFactory.deploy(
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
                assert.equal(
                    await superfluid.getSuperTokenFactory(),
                    factory,
                    "Upgradable factory address does not change"
                );
                assert.equal(
                    await superfluid.getSuperTokenFactoryLogic(),
                    factory2Logic.address,
                    "Upgradable factory logic address should change to the new one"
                );
            });

            it("#3.3 update super token factory double check if new code is called", async () => {
                const factory = await superfluid.getSuperTokenFactory();
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
                const factory2LogicFactory = await ethers.getContractFactory(
                    "SuperTokenFactoryUpdateLogicContractsTester"
                );
                const factory2Logic = await factory2LogicFactory.deploy(
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
                assert.equal(
                    await superfluid.getSuperTokenFactory(),
                    factory,
                    "Upgradable factory address does not change"
                );
                assert.equal(
                    await superfluid.getSuperTokenFactoryLogic(),
                    factory2Logic.address,
                    "Upgradable factory logic address should change to the new one"
                );
                const factoryProxy = await ethers.getContractAt(
                    "SuperTokenFactoryUpdateLogicContractsTester",
                    factory
                );
                assert.equal(
                    (await factoryProxy.newVariable()).toString(),
                    ethers.BigNumber.from(0).toString()
                );
            });
        });

        describe("#4 App Registry", () => {
            let superAppMock: SuperAppMock;

            beforeEach(async () => {
                superAppMock = await superAppMockFactory.deploy(
                    superfluid.address,
                    1,
                    false
                );
            });

            it("#4.1 basic app info", async () => {
                assert.isFalse(await superfluid.isApp(governance.address));
                assert.isTrue(await superfluid.isApp(superAppMock.address));
                assert.isFalse(
                    await superfluid.isAppJailed(superAppMock.address)
                );
                assert.equal(
                    await superfluid.getAppCallbackLevel(superAppMock.address),
                    1
                );
                const manifest = await superfluid.getAppManifest(
                    superAppMock.address
                );
                assert.equal(manifest.isSuperApp, true);
                assert.equal(manifest.isJailed, false);
                assert.equal(manifest.noopMask.toString(), "0");
                const nomanifest = await superfluid.getAppManifest(admin);
                assert.equal(nomanifest.isSuperApp, false);
            });

            it("#4.2 app registration rules", async () => {
                await expectCustomError(
                    superAppMock.tryRegisterApp(0),
                    superfluid,
                    "HOST_INVALID_CONFIG_WORD"
                );
            });

            it("#4.3 app registration with bad config", async () => {
                const reason = "HOST_INVALID_CONFIG_WORD";
                await expectCustomError(
                    superAppMockFactory.deploy(superfluid.address, 0, false),
                    superfluid,
                    reason
                );
                await expectCustomError(
                    superAppMockFactory.deploy(
                        superfluid.address,
                        1 | (1 << 15) /* jail bit */,
                        false
                    ),
                    superfluid,
                    reason
                );
                await expectCustomError(
                    superAppMockFactory.deploy(
                        superfluid.address,
                        1 | (1 << 16) /* garbage bit */,
                        false
                    ),
                    superfluid,
                    reason
                );
            });

            it("#4.4 app double registration should fail", async () => {
                await expectCustomError(
                    superAppMockFactory.deploy(superfluid.address, 1, true),
                    superfluid,
                    "HOST_SUPER_APP_ALREADY_REGISTERED"
                );
            });

            it("#4.5 allowCompositeApp", async () => {
                const app2 = await superAppMockFactory.deploy(
                    superfluid.address,
                    2 /* APP_LEVEL_SECOND */,
                    false
                );
                await expectCustomError(
                    superfluid.allowCompositeApp(superAppMock.address),
                    superfluid,
                    "HOST_SENDER_IS_NOT_SUPER_APP"
                );
                await expectCustomError(
                    superAppMock.allowCompositeApp(alice),
                    superfluid,
                    "HOST_RECEIVER_IS_NOT_SUPER_APP"
                );
                await expectCustomError(
                    superAppMock.allowCompositeApp(app2.address),
                    superfluid,
                    "HOST_SOURCE_APP_NEEDS_HIGHER_APP_LEVEL"
                );
                assert.isFalse(
                    await superfluid.isCompositeAppAllowed(
                        superAppMock.address,
                        app2.address
                    )
                );
                await app2.allowCompositeApp(superAppMock.address);
                assert.isTrue(
                    await superfluid.isCompositeAppAllowed(
                        app2.address,
                        superAppMock.address
                    )
                );
            });

            it("#4.6 register app should work", async () => {
                const app2Factory = await ethers.getContractFactory(
                    "SuperAppMockUsingRegisterApp"
                );
                const app2 = await app2Factory.deploy(
                    superfluid.address,
                    1
                ); /* APP_TYPE_FINAL_LEVEL */
                assert.isTrue(await superfluid.isApp(app2.address));
            });

            it("#4.7 app registration as factory by EOA should fail", async () => {
                await expectCustomError(
                    superfluid.registerAppByFactory(ZERO_ADDRESS, 1),
                    superfluid,
                    "HOST_MUST_BE_CONTRACT"
                );
                await expectCustomError(
                    superfluid["registerApp(address,uint256)"](ZERO_ADDRESS, 1),
                    superfluid,
                    "HOST_MUST_BE_CONTRACT"
                );
            });

            it("#4.8 register app by factory", async () => {
                const superAppFactoryMockFactory =
                    await ethers.getContractFactory("SuperAppFactoryMock");
                const appFactoryMock =
                    await superAppFactoryMockFactory.deploy();
                // since whitelisting is disabled, so governance ain't required
                const appFactory = await ethers.getContractFactory(
                    "SuperAppMockNotSelfRegistering"
                );
                const app = await appFactory.deploy();
                assert.isFalse(await superfluid.isApp(app.address));
                await appFactoryMock.registerAppWithHost(
                    superfluid.address,
                    app.address,
                    1 /* APP_TYPE_FINAL_LEVEL */
                );
                assert.isTrue(await superfluid.isApp(app.address));
            });
        });

        // disabled due to contract size limit
        describe("#5 Context Utilities", () => {
            it("#5.1 test replacePlaceholderCtx with testCtxFuncX", async () => {
                const testCtxFunc = async (
                    ctxFuncX: string,
                    args: any[],
                    ctx: string
                ) => {
                    const result = (
                        await superfluid.testCtxFuncX(
                            t.agreementHelper.hostInterface.encodeFunctionData(
                                ctxFuncX,
                                [...args, "0x"]
                            ),
                            ctx
                        )
                    ).slice(2);
                    const expectedResult = t.agreementHelper.hostInterface
                        .encodeFunctionData(ctxFuncX, [...args, ctx])
                        .slice(10);
                    assert.equal(result, expectedResult);
                };

                // test the boundary conditions
                for (let i = 0; i < 33; ++i) {
                    // with 32 bytes boundary padding
                    await testCtxFunc(
                        "ctxFunc1",
                        [42],
                        "0x" + (i % 2 !== 0 ? "0" : "") + "d".repeat(i)
                    );
                }

                // disabled code because contract size limit hit
                // more complicated ABI
                await testCtxFunc(
                    "ctxFunc2",
                    [
                        governance.address,
                        t.contracts.ida.address,
                        ethers.utils.hexZeroPad("0x2020", 32),
                        "0x", // agreementData
                        "0x", // cbdata
                    ],
                    "0x" + "dead".repeat(20)
                );
                await testCtxFunc(
                    "ctxFunc2",
                    [
                        governance.address,
                        t.contracts.ida.address,
                        ethers.utils.hexZeroPad("0x2020", 32),
                        "0xdead", // agreementData
                        "0xbeef", // cbdata
                    ],
                    "0x" + "faec".repeat(20)
                );

                // error case
                await expectCustomError(
                    superfluid.testCtxFuncX(
                        t.agreementHelper.hostInterface.encodeFunctionData(
                            "ctxFunc1",
                            [42, "0x0bad"]
                        ),
                        "0xbeef"
                    ),
                    superfluid,
                    "HOST_NON_ZERO_LENGTH_PLACEHOLDER_CTX"
                );
            });
        });

        describe("#6 Agreement Framework", () => {
            let agreement: AgreementMock;
            let app: SuperAppMock;
            let gasLimit: string;

            before(async () => {
                await t.useLastEvmSnapshot();

                gasLimit = (await superfluid.CALLBACK_GAS_LIMIT()).toString();
                agreement = await createAgreementMock(
                    web3.utils.sha3("MockAgreement")!,
                    0
                );
                await governance.registerAgreementClass(
                    superfluid.address,
                    agreement.address
                );
                agreement = await ethers.getContractAt(
                    "AgreementMock",
                    await superfluid.getAgreementClass(
                        web3.utils.sha3("MockAgreement")!
                    )
                );

                const SuperAppMockFactory =
                    await ethers.getContractFactory("SuperAppMock");
                app = await SuperAppMockFactory.deploy(
                    superfluid.address,
                    1,
                    false
                );

                await t.pushEvmSnapshot();
            });

            after(async () => {
                await t.popEvmSnapshot();
            });

            context("#6.x agreement framework access control", () => {
                it("#6.1 use agreement framework as an EOA", async () => {
                    await expectReverted(
                        superfluid.callAppBeforeCallback(
                            ZERO_ADDRESS,
                            "0x",
                            false,
                            "0x"
                        )
                    );
                    await expectReverted(
                        superfluid.callAppAfterCallback(
                            ZERO_ADDRESS,
                            "0x",
                            false,
                            "0x"
                        )
                    );
                    await expectReverted(
                        superfluid.appCallbackPush(
                            "0x",
                            ZERO_ADDRESS,
                            0,
                            0,
                            ZERO_ADDRESS
                        )
                    );
                    await expectReverted(superfluid.appCallbackPop("0x", 0));
                    await expectReverted(superfluid.ctxUseCredit("0x", 0));
                });

                it("#6.2 use agreement framework as an unregistered agreement", async () => {
                    const reason = "HOST_ONLY_LISTED_AGREEMENT";

                    // call from an unregistered mock agreement
                    const mock = await createAgreementMock(
                        web3.utils.sha3("typeA")!,
                        0
                    );
                    await expectCustomError(
                        mock.tryCallAppBeforeCallback(
                            superfluid.address,
                            app.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryCallAppAfterCallback(
                            superfluid.address,
                            app.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryAppCallbackPush(
                            superfluid.address,
                            app.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryAppCallbackPop(superfluid.address, "0x"),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryCtxUseCredit(
                            superfluid.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryJailApp(
                            superfluid.address,
                            app.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                });

                it("#6.3 use agreement framework as an impersonating agreement", async () => {
                    const reason = "HOST_ONLY_LISTED_AGREEMENT";

                    const mock = await createAgreementMock(
                        await t.contracts.cfa.agreementType(),
                        0
                    );
                    await expectCustomError(
                        mock.tryCallAppBeforeCallback(
                            superfluid.address,
                            app.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryCallAppAfterCallback(
                            superfluid.address,
                            app.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryAppCallbackPush(
                            superfluid.address,
                            app.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryAppCallbackPop(superfluid.address, "0x"),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryCtxUseCredit(
                            superfluid.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                    await expectCustomError(
                        mock.tryJailApp(
                            superfluid.address,
                            app.address,
                            false /* do not hack Ctx */,
                            "0x"
                        ),
                        superfluid,
                        reason
                    );
                });

                it("#6.4 callback will not be called for jailed apps", async () => {
                    await superfluid["jailApp(address)"](app.address);
                    await app.setNextCallbackAction(1 /* assert */, "0x");
                    await superfluid.callAgreement(
                        agreement.address,
                        agreementMockInterface.encodeFunctionData(
                            "callAppAfterAgreementCreatedCallback",
                            [app.address, "0x"]
                        ),
                        "0x"
                    );
                });

                it("#6.5 bad agreement implementations", async () => {
                    await superfluid.callAgreement(
                        agreement.address,
                        agreementMockInterface.encodeFunctionData(
                            "tryCallAppBeforeCallback",
                            [
                                superfluid.address,
                                app.address,
                                false /* do not hack Ctx */,
                                "0x",
                            ]
                        ),
                        "0x"
                    );
                    await expectReverted(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "tryCallAppBeforeCallback",
                                [
                                    superfluid.address,
                                    app.address,
                                    true /* hack the Ctx */,
                                    "0x",
                                ]
                            ),
                            "0x"
                        )
                    );

                    await superfluid.callAgreement(
                        agreement.address,
                        agreementMockInterface.encodeFunctionData(
                            "tryCallAppAfterCallback",
                            [
                                superfluid.address,
                                app.address,
                                false /* do not hack Ctx */,
                                "0x",
                            ]
                        ),
                        "0x"
                    );
                    await expectReverted(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "tryCallAppAfterCallback",
                                [
                                    superfluid.address,
                                    app.address,
                                    true /* hack the Ctx */,
                                    "0x",
                                ]
                            ),
                            "0x"
                        )
                    );

                    await superfluid.callAgreement(
                        agreement.address,
                        agreementMockInterface.encodeFunctionData(
                            "tryAppCallbackPush",
                            [
                                superfluid.address,
                                app.address,
                                false /* do not hack Ctx */,
                                "0x",
                            ]
                        ),
                        "0x"
                    );
                    await expectReverted(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "tryAppCallbackPush",
                                [
                                    superfluid.address,
                                    app.address,
                                    true /* hack the Ctx */,
                                    "0x",
                                ]
                            ),
                            "0x"
                        )
                    );

                    await superfluid.callAgreement(
                        agreement.address,
                        agreementMockInterface.encodeFunctionData(
                            "tryAppCallbackPop",
                            [superfluid.address, "0x"]
                        ),
                        "0x"
                    );
                    // NOTE that tryAppCallbackPop cannot be protected YET

                    await superfluid.callAgreement(
                        agreement.address,
                        agreementMockInterface.encodeFunctionData(
                            "tryCtxUseCredit",
                            [
                                superfluid.address,
                                false,
                                /* do not hack Ctx */ "0x",
                            ]
                        ),
                        "0x"
                    );
                    await expectReverted(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "tryCtxUseCredit",
                                [
                                    superfluid.address,
                                    true /* hack the Ctx */,
                                    "0x",
                                ]
                            ),
                            "0x"
                        )
                    );

                    await superfluid.callAgreement(
                        agreement.address,
                        agreementMockInterface.encodeFunctionData(
                            "tryJailApp",
                            [
                                superfluid.address,
                                app.address,
                                false /* do not hack Ctx */,
                                "0x",
                            ]
                        ),
                        "0x"
                    );
                    await expectReverted(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "tryJailApp",
                                [
                                    superfluid.address,
                                    app.address,
                                    true /* hack the Ctx */,
                                    "0x",
                                ]
                            ),
                            "0x"
                        )
                    );
                });
            });

            context("#6.1x agreement callback rules", async () => {
                it("#6.10 beforeAgreementCreated callback noop should work", async () => {
                    await app.setNextCallbackAction(0 /* noop */, "0x");
                    const agreementSignature =
                        agreementMockInterface.getSighash(
                            "callAppBeforeAgreementCreatedCallback(address,bytes calldata)"
                        );
                    await expect(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        )
                    )
                        .to.emit(agreement, "AppBeforeCallbackResult")
                        .withArgs(
                            0,
                            1,
                            agreementSignature,
                            "0x" + Buffer.from("Noop").toString("hex")
                        );
                });

                it("#6.11 beforeAgreementCreated callback assert or revert", async () => {
                    await app.setNextCallbackAction(1 /* assert */, "0x");
                    await expectRevertedWith(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        ),
                        "CallUtils: target panicked: 0x01"
                    );

                    await app.setNextCallbackAction(2 /* revert */, "0x");
                    await expectRevertedWith(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        ),
                        "CallUtils: target revert()"
                    );

                    await app.setNextCallbackAction(
                        3 /* revert with reason */,
                        web3.eth.abi.encodeParameter("string", "error 42")
                    );
                    await expectRevertedWith(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        ),
                        "error 42"
                    );
                });

                it("#6.12 afterAgreementCreated callback noop should work", async () => {
                    await app.setNextCallbackAction(0 /* noop */, "0x");
                    const agreementSignature =
                        agreementMockInterface.getSighash(
                            "callAppAfterAgreementCreatedCallback(address,bytes calldata)"
                        );
                    await expect(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        )
                    )
                        .to.emit(app, "NoopEvent")
                        .withArgs(
                            1,
                            3 /* CALL_INFO_CALL_TYPE_APP_CALLBACK */,
                            agreementSignature
                        )
                        .and.to.emit(agreement, "AppAfterCallbackResult")
                        .withArgs(
                            0,
                            1 /* CALL_INFO_CALL_TYPE_AGREEMENT */,
                            agreementSignature
                        );
                });

                it("#6.13 afterAgreementCreated callback assert or revert", async () => {
                    await app.setNextCallbackAction(1 /* assert */, "0x");
                    await expectRevertedWith(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        ),
                        "CallUtils: target panicked: 0x01"
                    );

                    await app.setNextCallbackAction(2 /* revert */, "0x");
                    await expectRevertedWith(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        ),
                        "CallUtils: target revert()"
                    );

                    await app.setNextCallbackAction(
                        3 /* revert with reason */,
                        web3.eth.abi.encodeParameter("string", "error 42")
                    );
                    await expectRevertedWith(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        ),
                        "error 42"
                    );
                });

                it("#6.14 afterAgreementCreated callback altering ctx", async () => {
                    await app.setNextCallbackAction(4 /* AlteringCtx */, "0x");
                    await expectCustomError(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        ),
                        superfluid,
                        "APP_RULE",
                        t.customErrorCode.APP_RULE_CTX_IS_READONLY
                    );
                });

                it("#6.15 beforeAgreementTerminated callback revert jail rule", async () => {
                    await app.setNextCallbackAction(1 /* assert */, "0x");
                    await expect(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementTerminatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        )
                    )
                        .to.emit(superfluid, "Jail")
                        .withArgs(
                            app.address,
                            10 /* APP_RULE_NO_REVERT_ON_TERMINATION_CALLBACK */
                        );
                    assert.isTrue(await superfluid.isAppJailed(app.address));
                });

                it("#6.16 afterAgreementTerminated callback revert jail rule", async () => {
                    await app.setNextCallbackAction(1 /* assert */, "0x");
                    await expect(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementTerminatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        )
                    )
                        .to.emit(superfluid, "Jail")
                        .withArgs(app.address, 10);
                    assert.isTrue(await superfluid.isAppJailed(app.address));
                });

                it("#6.17 afterAgreementTerminated callback readonly ctx jail rule", async () => {
                    await app.setNextCallbackAction(4 /* AlteringCtx */, "0x");
                    await expect(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementTerminatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        )
                    )
                        .to.emit(superfluid, "Jail")
                        .withArgs(app.address, 20);
                    assert.isTrue(await superfluid.isAppJailed(app.address));
                });

                it("#6.18 agreement callback noops masks", async () => {
                    const tests = [
                        [0, "callAppBeforeAgreementCreatedCallback"],
                        [1, "callAppAfterAgreementCreatedCallback"],
                        [2, "callAppBeforeAgreementUpdatedCallback"],
                        [3, "callAppAfterAgreementUpdatedCallback"],
                        [4, "callAppBeforeAgreementTerminatedCallback"],
                        [5, "callAppAfterAgreementTerminatedCallback"],
                    ];
                    for (let i = 0; i < tests.length; ++i) {
                        console.debug("testing noop mask for", tests[i][1]);

                        const app2Factory =
                            await ethers.getContractFactory("SuperAppMock");
                        const app2 = await app2Factory.deploy(
                            superfluid.address,
                            /* APP_TYPE_FINAL_LEVEL */
                            toBN(1)
                                .add(
                                    // *_NOOP:  1 << (32 + n)
                                    toBN(1).shl(32 + Number(tests[i][0]))
                                )
                                .toString(),
                            false
                        );
                        await app2.setNextCallbackAction(1 /* assert */, "0x");
                        await superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                tests[i][1].toString(),
                                [app2.address, "0x"]
                            ),
                            "0x"
                        );
                    }
                });

                it("#6.19 Jail event should not be emitted twice", async () => {
                    await expect(superfluid["jailApp(address)"](app.address))
                        .to.emit(superfluid, "Jail")
                        .withArgs(app.address, "6942");
                    await expect(
                        superfluid["jailApp(address)"](app.address)
                    ).to.not.emit(superfluid, "Jail");
                });
            });

            context("#6.2x callback gas limit", () => {
                it("#6.20 beforeCreated callback burn all gas", async () => {
                    await app.setNextCallbackAction(
                        5 /* BurnGas */,
                        web3.eth.abi.encodeParameter("uint256", gasLimit)
                    );

                    // burn all the gas
                    await expectRevertedWith(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x"
                        ),
                        "CallUtils: target revert()"
                    );
                });

                it("#6.21 beforeCreated callback try to burn all gas but less gas provided", async () => {
                    await app.setNextCallbackAction(
                        5 /* BurnGas */,
                        web3.eth.abi.encodeParameter("uint256", gasLimit)
                    );

                    // provide less gas
                    await expectCustomError(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x",
                            {
                                gasLimit: Math.ceil(Number(gasLimit) / 2),
                            }
                        ),

                        superfluid,
                        "HOST_NEED_MORE_GAS"
                    );
                });

                it("#6.22 afterTerminated burn all gas", async () => {
                    await app.setNextCallbackAction(
                        5 /* BurnGas */,
                        web3.eth.abi.encodeParameter("uint256", gasLimit)
                    );

                    // provide less gas
                    await expect(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementTerminatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x",
                            {
                                // give enough gas to trigger the error
                                gasLimit: Number(gasLimit) * 2,
                            }
                        )
                    )
                        .to.emit(superfluid, "Jail")
                        .withArgs(app.address, 10);
                    assert.isTrue(await superfluid.isAppJailed(app.address));
                });

                it("#6.23 afterTerminated try to burn all gas but with less gas provided", async () => {
                    await app.setNextCallbackAction(
                        5 /* BurnGas */,
                        web3.eth.abi.encodeParameter("uint256", gasLimit)
                    );

                    // provide less gas
                    await expectCustomError(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app.address, "0x"]
                            ),
                            "0x",
                            {
                                gasLimit: Math.ceil(Number(gasLimit) / 2),
                            }
                        ),
                        superfluid,
                        "HOST_NEED_MORE_GAS"
                    );
                });

                /**
                 * This slow test case is to ensure that a well behaved app callback
                 * is not mistakenly jailed for APP_RULE_NO_REVERT_ON_TERMINATION_CALLBACK.
                 *
                 * It uses the BurnGas operation from the mock super app, which burns as much gas as CALLBACK_GAS_LIMIT
                 * allows (minus a small amount as heuristics for solidity gas overhead). This is a mischievious but
                 * well behaved within the rule.
                 *
                 * To explore the gasLimit possibilities exhaustively in reasonable time, a binary search strategy is
                 * used. The test starts with a gas range that includes the maximum gas limit is used by the mock
                 * app. Then the test case shrinks the range to the point where the range is at a single value.
                 *
                 * This may take awhile, hence it is skipped in coverage test suite.
                 */
                it("#6.24 beforeCreated try to burn just enough gas [ @skip-on-coverage ]", async function () {
                    const setNextAction = async () => {
                        await app.setNextCallbackAction(
                            5 /* BurnGas */,
                            web3.eth.abi.encodeParameter(
                                "uint256",
                                Number(gasLimit - 30000) // leave some space for gas overhead
                            )
                        );
                    };
                    await setNextAction();
                    let tx = await superfluid.callAgreement(
                        agreement.address,
                        agreementMockInterface.encodeFunctionData(
                            "callAppBeforeAgreementCreatedCallback",
                            [app.address, "0x"]
                        ),
                        "0x"
                    );
                    let receipt = await tx.wait();
                    console.debug("Gas used", receipt.gasUsed.toString());
                    let gasLowerBound = Number(receipt.gasUsed.toString());
                    let gasUpperBound = Math.floor(gasLowerBound * 1.3);
                    console.debug(
                        "Current bound",
                        gasLowerBound,
                        gasUpperBound
                    );

                    // binary search proof if there is a price can trigger unexpected revert
                    let gas;
                    let errorCount = 0;
                    let successCount = 0;
                    while (gasLowerBound <= gasUpperBound) {
                        const gap = Math.floor(
                            (gasUpperBound - gasLowerBound) / 2
                        );
                        gas =
                            Number(gasLowerBound.toString()) +
                            Number(gap.toString());
                        console.debug("Trying with new gas limit", gas);
                        try {
                            await setNextAction();
                            tx = await superfluid.callAgreement(
                                agreement.address,
                                agreementMockInterface.encodeFunctionData(
                                    "callAppBeforeAgreementCreatedCallback",
                                    [app.address, "0x"]
                                ),
                                "0x",
                                {
                                    gasLimit: gas,
                                }
                            );
                            receipt = await tx.wait();
                            console.debug(
                                "Gas used",
                                receipt.gasUsed.toString()
                            );
                            console.debug(
                                "No error, decreasing gas with gap",
                                gasLowerBound,
                                gas,
                                gasUpperBound
                            );
                            gasUpperBound = gas;
                            ++errorCount;
                        } catch (error: any) {
                            console.debug("Caught error", error.message);
                            // with error, check error and increase gas
                            assert.isNotNull(
                                error.message.match("HOST_NEED_MORE_GAS()")
                            );
                            console.debug(
                                "Need more gas, increasing gas with gap",
                                gasLowerBound,
                                gas,
                                gasUpperBound
                            );
                            gasLowerBound = gas;
                            ++successCount;
                        }
                        if (gap === 0) break;
                    }
                    assert.isTrue(errorCount > 0, "expect some errors");
                    assert.isTrue(successCount > 0, "expect some success");
                });
            });

            context("#6.3x composite app rules", () => {
                const SuperAppMock2ndLevel = artifacts.require(
                    "SuperAppMock2ndLevel"
                );

                it("#6.30 composite app must be whitelisted", async () => {
                    // assuming MAX_APP_LEVEL = 1
                    // -> mockAgreement.callAppAfterAgreementCreatedCallback(app3)
                    // -> app3.afterAgreementCreated
                    // -> mockAgreement.callAppAfterAgreementCreatedCallback(app)
                    const app3 = await SuperAppMock2ndLevel.new(
                        superfluid.address,
                        app.address,
                        agreement.address
                    );
                    await expectCustomError(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app3.address, "0x"]
                            ),
                            "0x"
                        ),
                        superfluid,
                        "APP_RULE",
                        t.customErrorCode
                            .APP_RULE_COMPOSITE_APP_IS_NOT_WHITELISTED
                    );
                    await app3.allowCompositeApp();
                    await expectCustomError(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app3.address, "0x"]
                            ),
                            "0x"
                        ),
                        superfluid,
                        "APP_RULE",
                        t.customErrorCode.APP_RULE_MAX_APP_LEVEL_REACHED
                    );
                });

                it("#6.31 composite app cannot be jailed", async () => {
                    // assuming MAX_APP_LEVEL = 1
                    // -> mockAgreement.callAppAfterAgreementCreatedCallback(app3)
                    // -> app3.afterAgreementCreated
                    // -> mockAgreement.callAppAfterAgreementCreatedCallback(app) // jailed
                    const app3 = await SuperAppMock2ndLevel.new(
                        superfluid.address,
                        app.address,
                        agreement.address
                    );
                    await expectCustomError(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app3.address, "0x"]
                            ),
                            "0x"
                        ),
                        superfluid,
                        "APP_RULE",
                        t.customErrorCode
                            .APP_RULE_COMPOSITE_APP_IS_NOT_WHITELISTED
                    );
                    await superfluid["jailApp(address)"](app.address);
                    await superfluid.callAgreement(
                        agreement.address,
                        agreementMockInterface.encodeFunctionData(
                            "callAppAfterAgreementCreatedCallback",
                            [app3.address, "0x"]
                        ),
                        "0x"
                    );
                });
            });

            context("#6.4x invalid ctx returned by the callback", () => {
                const SuperAppMock2 = artifacts.require(
                    "SuperAppMockReturningEmptyCtx"
                );
                const SuperAppMock2ndLevel = artifacts.require(
                    "SuperAppMockReturningInvalidCtx"
                );

                it("#6.40 should give explicit error message in non-termination callbacks", async () => {
                    const app2 = await SuperAppMock2.new(superfluid.address);

                    console.debug("callAppBeforeAgreementCreatedCallback");
                    await expectCustomError(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementCreatedCallback",
                                [app2.address, "0x"]
                            ),
                            "0x"
                        ),
                        superfluid,
                        "APP_RULE",
                        t.customErrorCode.APP_RULE_CTX_IS_MALFORMATED
                    );

                    console.debug("callAppAfterAgreementCreatedCallback");
                    await expectCustomError(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app2.address, "0x"]
                            ),
                            "0x"
                        ),
                        superfluid,
                        "APP_RULE",
                        t.customErrorCode.APP_RULE_CTX_IS_MALFORMATED
                    );

                    console.debug("callAppAfterAgreementCreatedCallback");
                    const app3 = await SuperAppMock2ndLevel.new(
                        superfluid.address
                    );
                    await expectCustomError(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementCreatedCallback",
                                [app3.address, "0x"]
                            ),
                            "0x"
                        ),
                        superfluid,
                        "APP_RULE",
                        t.customErrorCode.APP_RULE_CTX_IS_MALFORMATED
                    );
                });

                it("#6.41 should jail the app in termination callbacks", async () => {
                    let app2;

                    app2 = await SuperAppMock2.new(superfluid.address);
                    await expect(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppBeforeAgreementTerminatedCallback",
                                [app2.address, "0x"]
                            ),
                            "0x"
                        )
                    )
                        .to.emit(superfluid, "Jail")
                        .withArgs(app2.address, 22); // APP_RULE_CTX_IS_MALFORMATED
                    assert.isTrue(await superfluid.isAppJailed(app2.address));

                    app2 = await SuperAppMock2.new(superfluid.address);
                    await expect(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementTerminatedCallback",
                                [app2.address, "0x"]
                            ),
                            "0x"
                        )
                    )
                        .to.emit(superfluid, "Jail")
                        .withArgs(app2.address, 22); // APP_RULE_CTX_IS_MALFORMATED
                    assert.isTrue(await superfluid.isAppJailed(app2.address));

                    const app3 = await SuperAppMock2ndLevel.new(
                        superfluid.address
                    );

                    await expect(
                        superfluid.callAgreement(
                            agreement.address,
                            agreementMockInterface.encodeFunctionData(
                                "callAppAfterAgreementTerminatedCallback",
                                [app3.address, "0x"]
                            ),
                            "0x"
                        )
                    )
                        .to.emit(superfluid, "Jail")
                        .withArgs(app3.address, 22); // APP_RULE_CTX_IS_MALFORMATED
                    assert.isTrue(await superfluid.isAppJailed(app3.address));
                });
            });
        });

        describe("#7 callAgreement", () => {
            it("#7.1 only listed agreement allowed", async () => {
                const reason = "HOST_ONLY_LISTED_AGREEMENT";
                // call to an non agreement
                await expect(superfluid.callAgreement(alice, "0x", "0x")).to.be
                    .reverted;
                // call to an unregistered mock agreement
                let mock = await createAgreementMock(
                    web3.utils.sha3("typeA")!,
                    0
                );
                await expectCustomError(
                    superfluid.callAgreement(mock.address, "0x", "0x"),
                    superfluid,
                    reason
                );
                // call to an in personating mock agreement
                mock = await createAgreementMock(
                    await t.contracts.cfa.agreementType(),
                    0
                );
                await expectCustomError(
                    superfluid.callAgreement(mock.address, "0x", "0x"),
                    superfluid,
                    reason
                );
            });

            it("#7.2 callData without correct selector", async () => {
                await expectRevertedWith(
                    superfluid.callAgreement(
                        t.contracts.cfa.address,
                        "0x",
                        "0x"
                    ),
                    "CallUtils: invalid callData"
                );
            });
        });

        describe("#8 callAppAction", () => {
            let agreement: AgreementMock;
            let app: SuperAppMock;

            before(async () => {
                await t.useLastEvmSnapshot();

                agreement = await createAgreementMock(
                    web3.utils.sha3("MockAgreement")!,
                    0
                );
                await governance.registerAgreementClass(
                    superfluid.address,
                    agreement.address
                );
                agreement = await ethers.getContractAt(
                    "AgreementMock",
                    await superfluid.getAgreementClass(
                        web3.utils.sha3("MockAgreement")!
                    )
                );

                const SuperAppMockFactory =
                    await ethers.getContractFactory("SuperAppMock");
                app = await SuperAppMockFactory.deploy(
                    superfluid.address,
                    1,
                    false
                );

                await t.pushEvmSnapshot();
            });

            after(async () => {
                await t.popEvmSnapshot();
            });

            it("#8.1 only super app can be called", async () => {
                const reason = "HOST_NOT_A_SUPER_APP";
                // call to an non agreement
                await expect(superfluid.callAppAction(alice, "0x")).to.be
                    .reverted;
                // call to an unregistered mock agreement
                await expectCustomError(
                    superfluid.callAppAction(governance.address, "0x"),
                    superfluid,
                    reason
                );
            });

            it("#8.2 actionNoop", async () => {
                await expect(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData("actionNoop", [
                            "0x",
                        ])
                    )
                )
                    .to.emit(app, "NoopEvent")
                    .withArgs(
                        0,
                        2 /* CALL_INFO_CALL_TYPE_APP_ACTION */,
                        "0x00000000"
                    );
            });

            it("#8.3 callAppAction assert or revert", async () => {
                await expectRevertedWith(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionAssert",
                            ["0x"]
                        )
                    ),
                    "CallUtils: target panicked: 0x01"
                );
                await expectRevertedWith(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionRevert",
                            ["0x"]
                        )
                    ),
                    "CallUtils: target revert()"
                );
                await expectRevertedWith(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionRevertWithReason",
                            ["error 42", "0x"]
                        )
                    ),
                    "error 42"
                );
            });

            it("#8.4 app action should not callAgreement or callAppAction without ctx", async () => {
                await expectCustomError(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionCallAgreementWithoutCtx",
                            ["0x"]
                        )
                    ),
                    superfluid,
                    "APP_RULE",
                    t.customErrorCode.APP_RULE_CTX_IS_NOT_CLEAN
                );
                await expectCustomError(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionCallAppActionWithoutCtx",
                            ["0x"]
                        )
                    ),
                    superfluid,
                    "APP_RULE",
                    t.customErrorCode.APP_RULE_CTX_IS_NOT_CLEAN
                );
            });

            it("#8.5 app callAgreementWithContext which doPing", async () => {
                await expect(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionPingAgreement",
                            [agreement.address, 42, "0x"]
                        )
                    )
                )
                    .to.emit(agreement, "Pong")
                    .withArgs(42);
            });

            it("#8.6 app callAgreementWithContext which reverts", async () => {
                await expectRevertedWith(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionAgreementRevert",
                            [agreement.address, "error 42", "0x"]
                        )
                    ),
                    "error 42"
                );
            });

            it("#8.7 app callAppActionWithContext which noop", async () => {
                await expect(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionCallActionNoop",
                            ["0x"]
                        )
                    )
                ).to.emit(app, "NoopEvent");
            });

            it("#8.8 app callAppActionWithContext which reverts", async () => {
                await expectRevertedWith(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionCallActionRevert",
                            ["error 42", "0x"]
                        )
                    ),
                    "error 42"
                );
            });

            it("#8.9 app action should not alter ctx", async () => {
                await expectCustomError(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionAlteringCtx",
                            ["0x"]
                        )
                    ),
                    superfluid,
                    "APP_RULE",
                    t.customErrorCode.APP_RULE_CTX_IS_READONLY
                );
            });

            it("#8.10 should not be able call jailed app", async () => {
                await superfluid["jailApp(address)"](app.address);
                await expectCustomError(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionCallActionNoop",
                            ["0x"]
                        )
                    ),
                    superfluid,
                    "HOST_SUPER_APP_IS_JAILED"
                );
            });

            it("#8.11 should give explicit error message when empty ctx returned by the action", async () => {
                await expectCustomError(
                    superfluid.callAppAction(
                        app.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionReturnEmptyCtx",
                            ["0x"]
                        )
                    ),
                    superfluid,
                    "APP_RULE",
                    t.customErrorCode.APP_RULE_CTX_IS_MALFORMATED
                );
            });

            it("#8.12 should not be able to call callbacks", async () => {
                await Promise.all(
                    [
                        "beforeAgreementCreated",
                        "afterAgreementCreated",
                        "beforeAgreementUpdated",
                        "afterAgreementUpdated",
                        "beforeAgreementTerminated",
                        "afterAgreementTerminated",
                    ].map(async (cbname) => {
                        const sel = Object.entries(
                            app.interface.functions
                        ).filter((i) => i[1].name === cbname)[0][0];
                        const signatureHash = app.interface.getSighash(sel);
                        await expectCustomError(
                            superfluid.callAppAction(
                                app.address,
                                signatureHash
                            ),
                            superfluid,
                            "HOST_AGREEMENT_CALLBACK_IS_NOT_ACTION"
                        );
                    })
                );
            });
        });

        describe("#9 Contextual Call Proxies", () => {
            let AgreementMock: AgreementMock;
            let SuperAppMock: SuperAppMock;

            before(async () => {
                await t.useLastEvmSnapshot();

                AgreementMock = await createAgreementMock(
                    web3.utils.sha3("MockAgreement")!,
                    0
                );
                await governance.registerAgreementClass(
                    superfluid.address,
                    AgreementMock.address
                );
                AgreementMock = await ethers.getContractAt(
                    "AgreementMock",
                    await superfluid.getAgreementClass(
                        web3.utils.sha3("MockAgreement")!
                    )
                );

                const SuperAppMockFactory =
                    await ethers.getContractFactory("SuperAppMock");
                SuperAppMock = await SuperAppMockFactory.deploy(
                    superfluid.address,
                    1,
                    false
                );

                await t.pushEvmSnapshot();
            });

            after(async () => {
                await t.popEvmSnapshot();
            });

            it("#9.1 must call with valid ctx", async () => {
                await expectCustomError(
                    superfluid.callAppAction(
                        SuperAppMock.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionCallAgreementWithInvalidCtx",
                            [AgreementMock.address, "0x"]
                        )
                    ),
                    superfluid,
                    "APP_RULE",
                    t.customErrorCode.APP_RULE_CTX_IS_READONLY
                );
                await expectCustomError(
                    superfluid.callAppAction(
                        SuperAppMock.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionCallActionWithInvalidCtx",
                            [AgreementMock.address, "0x"]
                        )
                    ),
                    superfluid,
                    "APP_RULE",
                    t.customErrorCode.APP_RULE_CTX_IS_READONLY
                );
            });

            it("#9.2 app action should not alter ctx", async () => {
                await expectCustomError(
                    superfluid.callAppAction(
                        SuperAppMock.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionCallBadAction",
                            ["0x"]
                        )
                    ),
                    superfluid,
                    "APP_RULE",
                    t.customErrorCode.APP_RULE_CTX_IS_READONLY
                );
            });

            it("#9.3 callAgreementWithContext should from the same app", async () => {
                await expectCustomError(
                    superfluid.callAppAction(
                        SuperAppMock.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionPingAgreementThroughAux",
                            [AgreementMock.address, 42, "0x"]
                        )
                    ),
                    superfluid,
                    "HOST_CALL_AGREEMENT_WITH_CTX_FROM_WRONG_ADDRESS"
                );
            });

            it("#9.4 callAppActionWithContext should from the same app", async () => {
                await expectCustomError(
                    superfluid.callAppAction(
                        SuperAppMock.address,
                        superAppMockInterface.encodeFunctionData(
                            "actionCallActionNoopThroughAux",
                            ["0x"]
                        )
                    ),
                    superfluid,
                    "HOST_CALL_APP_ACTION_WITH_CTX_FROM_WRONG_ADDRESS"
                );
            });
        });

        describe("#10 batchCall", () => {
            it("#10.1 batchCall upgrade/approve/transfer/downgrade in one", async () => {
                const superToken = t.tokens.SuperToken;

                const aliceSigner = await ethers.getSigner(alice);

                console.log("Alice upgrades 10 tokens");
                await superToken.connect(aliceSigner).upgrade(toWad("10"));

                console.log("SuperToken.approve - from alice to admin");
                await superToken
                    .connect(aliceSigner)
                    .approve(admin, toWad("3"));
                assert.equal(
                    (await superToken.allowance(alice, admin)).toString(),
                    toWad("3").toString()
                );

                await superfluid.batchCall([
                    {
                        operationType: 101, // upgrade
                        target: superToken.address,
                        data: web3.eth.abi.encodeParameters(
                            ["uint256"],
                            [toWad("10").toString()]
                        ),
                    },
                    {
                        operationType: 1, // approve
                        target: superToken.address,
                        data: web3.eth.abi.encodeParameters(
                            ["address", "uint256"],
                            [bob, toWad("1").toString()]
                        ),
                    },
                    {
                        operationType: 2, // transferFrom own funds
                        target: superToken.address,
                        data: web3.eth.abi.encodeParameters(
                            ["address", "address", "uint256"],
                            [admin, bob, toWad("2").toString()]
                        ),
                    },
                    {
                        operationType: 2, // transferFrom other's funds
                        target: superToken.address,
                        data: web3.eth.abi.encodeParameters(
                            ["address", "address", "uint256"],
                            [alice, bob, toWad("3").toString()]
                        ),
                    },
                    {
                        operationType: 102, // downgrade
                        target: superToken.address,
                        data: web3.eth.abi.encodeParameters(
                            ["uint256"],
                            [toWad("5").toString()]
                        ),
                    },
                ]);
                assert.equal(
                    (await superToken.balanceOf(admin)).toString(),
                    toWad("3").toString()
                );
                assert.equal(
                    (await superToken.allowance(alice, admin)).toString(),
                    toWad("0").toString()
                );
                assert.equal(
                    (await superToken.balanceOf(alice)).toString(),
                    toWad("7").toString()
                );
                assert.equal(
                    (await superToken.allowance(admin, bob)).toString(),
                    toWad("1").toString()
                );
                assert.equal(
                    (await superToken.balanceOf(bob)).toString(),
                    toWad("5").toString()
                );

                await t.validateSystemInvariance();
            });

            context("#10.2 batchCall send", () => {
                let superToken: SuperTokenMock;
                let mock: ERC777SenderRecipientMock;
                let aliceSigner: SignerWithAddress;

                before(async () => {
                    superToken = t.tokens.SuperToken;
                    aliceSigner = await ethers.getSigner(alice);
                });

                beforeEach(async () => {
                    const mockFactory = await ethers.getContractFactory(
                        "ERC777SenderRecipientMock"
                    );
                    mock = await mockFactory.deploy();

                    // @note we must add alias otherwise validateSystemInvariance will fail
                    t.addAlias("ERC777SenderRecipientMock", mock.address);

                    console.log("Alice upgrades 10 tokens");
                    await superToken.connect(aliceSigner).upgrade(toWad("10"));
                });

                afterEach(async () => {
                    await t.validateSystemInvariance();
                });

                it("#10.2.0 batchCall send with empty userData to EOA allowed", async () => {
                    await superfluid.connect(aliceSigner).batchCall([
                        {
                            operationType: 3, // send
                            target: superToken.address,
                            data: web3.eth.abi.encodeParameters(
                                ["address", "uint256", "bytes"],
                                [bob, toWad("3").toString(), "0x"]
                            ),
                        },
                    ]);
                });

                it("#10.2.1 batchCall send with non-empty userData to unregistered contract reverts", async () => {
                    await expectCustomError(
                        superfluid.connect(aliceSigner).batchCall([
                            {
                                operationType: 3, // send
                                target: superToken.address,
                                data: web3.eth.abi.encodeParameters(
                                    ["address", "uint256", "bytes"],
                                    [
                                        mock.address,
                                        toWad("3").toString(),
                                        "0x4206",
                                    ]
                                ),
                            },
                        ]),
                        superToken,
                        "SUPER_TOKEN_NOT_ERC777_TOKENS_RECIPIENT"
                    );
                });

                it("#10.2.2 batchCall send with non-empty userData to registered contract allowed", async () => {
                    console.log("registerRecipient");
                    await mock.registerRecipient(mock.address);

                    await superfluid.connect(aliceSigner).batchCall([
                        {
                            operationType: 3, // send
                            target: superToken.address,
                            data: web3.eth.abi.encodeParameters(
                                ["address", "uint256", "bytes"],
                                [mock.address, toWad("3").toString(), "0x4206"]
                            ),
                        },
                    ]);
                });

                it("#10.2.3 batchCall send with non-empty userData to EOA allowed", async () => {
                    await superfluid.connect(aliceSigner).batchCall([
                        {
                            operationType: 3, // send
                            target: superToken.address,
                            data: web3.eth.abi.encodeParameters(
                                ["address", "uint256", "bytes"],
                                [bob, toWad("3").toString(), "0x4206"]
                            ),
                        },
                    ]);
                });
            });

            it("#10.3 batchCall call agreement", async () => {
                let agreement = await createAgreementMock(
                    web3.utils.sha3("MockAgreement")!,
                    0
                );
                console.log("Registering mock agreement");
                await governance.registerAgreementClass(
                    superfluid.address,
                    agreement.address
                );
                agreement = await ethers.getContractAt(
                    "AgreementMock",
                    await superfluid.getAgreementClass(
                        web3.utils.sha3("MockAgreement")!
                    )
                );

                await expect(
                    superfluid.batchCall([
                        {
                            operationType: 201, // call agreement
                            target: agreement.address,
                            data: web3.eth.abi.encodeParameters(
                                ["bytes", "bytes"],
                                [
                                    agreementMockInterface.encodeFunctionData(
                                        "pingMe",
                                        [admin, 42, "0x"]
                                    ),
                                    "0x", // user data
                                ]
                            ),
                        },
                        {
                            operationType: 201, // call agreement
                            target: agreement.address,
                            data: web3.eth.abi.encodeParameters(
                                ["bytes", "bytes"],
                                [
                                    agreementMockInterface.encodeFunctionData(
                                        "pingMe",
                                        [admin, 43, "0x"]
                                    ),
                                    "0x", // user data
                                ]
                            ),
                        },
                    ])
                )
                    .to.emit(agreement, "Pong")
                    .withArgs(42)
                    .and.to.emit(agreement, "Pong")
                    .withArgs(43);
            });

            it("#10.4 batchCall call app action", async () => {
                let agreement = await createAgreementMock(
                    web3.utils.sha3("MockAgreement")!,
                    0
                );
                console.log("Registering mock agreement");
                await governance.registerAgreementClass(
                    superfluid.address,
                    agreement.address
                );
                agreement = await ethers.getContractAt(
                    "AgreementMock",
                    await superfluid.getAgreementClass(
                        web3.utils.sha3("MockAgreement")!
                    )
                );
                const SuperAppMockFactory =
                    await ethers.getContractFactory("SuperAppMock");
                const app = await SuperAppMockFactory.deploy(
                    superfluid.address,
                    1,
                    false
                );

                await expect(
                    superfluid.batchCall([
                        {
                            operationType: 201, // call agreement
                            target: agreement.address,
                            data: web3.eth.abi.encodeParameters(
                                ["bytes", "bytes"],
                                [
                                    agreementMockInterface.encodeFunctionData(
                                        "pingMe",
                                        [admin, 42, "0x"]
                                    ),
                                    "0x", // user data
                                ]
                            ),
                        },
                        {
                            operationType: 202, // call app action
                            target: app.address,
                            data: superAppMockInterface.encodeFunctionData(
                                "actionNoop",
                                ["0x"]
                            ),
                        },
                    ])
                )
                    .to.emit(agreement, "Pong")
                    .withArgs(42)
                    .and.to.emit(app, "NoopEvent");
            });

            it("#10.5 batchCall one fail revert all", async () => {
                const SuperAppMockFactory =
                    await ethers.getContractFactory("SuperAppMock");
                const app = await SuperAppMockFactory.deploy(
                    superfluid.address,
                    1,
                    false
                );

                await expectRevertedWith(
                    superfluid
                        .connect(await ethers.getSigner(admin))
                        .batchCall([
                            {
                                operationType: 202, // call app action
                                target: app.address,
                                data: superAppMockInterface.encodeFunctionData(
                                    "actionCallActionNoop",
                                    ["0x"]
                                ),
                            },
                            {
                                operationType: 202, // call app action
                                target: app.address,
                                data: superAppMockInterface.encodeFunctionData(
                                    "actionCallActionRevert",
                                    ["error 42", "0x"]
                                ),
                            },
                        ]),
                    "error 42"
                );
            });

            it("#10.6 batchCall invalid operation type", async () => {
                await expectCustomError(
                    superfluid.batchCall([
                        {operationType: 8888, target: ZERO_ADDRESS, data: "0x"},
                    ]),
                    superfluid,
                    "HOST_UNKNOWN_BATCH_CALL_OPERATION_TYPE"
                );
            });
        });

        describe("#11 forwardBatchCall", () => {
            let forwarder: ForwarderMock;

            beforeEach(async () => {
                const ForwarderMockFactory =
                    await ethers.getContractFactory("ForwarderMock");
                forwarder = await ForwarderMockFactory.deploy();
            });

            it("#11.1 forwardBatchCall with mocked transaction signer", async () => {
                await governance.enableTrustedForwarder(
                    superfluid.address,
                    ZERO_ADDRESS,
                    forwarder.address,
                    {
                        from: admin,
                    }
                );
                const superToken = t.tokens.SuperToken;
                await t.upgradeBalance("alice", toWad(1));
                await forwarder.execute({
                    from: alice, // mocked transaction signer
                    to: superfluid.address,
                    value: "0",
                    gas: "5000000",
                    data: t.agreementHelper.hostInterface.encodeFunctionData(
                        "forwardBatchCall",
                        [
                            [
                                {
                                    operationType: 2,
                                    target: superToken.address,
                                    data: web3.eth.abi.encodeParameters(
                                        ["address", "address", "uint256"],
                                        [alice, bob, toWad(1).toString()]
                                    ),
                                },
                            ],
                        ]
                    ),
                });
                assert.equal(
                    (await superToken.balanceOf(bob)).toString(),
                    toWad(1).toString()
                );
            });

            it("#11.2 untrusted forwarder", async () => {
                await governance.disableTrustedForwarder(
                    superfluid.address,
                    ZERO_ADDRESS,
                    forwarder.address,
                    {
                        from: admin,
                    }
                );
                await expectRevertedWith(
                    forwarder.execute({
                        from: alice,
                        to: superfluid.address,
                        value: "0",
                        gas: "5000000",
                        data: t.agreementHelper.hostInterface.encodeFunctionData(
                            "forwardBatchCall",
                            [[]]
                        ),
                    }),
                    "Not trusted forwarder"
                );
            });

            it("#11.3 forwarder with malformatted message", async () => {
                await expectRevertedWith(
                    superfluid
                        .connect(await ethers.getSigner(admin))
                        .forwardBatchCall([]),
                    "Not trusted forwarder"
                );
            });
        });

        describe("#20 Governance", () => {
            it("#20.1 getGovernance", async () => {
                assert.equal(
                    await superfluid.getGovernance(),
                    t.contracts.governance.address
                );
            });

            it("#20.2 only governance can replace itself", async () => {
                await expectCustomError(
                    superfluid.updateCode(ZERO_ADDRESS),
                    superfluid,
                    "HOST_ONLY_GOVERNANCE"
                );
                await expectCustomError(
                    superfluid.replaceGovernance(ZERO_ADDRESS),
                    superfluid,
                    "HOST_ONLY_GOVERNANCE"
                );
            });

            it("#20.3 replace with new governance", async () => {
                const TestGovernanceFactory =
                    await ethers.getContractFactory("TestGovernance");
                const newGov = await TestGovernanceFactory.deploy();
                await governance.replaceGovernance(
                    superfluid.address,
                    newGov.address
                );
                assert.equal(await superfluid.getGovernance(), newGov.address);
            });
        });
    });

    context("Non-upgradable deployment", () => {
        let governance: TestGovernance;
        let superfluid: SuperfluidMock;

        before(async () => {
            await t.beforeTestSuite({
                isTruffle: true,
                nAccounts: 0,
                tokens: [],
            });

            await t.deployFramework({
                isTruffle: true,
                useMocks: true,
                nonUpgradable: true,
            });
            await t.pushEvmSnapshot();

            // load test suite again after new evm snapshot is created
            await t.beforeTestSuite({
                isTruffle: true,
                nAccounts: 3,
                tokens: [],
            });

            ({admin, alice, bob} = t.aliases);
            ({superfluid, governance} = t.contracts);
        });

        after(async function () {
            await t.popEvmSnapshot();
        });

        describe("#30 non-upgradability", () => {
            it("#30.1 agreement is not upgradable", async () => {
                await expectCustomError(
                    governance.updateContracts(
                        superfluid.address,
                        ZERO_ADDRESS,
                        [t.contracts.ida.address],
                        ZERO_ADDRESS,
                        ZERO_ADDRESS
                    ),
                    superfluid,
                    "HOST_NON_UPGRADEABLE"
                );
            });

            it("#30.2 supertoken factory logic contract identical and not upgradable", async () => {
                assert.equal(
                    await superfluid.getSuperTokenFactory(),
                    await superfluid.getSuperTokenFactoryLogic()
                );
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
                const factory2Logic = await t.deployContract<SuperTokenFactory>(
                    "SuperTokenFactory",
                    superfluid.address,
                    superTokenLogic.address,
                    t.constants.ZERO_ADDRESS,
                    t.constants.ZERO_ADDRESS,
                    paNFTLogicAddress,
                    pmNFTLogicAddress
                );
                await expectCustomError(
                    governance.updateContracts(
                        superfluid.address,
                        ZERO_ADDRESS,
                        [],
                        factory2Logic.address,
                        ZERO_ADDRESS
                    ),
                    superfluid,
                    "HOST_NON_UPGRADEABLE"
                );
            });

            it("#30.3 host is not upgradable", async () => {
                const mock1Factory =
                    await ethers.getContractFactory("SuperfluidMock");
                const mock1 = await mock1Factory.deploy(
                    false /* nonUpgradable */,
                    false /* appWhiteListingEnabled */,
                    3000000 /* callbackGasLimit */,
                    ZERO_ADDRESS /* simpleForwarder */,
                    ZERO_ADDRESS /* erc2771Forwarder */
                );
                await expectCustomError(
                    governance.updateContracts(
                        superfluid.address,
                        mock1.address,
                        [],
                        ZERO_ADDRESS,
                        ZERO_ADDRESS
                    ),
                    superfluid,
                    "HOST_NON_UPGRADEABLE"
                );
            });
        });
    });

    context("App whitelisting deployment", () => {
        let superAppMockWithRegistrationKeyFactory: SuperAppMockWithRegistrationKey__factory;
        let superfluid: SuperfluidMock;
        let governance: TestGovernance;

        before(async () => {
            await t.beforeTestSuite({
                isTruffle: true,
                nAccounts: 0,
                tokens: [],
            });

            await t.deployFramework({
                isTruffle: true,
                useMocks: true,
                appWhiteListing: true,
            });
            await t.pushEvmSnapshot();

            // load test suite again after new evm snapshot is created
            await t.beforeTestSuite({
                isTruffle: true,
                nAccounts: 3,
                tokens: [],
            });

            superAppMockWithRegistrationKeyFactory =
                await ethers.getContractFactory(
                    "SuperAppMockWithRegistrationKey"
                );

            ({admin, alice, bob} = t.aliases);
            ({superfluid, governance} = t.contracts);
        });

        after(async function () {
            await t.popEvmSnapshot();
        });

        context("#40.x register app with key", () => {
            it("#40.1 app registration without key should succeed", async () => {
                await expectCustomError(
                    superAppMockFactory.deploy(
                        superfluid.address,
                        1 /* APP_TYPE_FINAL_LEVEL */,
                        false
                    ),
                    superfluid,
                    "HOST_NO_APP_REGISTRATION_PERMISSION"
                );
            });

            it("#40.2 app registration with invalid key should fail", async () => {
                await expectCustomError(
                    superAppMockWithRegistrationKeyFactory.deploy(
                        superfluid.address,
                        1 /* APP_TYPE_FINAL_LEVEL */,
                        "bad microsoft registration key"
                    ),
                    superfluid,
                    "HOST_NO_APP_REGISTRATION_PERMISSION"
                );
            });

            it("#40.3 app can register with a correct key", async () => {
                const regKey = "hello world";
                const expirationTs =
                    Math.floor(Date.now() / 1000) + 3600 * 24 * 90; // 90 days from now
                await governance.setAppRegistrationKey(
                    superfluid.address,
                    bob,
                    regKey,
                    expirationTs
                );
                const bobSigner = await ethers.getSigner(bob);
                const app = await superAppMockWithRegistrationKeyFactory
                    .connect(bobSigner)
                    .deploy(
                        superfluid.address,
                        1 /* APP_TYPE_FINAL_LEVEL */,
                        "hello world"
                    );
                assert.isTrue(await superfluid.isApp(app.address));
            });

            it("#40.4 app registration with key for different deployer should fail", async () => {
                const regKey = "hello world";
                const expirationTs =
                    Math.floor(Date.now() / 1000) + 3600 * 24 * 90; // 90 days from now
                await governance.setAppRegistrationKey(
                    superfluid.address,
                    bob,
                    regKey,
                    expirationTs
                );
                await expectCustomError(
                    superAppMockWithRegistrationKeyFactory.deploy(
                        superfluid.address,
                        1 /* APP_TYPE_FINAL_LEVEL */,
                        "hello world"
                    ),
                    superfluid,
                    "HOST_NO_APP_REGISTRATION_PERMISSION"
                );
            });

            it("#40.5 app can register with an expired key should fail", async () => {
                const regKey = "hello world again";
                const expirationTs = Math.floor(Date.now() / 1000) - 3600 * 24; // expired yesterday
                await governance.setAppRegistrationKey(
                    superfluid.address,
                    bob,
                    regKey,
                    expirationTs
                );
                await expectCustomError(
                    superAppMockWithRegistrationKeyFactory.deploy(
                        superfluid.address,
                        1 /* APP_TYPE_FINAL_LEVEL */,
                        "hello world again"
                    ),
                    superfluid,
                    "HOST_NO_APP_REGISTRATION_PERMISSION"
                );
            });
        });

        context("#41.x register app by factory", () => {
            it("#41.1 app registration by unauthorized factory should fail", async () => {
                const superAppFactoryMockFactory =
                    await ethers.getContractFactory("SuperAppFactoryMock");
                const appFactory = await superAppFactoryMockFactory.deploy();
                // governance.authorizeAppFactory NOT done
                const SuperAppMockNotSelfRegisteringFactory =
                    await ethers.getContractFactory(
                        "SuperAppMockNotSelfRegistering"
                    );
                const app =
                    await SuperAppMockNotSelfRegisteringFactory.deploy();
                await expectCustomError(
                    appFactory.registerAppWithHost(
                        superfluid.address,
                        app.address,
                        1 /* APP_TYPE_FINAL_LEVEL */
                    ),
                    superfluid,
                    "HOST_NO_APP_REGISTRATION_PERMISSION"
                );
            });

            it("#41.2 app registration by authorized factory", async () => {
                const superAppFactoryMockFactory =
                    await ethers.getContractFactory("SuperAppFactoryMock");
                const appFactory = await superAppFactoryMockFactory.deploy();
                await governance.authorizeAppFactory(
                    superfluid.address,
                    appFactory.address
                );
                const app = await superAppFactoryMockFactory.deploy();
                assert.isFalse(await superfluid.isApp(app.address));
                await appFactory.registerAppWithHost(
                    superfluid.address,
                    app.address,
                    1 /* APP_TYPE_FINAL_LEVEL */
                );
                assert.isTrue(await superfluid.isApp(app.address));

                // works for more than once app...
                const app2 = await superAppFactoryMockFactory.deploy();
                assert.isFalse(await superfluid.isApp(app2.address));
                await appFactory.registerAppWithHost(
                    superfluid.address,
                    app2.address,
                    1 /* APP_TYPE_FINAL_LEVEL */
                );
                assert.isTrue(await superfluid.isApp(app2.address));

                // withdrawal of authorization disallows further apps to be registered ...
                await governance.unauthorizeAppFactory(
                    superfluid.address,
                    appFactory.address
                );

                const app3 = await superAppFactoryMockFactory.deploy();
                assert.isFalse(await superfluid.isApp(app3.address));
                await expectCustomError(
                    appFactory.registerAppWithHost(
                        superfluid.address,
                        app3.address,
                        1 /* APP_TYPE_FINAL_LEVEL */
                    ),
                    superfluid,
                    "HOST_NO_APP_REGISTRATION_PERMISSION"
                );
            });
        });
    });
});
