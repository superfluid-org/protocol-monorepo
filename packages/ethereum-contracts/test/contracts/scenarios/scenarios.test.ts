import {expect} from "chai";
import {assert} from "chai";
import {BigNumber} from "ethers";
import {ethers} from "hardhat";

import {SuperToken} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectCustomError} from "../../utils/expectRevert";
import {VerifyOptions} from "../agreements/Agreement.types";
import AgreementHelper, {FLOW_TYPE_CREATE} from "../agreements/AgreementHelper";
import {
    expectNetFlow,
    shouldCreateFlow,
} from "../agreements/ConstantFlowAgreementV1.behavior";
import CFADataModel from "../agreements/ConstantFlowAgreementV1.data";
import {
    shouldApproveSubscription,
    shouldCreateIndex,
    shouldDeleteSubscription,
    shouldDistribute,
    shouldUpdateSubscription,
} from "../agreements/InstantDistributionAgreementV1.behaviour";
import {toBN, toWad, wad4human} from "../utils/helpers";

const DEFAULT_INDEX_ID = "42";

interface ExpectedBalance {
    readonly address: string;
    readonly expectedBalance: BigNumber;
}

describe("Superfluid scenarios", function () {
    this.timeout(300e3);
    let agreementHelper: AgreementHelper;

    const t = TestEnvironment.getSingleton();
    const {FLOW_RATE1, INIT_BALANCE} = t.configs;

    let alice: string, bob: string, carol: string, dan: string;
    let superToken: SuperToken;

    before(async function () {
        await t.beforeTestSuite({
            nAccounts: 5,
        });
        ({alice, bob, carol, dan} = t.aliases);

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

    async function verifyAll(opts?: VerifyOptions) {
        const cfaDataModel = new CFADataModel(t, superToken);
        const block2 = await ethers.provider.getBlock("latest");
        await t.validateExpectedBalances(() => {
            cfaDataModel.syncAccountExpectedBalanceDeltas({
                superToken: superToken.address,
                timestamp: block2.timestamp,
            });
        });
        await t.validateSystemInvariance(opts);
    }

    async function timeTravelOnceAndVerifyAll(opts: VerifyOptions = {}) {
        await t.timeTravelOnce(opts.time);
        await verifyAll(opts);
    }

    async function testExpectedBalances(
        expectedBalances: Array<ExpectedBalance>
    ) {
        for (let i = 0; i < expectedBalances.length; ++i) {
            const account = expectedBalances[i].address;
            const expectedBalance = expectedBalances[i].expectedBalance;
            //const expectedDeposit = expectedBalances[i][2] || "0";
            const balance = await superToken.balanceOf(account);
            console.log(
                `${t.toAlias(account)}'s current balance: `,
                wad4human(balance)
            );
            assert.equal(balance.toString(), expectedBalance.toString());
        }
    }

    context("#1.x Multi-accounts CFA scenarios", () => {
        it("#1.1 two accounts sending to each other with the same flow rate", async () => {
            await t.upgradeBalance("alice", t.configs.INIT_BALANCE);

            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "alice",
                receiver: "bob",
                flowRate: FLOW_RATE1,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: FLOW_RATE1.mul(toBN(0).sub(toBN(1))),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: FLOW_RATE1,
            });
            await timeTravelOnceAndVerifyAll();

            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "bob",
                receiver: "alice",
                flowRate: FLOW_RATE1,
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
            await timeTravelOnceAndVerifyAll();
        });

        it("#1.2 three accounts forming a flow loop", async () => {
            // alice -> bob -> carol
            //   ^---------------|
            await t.upgradeBalance("alice", t.configs.INIT_BALANCE);

            const flowRateBC = FLOW_RATE1.mul(2).div(3);
            const flowRateCA = FLOW_RATE1.div(3);

            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "alice",
                receiver: "bob",
                flowRate: FLOW_RATE1,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0).sub(FLOW_RATE1),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: FLOW_RATE1,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "carol",
                value: "0",
            });
            await timeTravelOnceAndVerifyAll();

            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "bob",
                receiver: "carol",
                flowRate: flowRateBC,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0).sub(FLOW_RATE1),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: FLOW_RATE1.sub(flowRateBC),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "carol",
                value: flowRateBC,
            });
            await timeTravelOnceAndVerifyAll();

            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "carol",
                receiver: "alice",
                flowRate: flowRateCA,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(flowRateCA).sub(FLOW_RATE1),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: FLOW_RATE1.sub(flowRateBC),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "carol",
                value: flowRateBC.sub(flowRateCA),
            });
            await timeTravelOnceAndVerifyAll();
        });

        it("#1.3 a slight complex flow map", async () => {
            await t.upgradeBalance("alice", t.configs.INIT_BALANCE.mul(2));

            const flowRateBD = FLOW_RATE1.mul(2).div(3);
            const flowRateDC = FLOW_RATE1.div(3);
            //const flowRate;

            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "alice",
                receiver: "bob",
                flowRate: FLOW_RATE1,
            });
            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "alice",
                receiver: "carol",
                flowRate: FLOW_RATE1,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0).sub(FLOW_RATE1.mul(2)),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: FLOW_RATE1,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "carol",
                value: FLOW_RATE1,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "dan",
                value: "0",
            });
            await timeTravelOnceAndVerifyAll();

            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "bob",
                receiver: "dan",
                flowRate: flowRateBD,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0).sub(FLOW_RATE1.mul(2)),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: FLOW_RATE1.sub(flowRateBD),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "carol",
                value: FLOW_RATE1,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "dan",
                value: flowRateBD,
            });
            await timeTravelOnceAndVerifyAll();

            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "dan",
                receiver: "carol",
                flowRate: flowRateDC,
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "alice",
                value: toBN(0).sub(FLOW_RATE1.mul(2)),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "bob",
                value: FLOW_RATE1.sub(flowRateBD),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "carol",
                value: FLOW_RATE1.add(flowRateDC),
            });
            await expectNetFlow({
                testenv: t,
                superToken,
                account: "dan",
                value: flowRateBD.sub(flowRateDC),
            });
            await timeTravelOnceAndVerifyAll();
        });
    });

    context("#2.x Multi-accounts IDA Scenarios", () => {
        it("#2.1 1to3 distribution scenario", async () => {
            await t.upgradeBalance("alice", INIT_BALANCE);

            await shouldCreateIndex({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
            });

            const subscribers = [
                {address: bob, units: toWad("0.0001"), approve: true},
                {address: carol, units: toWad("0.0002"), approve: true},
                {address: dan, units: toWad("0.0003"), approve: false},
            ];
            for (let i = 0; i < subscribers.length; ++i) {
                const subscriberAddr = subscribers[i].address;
                const subscriptionUnits = subscribers[i].units;
                const doApprove = subscribers[i].approve;
                const subscriberName = t.toAlias(subscriberAddr);

                if (doApprove) {
                    await shouldApproveSubscription({
                        testenv: t,
                        superToken,
                        publisherName: "alice",
                        indexId: DEFAULT_INDEX_ID,
                        subscriberName: subscriberName,
                    });
                }

                await shouldUpdateSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: subscriberName,
                    units: subscriptionUnits,
                });

                const subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    subscriberAddr
                );
                if (doApprove) {
                    expect(subs.indexIds.length).to.equal(1);
                    expect(subs.publishers[0]).to.equal(alice);
                    expect(subs.indexIds[0]).to.equal(Number(DEFAULT_INDEX_ID));
                    expect(subs.unitsList[0]).to.equal(subscriptionUnits);
                } else {
                    expect(subs.indexIds.length).to.equal(0);
                }
            }

            await shouldDistribute({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                indexValue: toBN(100),
            });
            await testExpectedBalances([
                {address: alice, expectedBalance: toWad("99.94")},
                {address: bob, expectedBalance: toWad("0.01")},
                {address: carol, expectedBalance: toWad("0.02")},
                {address: dan, expectedBalance: toWad("0.00")},
            ]);

            await shouldDistribute({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                indexValue: toBN(300),
            });
            await testExpectedBalances([
                {address: alice, expectedBalance: toWad("99.82")},
                {address: bob, expectedBalance: toWad("0.03")},
                {address: carol, expectedBalance: toWad("0.06")},
                {address: dan, expectedBalance: toWad("0.00")},
            ]);

            await shouldDeleteSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "dan",
                senderName: "alice",
            });
            await testExpectedBalances([
                {address: alice, expectedBalance: toWad("99.82")},
                {address: bob, expectedBalance: toWad("0.03")},
                {address: carol, expectedBalance: toWad("0.06")},
                {address: dan, expectedBalance: toWad("0.09")},
            ]);

            await shouldDistribute({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                indexValue: toBN(400),
            });
            await testExpectedBalances([
                {address: alice, expectedBalance: toWad("99.79")},
                {address: bob, expectedBalance: toWad("0.04")},
                {address: carol, expectedBalance: toWad("0.08")},
                {address: dan, expectedBalance: toWad("0.09")},
            ]);

            await verifyAll();
        });

        it("#2.2 2to1 distribution scenario", async () => {
            await t.upgradeBalance("alice", INIT_BALANCE);
            await t.upgradeBalance("bob", INIT_BALANCE);

            // alice and bob create indices and dan subscribes to them
            const publishers = [
                {address: alice, units: toWad("0.0001"), approve: true},
                {address: bob, units: toWad("0.0002"), approve: false},
            ];
            for (let i = 0; i < publishers.length; ++i) {
                const publisherAddr = publishers[i].address;
                const subscriptionUnits = publishers[i].units;
                const doApprove = publishers[i].approve;
                const publisherName = t.toAlias(publisherAddr);

                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName,
                    indexId: DEFAULT_INDEX_ID,
                });

                if (doApprove) {
                    await shouldApproveSubscription({
                        testenv: t,
                        superToken,
                        publisherName,
                        indexId: DEFAULT_INDEX_ID,
                        subscriberName: "dan",
                    });
                }

                await shouldUpdateSubscription({
                    testenv: t,
                    superToken,
                    publisherName,
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "dan",
                    units: subscriptionUnits,
                });
            }

            const subs = await t.contracts.ida.listSubscriptions(
                superToken.address,
                dan
            );
            assert.equal(subs.indexIds.length, 1);
            assert.equal(subs.publishers[0], alice);
            assert.equal(subs.indexIds[0], Number(DEFAULT_INDEX_ID));
            assert.equal(wad4human(subs.unitsList[0]), "0.0001");

            // Alice distributes tokens (100 * 0.0001 = 0.01)
            await shouldDistribute({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                indexValue: toBN(100),
            });
            await testExpectedBalances([
                {address: alice, expectedBalance: toWad("99.99")},
                {address: bob, expectedBalance: toWad("100.00")},
                {address: dan, expectedBalance: toWad("0.01")},
            ]);

            // Bob distributes tokens (200 * 0.0002 = 0.04)
            await shouldDistribute({
                testenv: t,
                superToken,
                publisherName: "bob",
                indexId: DEFAULT_INDEX_ID,
                indexValue: toBN(200),
            });
            await testExpectedBalances([
                {address: alice, expectedBalance: toWad("99.99")},
                {address: bob, expectedBalance: toWad("99.96")},
                {address: dan, expectedBalance: toWad("0.01")},
            ]);

            // Alice update Dan's subscription with more units
            await shouldUpdateSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "dan",
                units: toWad("0.0003"),
            });

            // Alice distributes tokens again (100 * 0.0003 = 0.03)
            await shouldDistribute({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                indexValue: toBN(200),
            });
            await testExpectedBalances([
                {address: alice, expectedBalance: toWad("99.96")},
                {address: bob, expectedBalance: toWad("99.96")},
                {address: dan, expectedBalance: toWad("0.04")},
            ]);

            await shouldApproveSubscription({
                testenv: t,
                superToken,
                publisherName: "bob",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "dan",
            });
            await testExpectedBalances([
                {address: alice, expectedBalance: toWad("99.96")},
                {address: bob, expectedBalance: toWad("99.96")},
                {address: dan, expectedBalance: toWad("0.08")},
            ]);

            await verifyAll();
        });
    });

    context("#3.x Special CFA+IDA Scenarios", () => {
        it("#3.1 distributions should not dip into the flow deposit", async () => {
            await t.upgradeBalance("alice", INIT_BALANCE);
            await shouldCreateIndex({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
            });

            await shouldUpdateSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "bob",
                units: toWad("0.001"),
            });

            await agreementHelper.modifyFlow({
                type: FLOW_TYPE_CREATE,
                superToken: superToken.address,
                sender: alice,
                receiver: bob,
                flowRate: FLOW_RATE1,
            });

            await t.timeTravelOnce();

            await expectCustomError(
                t.agreementHelper.callAgreement({
                    agreementAddress: t.contracts.ida.address,
                    callData: t.agreementHelper.getIDACallData("distribute", [
                        superToken.address,
                        DEFAULT_INDEX_ID,
                        toWad(75).toString(),
                        "0x",
                    ]),
                    signer: await ethers.getSigner(alice),
                }),
                t.contracts.ida,
                "IDA_INSUFFICIENT_BALANCE"
            );
        });

        it("#3.2 receiving a distribution with an incoming stream", async () => {
            await t.upgradeBalance("alice", INIT_BALANCE);
            await t.upgradeBalance("bob", INIT_BALANCE);

            await shouldCreateIndex({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
            });

            await shouldUpdateSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "bob",
                units: toWad("0.001"),
            });

            await shouldApproveSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "bob",
            });

            await shouldCreateFlow({
                testenv: t,
                superToken,
                sender: "bob",
                receiver: "alice",
                flowRate: FLOW_RATE1,
            });
            await t.timeTravelOnce();
            await t.validateSystemInvariance();

            await t.agreementHelper.callAgreement({
                agreementAddress: t.contracts.ida.address,
                callData: t.agreementHelper.getIDACallData("distribute", [
                    superToken.address,
                    DEFAULT_INDEX_ID,
                    toWad(20).toString(),
                    "0x",
                ]),
                signer: await ethers.getSigner(alice),
            });
            await t.timeTravelOnce();
            await t.validateSystemInvariance();
        });

        it("#3.3 critical user receiver receiving distribution and not being critical anymore", async () => {
            await t.upgradeBalance("bob", toWad(23));

            await shouldCreateIndex({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
            });

            await shouldUpdateSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "bob",
                units: toWad("0.001"),
            });

            await shouldApproveSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "bob",
            });

            await agreementHelper.modifyFlow({
                type: FLOW_TYPE_CREATE,
                superToken: superToken.address,
                sender: bob,
                receiver: alice,
                flowRate: FLOW_RATE1,
            });

            await t.timeTravelOnce();

            assert.isTrue(await superToken.isAccountCriticalNow(bob));

            await t.agreementHelper.callAgreement({
                agreementAddress: t.contracts.ida.address,
                callData: t.agreementHelper.getIDACallData("distribute", [
                    superToken.address,
                    DEFAULT_INDEX_ID,
                    toWad(20).toString(),
                    "0x",
                ]),
                signer: await ethers.getSigner(alice),
            });

            assert.isFalse(await superToken.isAccountCriticalNow(bob));
        });

        it("#3.4 not enough balance for distribution -> receive stream -> distribute", async () => {
            await t.upgradeBalance("bob", INIT_BALANCE);
            await shouldCreateIndex({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
            });

            await shouldUpdateSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "bob",
                units: toWad("0.001"),
            });

            await expectCustomError(
                t.agreementHelper.callAgreement({
                    agreementAddress: t.contracts.ida.address,
                    callData: t.agreementHelper.getIDACallData("distribute", [
                        superToken.address,
                        DEFAULT_INDEX_ID,
                        toWad(24).toString(),
                        "0x",
                    ]),
                    signer: await ethers.getSigner(alice),
                }),
                t.contracts.ida,
                "IDA_INSUFFICIENT_BALANCE"
            );

            await agreementHelper.modifyFlow({
                type: FLOW_TYPE_CREATE,
                superToken: superToken.address,
                sender: bob,
                receiver: alice,
                flowRate: FLOW_RATE1,
            });

            await t.timeTravelOnce();

            await t.agreementHelper.callAgreement({
                agreementAddress: t.contracts.ida.address,
                callData: t.agreementHelper.getIDACallData("distribute", [
                    superToken.address,
                    DEFAULT_INDEX_ID,
                    toWad(20).toString(),
                    "0x",
                ]),
                signer: await ethers.getSigner(alice),
            });
        });

        it("#3.5 distributing with an outgoing stream", async () => {
            await t.upgradeBalance("alice", INIT_BALANCE);
            await shouldCreateIndex({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
            });

            await shouldUpdateSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "bob",
                units: toWad("0.001"),
            });

            await shouldApproveSubscription({
                testenv: t,
                superToken,
                publisherName: "alice",
                indexId: DEFAULT_INDEX_ID,
                subscriberName: "bob",
            });

            await agreementHelper.modifyFlow({
                type: FLOW_TYPE_CREATE,
                superToken: superToken.address,
                sender: alice,
                receiver: bob,
                flowRate: FLOW_RATE1,
            });
            await t.timeTravelOnce();
            await t.validateSystemInvariance();

            await t.agreementHelper.callAgreement({
                agreementAddress: t.contracts.ida.address,
                callData: t.agreementHelper.getIDACallData("distribute", [
                    superToken.address,
                    DEFAULT_INDEX_ID,
                    toWad(20).toString(),
                    "0x",
                ]),
                signer: await ethers.getSigner(alice),
            });
            await t.timeTravelOnce();
            await t.validateSystemInvariance();
        });
    });
});
