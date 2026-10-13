import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {expect} from "chai";
import {assert} from "chai";
import {ethers} from "hardhat";

import {
    ConstantFlowAgreementV1,
    StreamRedirector__factory,
    SuperfluidMock,
    SuperTokenMock,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectCustomError} from "../../utils/expectRevert";
import {toBN} from "../utils/helpers";

import {VerifyOptions} from "./Agreement.types";
import AgreementHelper, {
    FLOW_TYPE_CREATE,
    FLOW_TYPE_DELETE,
    FLOW_TYPE_UPDATE,
} from "./AgreementHelper";
import {
    expectDepositAndOwedDeposit,
    expectFlow,
    expectNetFlow,
    getDeposit,
    shouldUpdateFlowOperatorPermissionsAndValidateEvent,
} from "./ConstantFlowAgreementV1.behavior";
import CFADataModel from "./ConstantFlowAgreementV1.data";

describe("CFAv1 | Callback Tests", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();
    let agreementHelper: AgreementHelper;
    const {LIQUIDATION_PERIOD, FLOW_RATE1} = t.configs;

    let alice: string, bob: string;
    let superfluid: SuperfluidMock;
    let cfa: ConstantFlowAgreementV1;
    let superToken: SuperTokenMock;

    before(async () => {
        await t.beforeTestSuite({
            nAccounts: 5,
        });
        ({alice, bob} = t.aliases);

        ({superfluid, cfa} = t.contracts);
        superToken = t.tokens.SuperToken;
        agreementHelper = t.agreementHelper;
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(async () => {
        t.afterEachTestCaseBenchmark();
    });

    async function timeTravelOnceAndValidateSystemInvariance(
        opts?: VerifyOptions
    ) {
        await t.timeTravelOnce(opts?.time);
        await t.validateSystemInvariance(opts);
    }

    it("#1.1 ExclusiveInflowTestApp", async () => {
        const ExclusiveInflowTestAppFactory = await ethers.getContractFactory(
            "ExclusiveInflowTestApp"
        );
        const app = await ExclusiveInflowTestAppFactory.deploy(
            cfa.address,
            superfluid.address
        );
        t.addAlias("app", app.address);

        await t.upgradeBalance("alice", t.configs.INIT_BALANCE);
        await t.upgradeBalance("bob", t.configs.INIT_BALANCE);

        console.log("alice -> app");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_CREATE,
            superToken: superToken.address,
            sender: alice,
            receiver: app.address,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "alice",
            value: toBN(0).sub(FLOW_RATE1).toString(),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "bob",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "app",
            value: FLOW_RATE1.toString(),
        });
        await timeTravelOnceAndValidateSystemInvariance();

        console.log("bob -> app");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_CREATE,
            superToken: superToken.address,
            sender: bob,
            receiver: app.address,
            flowRate: FLOW_RATE1.mul(2),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "alice",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "bob",
            value: toBN(0).sub(FLOW_RATE1.mul(2)).toString(),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "app",
            value: FLOW_RATE1.mul(2).toString(),
        });
        await timeTravelOnceAndValidateSystemInvariance();

        console.log("bob -> app");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_DELETE,
            superToken: superToken.address,
            sender: bob,
            receiver: app.address,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "alice",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "bob",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "app",
            value: "0",
        });
        await timeTravelOnceAndValidateSystemInvariance();
    });

    it("#1.2 NonClosableOutflowTestApp", async () => {
        const NonClosableOutflowTestAppFactory =
            await ethers.getContractFactory("NonClosableOutflowTestApp");
        const app = await NonClosableOutflowTestAppFactory.deploy(
            cfa.address,
            superfluid.address
        );
        t.addAlias("app", app.address);

        await t.upgradeBalance("alice", t.configs.INIT_BALANCE);
        await t.transferBalance("alice", "app", t.configs.INIT_BALANCE);

        await app.setupOutflow(
            superToken.address,
            alice,
            FLOW_RATE1.toString()
        );
        expect(
            (await cfa.getFlow(superToken.address, app.address, alice)).flowRate
        ).to.equal(FLOW_RATE1.toString());
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "alice",
            value: FLOW_RATE1.toString(),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "app",
            value: toBN(0).sub(FLOW_RATE1).toString(),
        });
        await timeTravelOnceAndValidateSystemInvariance();

        console.log("app -> alice by alice");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_DELETE,
            superToken: superToken.address,
            sender: app.address,
            receiver: alice,
            signer: await ethers.getSigner(alice),
        });
        expect(
            (await cfa.getFlow(superToken.address, app.address, alice)).flowRate
        ).to.equal(FLOW_RATE1.toString());
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "alice",
            value: FLOW_RATE1.toString(),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "app",
            value: toBN(0).sub(FLOW_RATE1).toString(),
        });
        await timeTravelOnceAndValidateSystemInvariance();
    });

    it("#1.3 SelfDeletingFlowTestApp", async () => {
        const SelfDeletingFlowTestAppFactory = await ethers.getContractFactory(
            "SelfDeletingFlowTestApp"
        );
        const app = await SelfDeletingFlowTestAppFactory.deploy(
            cfa.address,
            superfluid.address
        );
        t.addAlias("app", app.address);

        await t.upgradeBalance("alice", t.configs.INIT_BALANCE);

        console.log("alice -> app");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_CREATE,
            superToken: superToken.address,
            sender: alice,
            receiver: app.address,
            flowRate: FLOW_RATE1,
        });
        expect(
            (await cfa.getFlow(superToken.address, alice, app.address)).flowRate
        ).to.equal("0");
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "alice",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "app",
            value: "0",
        });
        await timeTravelOnceAndValidateSystemInvariance();
    });

    it("#1.4 ClosingOnUpdateFlowTestApp", async () => {
        const ClosingOnUpdateFlowTestAppFactory =
            await ethers.getContractFactory("ClosingOnUpdateFlowTestApp");
        const app = await ClosingOnUpdateFlowTestAppFactory.deploy(
            cfa.address,
            superfluid.address
        );
        t.addAlias("app", app.address);

        await t.upgradeBalance("alice", t.configs.INIT_BALANCE);

        console.log("alice -> app");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_CREATE,
            superToken: superToken.address,
            sender: alice,
            receiver: app.address,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "alice",
            value: toBN(0).sub(FLOW_RATE1).toString(),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "bob",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "app",
            value: FLOW_RATE1.toString(),
        });
        await timeTravelOnceAndValidateSystemInvariance();

        console.log("alice -> app");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_UPDATE,
            superToken: superToken.address,
            sender: alice,
            receiver: app.address,
            flowRate: FLOW_RATE1.mul(2),
        });
        expect(
            (await cfa.getFlow(superToken.address, alice, app.address)).flowRate
        ).to.equal("0");
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "alice",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "app",
            value: "0",
        });
        await timeTravelOnceAndValidateSystemInvariance();
    });

    it("#1.5 FlowExchangeTestApp", async () => {
        await t.upgradeBalance("alice", t.configs.INIT_BALANCE);

        const {superToken: superToken2} = await t.deployNewToken("TEST2", {
            doUpgrade: true,
        });
        const FlowExchangeTestAppFactory = await ethers.getContractFactory(
            "FlowExchangeTestApp"
        );
        const app = await FlowExchangeTestAppFactory.deploy(
            cfa.address,
            superfluid.address,
            superToken2.address
        );
        t.addAlias("app", app.address);

        console.log("alice -> app");
        await expectCustomError(
            agreementHelper.modifyFlow({
                type: FLOW_TYPE_CREATE,
                superToken: superToken.address,
                sender: alice,
                receiver: app.address,
                flowRate: FLOW_RATE1,
            }),
            cfa,
            "CFA_INSUFFICIENT_BALANCE"
        );

        // fund the app with
        await superToken2
            .connect(await ethers.getSigner(alice))
            .transfer(app.address, t.configs.INIT_BALANCE);

        console.log("alice -> app");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_CREATE,
            superToken: superToken.address,
            sender: alice,
            receiver: app.address,
            flowRate: FLOW_RATE1,
        });
        let flow1, flow2;
        flow1 = await cfa.getFlow(superToken.address, alice, app.address);
        flow2 = await cfa.getFlow(superToken2.address, app.address, alice);
        const cfaDataModel = new CFADataModel(t, superToken);
        const deposit = cfaDataModel.getDeposit(FLOW_RATE1, LIQUIDATION_PERIOD);
        console.log(
            "Flow: alice -> app (token1)",
            flow1.flowRate.toString(),
            flow1.deposit.toString(),
            flow1.owedDeposit.toString()
        );
        assert.equal(flow1.flowRate.toString(), FLOW_RATE1.toString());
        assert.equal(flow1.deposit.toString(), deposit.toString());
        assert.equal(flow1.owedDeposit.toString(), "0");
        console.log(
            "Flow: app -> alice (token2)",
            flow2.flowRate.toString(),
            flow2.deposit.toString(),
            flow2.owedDeposit.toString()
        );
        assert.equal(flow2.flowRate.toString(), FLOW_RATE1.toString());
        assert.equal(flow2.deposit.toString(), deposit.toString());
        assert.equal(flow2.owedDeposit.toString(), "0");
        console.log(
            "App balances",
            (await superToken.balanceOf(app.address)).toString(),
            (await superToken2.balanceOf(app.address)).toString()
        );

        await timeTravelOnceAndValidateSystemInvariance();

        console.log("alice -> app");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_DELETE,
            superToken: superToken.address,
            sender: alice,
            receiver: app.address,
        });
        flow1 = await cfa.getFlow(superToken.address, alice, app.address);
        flow2 = await cfa.getFlow(superToken2.address, app.address, alice);
        console.log(
            "Flow: alice -> app (token1)",
            flow1.flowRate.toString(),
            flow1.deposit.toString(),
            flow1.owedDeposit.toString()
        );
        assert.equal(flow1.flowRate.toString(), "0");
        assert.equal(flow1.deposit.toString(), "0");
        assert.equal(flow1.owedDeposit.toString(), "0");
        console.log(
            "Flow: app -> alice (token2)",
            flow2.flowRate.toString(),
            flow2.deposit.toString(),
            flow2.owedDeposit.toString()
        );
        assert.equal(flow2.flowRate.toString(), FLOW_RATE1.toString());
        assert.equal(flow2.deposit.toString(), deposit.toString());
        assert.equal(flow2.owedDeposit.toString(), "0");
        console.log(
            "App balances",
            (await superToken.balanceOf(app.address)).toString(),
            (await superToken2.balanceOf(app.address)).toString()
        );
        assert.equal(
            toBN((await superToken2.balanceOf(app.address)).toString())
                .add(toBN((await superToken2.balanceOf(alice)).toString()))
                .add(toBN(deposit))
                .toString(),
            t.configs.INIT_BALANCE.toString()
        );

        await timeTravelOnceAndValidateSystemInvariance();
        assert.isFalse(await t.contracts.superfluid.isAppJailed(app.address));
    });

    describe("#1.6 Access Control List Callback", () => {
        const ALLOW_CREATE = 1 << 0;
        let streamRedirectorFactory: StreamRedirector__factory;
        let signer: SignerWithAddress;

        before(async () => {
            streamRedirectorFactory =
                await ethers.getContractFactory("StreamRedirector");
        });

        beforeEach(async () => {
            await t.upgradeBalance("admin", t.configs.INIT_BALANCE);
            await t.upgradeBalance("alice", t.configs.INIT_BALANCE);
            await t.upgradeBalance("bob", t.configs.INIT_BALANCE);
            await t.upgradeBalance("dan", t.configs.INIT_BALANCE);
            signer = await ethers.getSigner(alice);
        });
        it("#1.6.1 SuperApp with ACL permissions should be able to stream to itself", async () => {
            const app = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                bob, // Stream back to Bob in the callback
                t.constants.APP_LEVEL_FINAL
            );

            const aclBaseData = {
                testenv: t,
                superToken: superToken.address,
                sender: alice,
                ctx: "0x",
                flowOperator: app.address,
                from: alice,
            };

            t.addAlias("redirector", app.address);

            // Grant ACL permissions
            await shouldUpdateFlowOperatorPermissionsAndValidateEvent({
                ...aclBaseData,
                permissions: ALLOW_CREATE.toString(),
                flowRateAllowance: FLOW_RATE1,
                signer,
            });

            // Start stream to self (app) from Alice
            await app.startStreamToSelf(alice, FLOW_RATE1);

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0).sub(FLOW_RATE1),
            });

            await expectNetFlow({
                testenv: t,
                superToken,
                account: "redirector",
                value: toBN(0),
            });

            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: FLOW_RATE1,
            });

            // Validate flow data (deposit and owed deposit especially)
            const baseDeposit = getDeposit({
                testenv: t,
                flowRate: FLOW_RATE1,
            });
            const appCreditAdditionalDeposit = baseDeposit.mul(toBN(2));
            await expectFlow({
                testenv: t,
                superToken,
                sender: "alice",
                receiver: "redirector",
                flowRate: FLOW_RATE1,
                deposit: appCreditAdditionalDeposit,
                owedDeposit: baseDeposit,
            });
            await expectDepositAndOwedDeposit({
                testenv: t,
                superToken,
                account: "alice",
                deposit: baseDeposit.mul(toBN(2)),
                owedDeposit: toBN(0),
            });
            await expectDepositAndOwedDeposit({
                testenv: t,
                superToken,
                account: "redirector",
                deposit: baseDeposit,
                owedDeposit: baseDeposit,
            });

            await expectFlow({
                testenv: t,
                superToken,
                sender: "redirector",
                receiver: "bob",
                flowRate: FLOW_RATE1,
                deposit: baseDeposit,
                owedDeposit: toBN(0),
            });
            await expectDepositAndOwedDeposit({
                testenv: t,
                superToken,
                account: "bob",
                deposit: toBN(0),
                owedDeposit: toBN(0),
            });

            // State: Alice -> Redirector -> Bob
            await agreementHelper.modifyFlow({
                type: FLOW_TYPE_DELETE,
                superToken: superToken.address,
                sender: alice,
                receiver: app.address,
            });

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0),
            });

            await expectNetFlow({
                testenv: t,
                superToken,
                account: "redirector",
                value: toBN(0),
            });

            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: toBN(0),
            });

            await expectFlow({
                testenv: t,
                superToken,
                sender: "alice",
                receiver: "redirector",
                flowRate: toBN(0),
                deposit: toBN(0),
                owedDeposit: toBN(0),
            });

            // State: No flows
        });

        it("#1.6.2 SuperApp with permissions should be able to stream to itself (blue elephant)", async () => {
            const app = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                alice, // Note that in this case, we stream back to Alice in the callback
                t.constants.APP_LEVEL_FINAL
            );

            const aclBaseData = {
                testenv: t,
                superToken: superToken.address,
                sender: alice,
                ctx: "0x",
                flowOperator: app.address,
                from: alice,
            };

            t.addAlias("redirector", app.address);

            // Grant ACL permissions
            await shouldUpdateFlowOperatorPermissionsAndValidateEvent({
                ...aclBaseData,
                permissions: ALLOW_CREATE.toString(),
                flowRateAllowance: FLOW_RATE1,
                signer,
            });

            // Start stream to self (app) from Alice
            await app.startStreamToSelf(alice, FLOW_RATE1);

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0),
            });

            await expectNetFlow({
                testenv: t,
                superToken,
                account: "redirector",
                value: toBN(0),
            });

            // Validate flow data (deposit and owed deposit especially)
            const baseDeposit = getDeposit({
                testenv: t,
                flowRate: FLOW_RATE1,
            });
            const appCreditAdditionalDeposit = baseDeposit.mul(toBN(2));
            await expectFlow({
                testenv: t,
                superToken,
                sender: "alice",
                receiver: "redirector",
                flowRate: FLOW_RATE1,
                deposit: appCreditAdditionalDeposit,
                owedDeposit: baseDeposit,
            });
            await expectDepositAndOwedDeposit({
                testenv: t,
                superToken,
                account: "alice",
                deposit: baseDeposit.mul(toBN(2)),
                owedDeposit: toBN(0),
            });
            await expectDepositAndOwedDeposit({
                testenv: t,
                superToken,
                account: "redirector",
                deposit: baseDeposit,
                owedDeposit: baseDeposit,
            });

            await expectFlow({
                testenv: t,
                superToken,
                sender: "redirector",
                receiver: "alice",
                flowRate: FLOW_RATE1,
                deposit: baseDeposit,
                owedDeposit: toBN(0),
            });

            // State: Alice -> Redirector -> Alice

            await agreementHelper.modifyFlow({
                type: FLOW_TYPE_DELETE,
                superToken: superToken.address,
                sender: alice,
                receiver: app.address,
            });

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0),
            });

            await expectNetFlow({
                testenv: t,
                superToken,
                account: "redirector",
                value: toBN(0),
            });

            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: toBN(0),
            });

            await expectFlow({
                testenv: t,
                superToken,
                sender: "alice",
                receiver: "redirector",
                flowRate: toBN(0),
                deposit: toBN(0),
                owedDeposit: toBN(0),
            });
            // State: No flows
        });

        it("#1.6.3 SuperApp to SuperApp is not allowed (non-ACL)", async () => {
            const redirectorA = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                alice,
                t.constants.APP_LEVEL_FINAL
            );
            const redirectorB = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                redirectorA.address,
                t.constants.APP_LEVEL_SECOND
            );

            t.addAlias("redirectorA", redirectorA.address);
            t.addAlias("redirectorB", redirectorB.address);

            // Attempting to do SuperApp callback to SuperApp should fail
            // Alice -> redirectorB cb-> redirectorA cb-> Alice is not allowed
            await expectCustomError(
                agreementHelper.modifyFlow({
                    type: FLOW_TYPE_CREATE,
                    superToken: superToken.address,
                    sender: t.getAddress("alice"),
                    receiver: t.getAddress("redirectorB"),
                    flowRate: FLOW_RATE1,
                }),
                superfluid,
                "APP_RULE",
                t.customErrorCode.APP_RULE_COMPOSITE_APP_IS_NOT_WHITELISTED
            );

            // Should still fail after allow composite app due to max app level rule
            await redirectorB.allowCompositeApp(redirectorA.address);
            await expectCustomError(
                agreementHelper.modifyFlow({
                    type: FLOW_TYPE_CREATE,
                    superToken: superToken.address,
                    sender: t.getAddress("alice"),
                    receiver: t.getAddress("redirectorB"),
                    flowRate: FLOW_RATE1,
                }),
                superfluid,
                "APP_RULE",
                t.customErrorCode.APP_RULE_MAX_APP_LEVEL_REACHED
            );
        });

        it("#1.6.4 SuperApp to SuperApp is not allowed (ACL)", async () => {
            const redirectorA = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                alice,
                t.constants.APP_LEVEL_FINAL
            );
            const redirectorB = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                redirectorA.address,
                t.constants.APP_LEVEL_SECOND
            );

            const aclBaseData = {
                testenv: t,
                superToken: superToken.address,
                sender: alice,
                ctx: "0x",
                flowOperator: redirectorB.address,
                from: alice,
            };

            await shouldUpdateFlowOperatorPermissionsAndValidateEvent({
                ...aclBaseData,
                permissions: ALLOW_CREATE.toString(),
                flowRateAllowance: FLOW_RATE1,
                signer,
            });

            t.addAlias("redirectorA", redirectorA.address);
            t.addAlias("redirectorB", redirectorB.address);

            // Attempting to do SuperApp callback to SuperApp should fail via ACL
            // originating from SuperApp
            // (SuperApp ACL) Alice -> redirectorB cb-> redirectorA cb-> Alice is not allowed
            await expectCustomError(
                redirectorB.startStreamToSelf(alice, FLOW_RATE1),
                superfluid,
                "APP_RULE",
                t.customErrorCode.APP_RULE_COMPOSITE_APP_IS_NOT_WHITELISTED
            );

            // Should still fail after allow composite app due to max app level rule
            await redirectorB.allowCompositeApp(redirectorA.address);
            await expectCustomError(
                redirectorB.startStreamToSelf(alice, FLOW_RATE1),
                superfluid,
                "APP_RULE",
                t.customErrorCode.APP_RULE_MAX_APP_LEVEL_REACHED
            );
        });

        it("#1.6.5 SuperApp to SuperApp (agreement creation originates from SuperApp)-Alice deletes", async () => {
            const redirectorA = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                alice,
                t.constants.APP_LEVEL_FINAL
            );
            const redirectorB = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                redirectorA.address,
                t.constants.APP_LEVEL_SECOND
            );

            t.addAlias("redirectorA", redirectorA.address);
            t.addAlias("redirectorB", redirectorB.address);
            const baseDeposit = getDeposit({
                testenv: t,
                flowRate: FLOW_RATE1,
            });
            const appCreditAdditionalDeposit = baseDeposit.mul(toBN(2));
            await t.transferBalance(
                "alice",
                "redirectorB",
                appCreditAdditionalDeposit
            );
            await redirectorB.startStreamToSuperApp(
                redirectorA.address,
                FLOW_RATE1
            );

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: FLOW_RATE1,
            });

            // State: RedirectorB -> RedirectorA -> Alice
            await agreementHelper.modifyFlow({
                type: FLOW_TYPE_DELETE,
                superToken: superToken.address,
                sender: redirectorA.address,
                receiver: alice,
                signer: await ethers.getSigner(alice),
            });

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0),
            });

            // OD not returned as the lender (redirectorB) did not terminate the flow
            await expectFlow({
                testenv: t,
                superToken,
                sender: "redirectorB",
                receiver: "redirectorA",
                flowRate: FLOW_RATE1,
                deposit: baseDeposit.mul(toBN(2)),
                owedDeposit: baseDeposit,
            });
            // State: RedirectorB -> RedirectorA
        });

        it("#1.6.6 SuperApp to SuperApp (agreement creation originates from SuperApp)-RDB deletes", async () => {
            const redirectorA = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                alice,
                t.constants.APP_LEVEL_FINAL
            );
            const redirectorB = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                redirectorA.address,
                t.constants.APP_LEVEL_SECOND
            );

            t.addAlias("redirectorA", redirectorA.address);
            t.addAlias("redirectorB", redirectorB.address);
            const baseDeposit = getDeposit({
                testenv: t,
                flowRate: FLOW_RATE1,
            });
            const appCreditAdditionalDeposit = baseDeposit.mul(toBN(2));
            await t.transferBalance(
                "alice",
                "redirectorB",
                appCreditAdditionalDeposit
            );
            await redirectorB.startStreamToSuperApp(
                redirectorA.address,
                FLOW_RATE1
            );

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: FLOW_RATE1,
            });

            // State: RedirectorB -> RedirectorA -> Alice
            await redirectorB.stopStreamToSuperApp(
                t.getAddress("redirectorB"),
                t.getAddress("redirectorA")
            );

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "redirectorB",
                value: toBN(0),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "redirectorA",
                value: toBN(0),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0),
            });
            // State: No flows
        });

        it("#1.6.7 SuperApp to SuperApp (agreement creation originates from SuperApp)-RDA deletes", async () => {
            const redirectorA = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                alice,
                t.constants.APP_LEVEL_FINAL
            );
            const redirectorB = await streamRedirectorFactory.deploy(
                superfluid.address,
                superToken.address,
                redirectorA.address,
                t.constants.APP_LEVEL_SECOND
            );

            t.addAlias("redirectorA", redirectorA.address);
            t.addAlias("redirectorB", redirectorB.address);
            const baseDeposit = getDeposit({
                testenv: t,
                flowRate: FLOW_RATE1,
            });
            const appCreditAdditionalDeposit = baseDeposit.mul(toBN(2));
            await t.transferBalance(
                "alice",
                "redirectorB",
                appCreditAdditionalDeposit
            );
            await redirectorB.startStreamToSuperApp(
                redirectorA.address,
                FLOW_RATE1
            );

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: FLOW_RATE1,
            });

            // State: RedirectorB -> RedirectorA -> Alice
            await redirectorA.stopStreamToSuperApp(
                t.getAddress("redirectorB"),
                t.getAddress("redirectorA")
            );

            console.log("redirectorA.address", redirectorA.address);
            console.log("redirectorB.address", redirectorB.address);

            // Validate net flows
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "redirectorB",
                value: toBN(0),
            });

            // because redirectorB is the target super app, we are calling
            // the callback on redirectorB, so the flow from RedirectorA -> Alice
            // is untouched
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "redirectorA",
                value: toBN(0).sub(FLOW_RATE1),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: FLOW_RATE1,
            });
            // State: RedirectorA -> Alice
        });
    });
});
