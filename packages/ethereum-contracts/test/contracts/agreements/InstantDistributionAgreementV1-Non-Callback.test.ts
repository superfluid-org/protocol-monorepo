import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {BigNumber} from "ethers";
import {assert, ethers, expect, web3} from "hardhat";

import {
    InstantDistributionAgreementV1,
    SuperToken,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectCustomError} from "../../utils/expectRevert";
import {toBN, toWad} from "../utils/helpers";

import {
    shouldApproveSubscription,
    shouldClaimPendingDistribution,
    shouldCreateIndex,
    shouldDeleteSubscription,
    shouldDistribute,
    shouldRevokeSubscription,
    shouldUpdateSubscription,
} from "./InstantDistributionAgreementV1.behaviour";

const {wad4human} = require("@decentral.ee/web3-helpers");

const ZERO_ADDRESS = ethers.constants.AddressZero;
const DEFAULT_INDEX_ID = "42";

interface ExpectedBalance {
    readonly address: string;
    readonly expectedBalance: BigNumber;
}

describe("IDAv1 | Non-Callback Tests", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    const {INIT_BALANCE} = t.configs;

    let alice: string, bob: string, carol: string;
    let superToken: SuperToken;
    let aliceSigner: SignerWithAddress, bobSigner: SignerWithAddress;
    let ida: InstantDistributionAgreementV1;

    before(async function () {
        await t.beforeTestSuite({
            isTruffle: true,
            nAccounts: 5,
        });
        ({alice, bob, carol} = t.aliases);
        ({ida} = t.contracts);

        superToken = t.tokens.SuperToken;
        aliceSigner = await ethers.getSigner(alice);
        bobSigner = await ethers.getSigner(bob);
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(async () => {
        t.afterEachTestCaseBenchmark();
    });

    // @note this is duplicated in scenarios.test.ts
    async function testExpectedBalances(expectedBalances: ExpectedBalance[]) {
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

    async function verifyAll() {
        await t.validateSystemInvariance();
    }

    context("#1 without callbacks", () => {
        describe("#1.1 index operations", async () => {
            it("#1.1.1 publisher can create a new index", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await verifyAll();
            });

            it("#1.1.2 publisher should fail to create the same index", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "createIndex",
                            [superToken.address, DEFAULT_INDEX_ID, "0x"]
                        ),
                        signer: aliceSigner,
                    }),
                    ida,
                    "IDA_INDEX_ALREADY_EXISTS"
                );
            });

            it("#1.1.3 publisher should fail to query non-existent index", async () => {
                const idata = await t.contracts.ida.getIndex(
                    superToken.address,
                    alice,
                    DEFAULT_INDEX_ID
                );
                assert.isFalse(idata.exist);
            });

            it("#1.1.4 publisher can update the index", async () => {
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

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("200"),
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("99.80")},
                    {address: bob, expectedBalance: toWad("0.00")},
                ]);

                await verifyAll();
            });

            it("#1.1.5 publisher should fail to update non-existent index", async () => {
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "updateIndex",
                            [superToken.address, DEFAULT_INDEX_ID, "42", "0x"]
                        ),
                        signer: aliceSigner,
                    }),
                    ida,
                    "IDA_INDEX_DOES_NOT_EXIST"
                );
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "distribute",
                            [superToken.address, DEFAULT_INDEX_ID, "42", "0x"]
                        ),
                        signer: aliceSigner,
                    }),
                    ida,
                    "IDA_INDEX_DOES_NOT_EXIST"
                );
                await expectCustomError(
                    ida.calculateDistribution(
                        superToken.address,
                        alice,
                        DEFAULT_INDEX_ID,
                        "42"
                    ),
                    ida,
                    "IDA_INDEX_DOES_NOT_EXIST"
                );
            });

            it("#1.1.6 publisher should fail to update index with smaller value", async () => {
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

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("200"),
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("99.80")},
                    {address: bob, expectedBalance: toWad("0.00")},
                ]);

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("200"),
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("99.80")},
                    {address: bob, expectedBalance: toWad("0.00")},
                ]);

                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "updateIndex",
                            [superToken.address, DEFAULT_INDEX_ID, "199", "0x"]
                        ),
                        signer: aliceSigner,
                    }),
                    ida,
                    "IDA_INDEX_SHOULD_GROW"
                );
            });

            it("#1.1.7 publisher can distribute by specifying amount", async () => {
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

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    amount: toWad(1),
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("99.00")},
                    {address: bob, expectedBalance: toWad("0.00")},
                ]);

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    amount: toWad(1),
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("98.00")},
                    {address: bob, expectedBalance: toWad("0.00")},
                ]);
            });

            it("#1.1.8 publisher cannot distribute with insufficient balance", async () => {
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
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "distribute",
                            [
                                superToken.address,
                                DEFAULT_INDEX_ID,
                                toWad(1).toString(),
                                "0x",
                            ]
                        ),
                        signer: aliceSigner,
                    }),
                    ida,
                    "IDA_INSUFFICIENT_BALANCE"
                );
            });

            it("#1.1.9 publisher should not be able to update subscription to zero address", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "updateSubscription",
                            [
                                superToken.address,
                                DEFAULT_INDEX_ID,
                                ZERO_ADDRESS,
                                toWad("0.001").toString(),
                                "0x",
                            ]
                        ),
                        signer: aliceSigner,
                    }),
                    ida,
                    "IDA_ZERO_ADDRESS_SUBSCRIBER"
                );
            });

            it("#1.1.10 publisher should not be able to delete zero address subscription", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "deleteSubscription",
                            [
                                superToken.address,
                                alice,
                                DEFAULT_INDEX_ID,
                                ZERO_ADDRESS,
                                "0x",
                            ]
                        ),
                        signer: aliceSigner,
                    }),
                    ida,
                    "IDA_ZERO_ADDRESS_SUBSCRIBER"
                );
            });

            it("#1.1.11 calling distribute when total units = 0 doesn't revert", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    amount: toWad(1),
                });
            });
        });

        describe("#1.2 subscription operations", async () => {
            it("#1.2.1 subscriber can approve a subscription", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });
                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });

                await verifyAll();
            });

            it("#1.2.2 subscriber should fail to approve a subscription twice", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });
                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "approveSubscription",
                            [superToken.address, alice, DEFAULT_INDEX_ID, "0x"]
                        ),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_SUBSCRIPTION_ALREADY_APPROVED"
                );
            });

            it("#1.2.3 subscriber can revoke its approved subscription", async () => {
                let subs;
                await t.upgradeBalance("alice", INIT_BALANCE);

                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 1);

                await shouldUpdateSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    units: toWad("0.001"),
                });

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("200"),
                });

                await shouldRevokeSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await verifyAll();
            });

            it("#1.2.4 publisher can delete a subscription", async () => {
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

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("200"),
                });

                await shouldDeleteSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    senderName: "alice",
                });
                const subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await verifyAll();
            });

            it("#1.2.5 publisher should fail to delete a non-existent subscription", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "deleteSubscription",
                            [
                                superToken.address,
                                alice,
                                DEFAULT_INDEX_ID,
                                bob,
                                "0x",
                            ]
                        ),
                        signer: aliceSigner,
                    }),
                    ida,
                    "IDA_SUBSCRIPTION_DOES_NOT_EXIST"
                );
            });

            it("#1.2.6 one should fail to delete other's subscription", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });
                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "deleteSubscription",
                            [
                                superToken.address,
                                alice,
                                DEFAULT_INDEX_ID,
                                bob,
                                "0x",
                            ]
                        ),
                        signer: await ethers.getSigner(t.getAddress("dan")),
                    }),
                    ida,
                    "IDA_OPERATION_NOT_ALLOWED"
                );
            });

            it("#1.2.7 subscriber can revoke and resubscribe multiple times to subscription", async () => {
                let subs;
                await t.upgradeBalance("alice", INIT_BALANCE);

                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 1);

                await verifyAll();

                await shouldRevokeSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await verifyAll();

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 1);

                await verifyAll();

                await shouldRevokeSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await verifyAll();
            });

            it("#1.2.8 subscriber can have multiple subscription and then with subId 0 revoked", async () => {
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

                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "carol",
                    indexId: DEFAULT_INDEX_ID,
                });
                await shouldUpdateSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "carol",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    units: toWad("0.002"),
                });

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "carol",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                let subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 2);
                assert.equal(subs.publishers[0], alice);
                assert.equal(subs.publishers[1], carol);
                await verifyAll();

                await shouldRevokeSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 1);
                assert.equal(subs.publishers[0], carol);
                await verifyAll();
            });

            it("#1.2.10 one should fail to use a subscription of a non-existent index", async () => {
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "approveSubscription",
                            [superToken.address, alice, DEFAULT_INDEX_ID, "0x"]
                        ),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_INDEX_DOES_NOT_EXIST"
                );
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "updateSubscription",
                            [
                                superToken.address,
                                DEFAULT_INDEX_ID,
                                bob,
                                "42",
                                "0x",
                            ]
                        ),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_INDEX_DOES_NOT_EXIST"
                );
                await expectCustomError(
                    ida.getSubscription(
                        superToken.address,
                        alice,
                        DEFAULT_INDEX_ID,
                        bob
                    ),
                    ida,
                    "IDA_INDEX_DOES_NOT_EXIST"
                );
            });

            it("#1.2.11 subscriber can revoke its subscription", async () => {
                let subs;
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
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 1);

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("200"),
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("99.8")},
                    {address: bob, expectedBalance: toWad("0.2")},
                ]);

                await shouldRevokeSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN(500),
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("99.5")},
                    {address: bob, expectedBalance: toWad("0.2")},
                ]);

                await verifyAll();
            });

            it("#1.2.12 subscriber should fail to revoke an pending subscription", async () => {
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
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "revokeSubscription",
                            [superToken.address, alice, DEFAULT_INDEX_ID, "0x"]
                        ),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_SUBSCRIPTION_IS_NOT_APPROVED"
                );
            });

            it("#1.2.13 subscriber should fail to revoke a non-existent subscription", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "revokeSubscription",
                            [superToken.address, alice, DEFAULT_INDEX_ID, "0x"]
                        ),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_SUBSCRIPTION_DOES_NOT_EXIST"
                );
            });

            it("#1.2.14 subscriber should fail to revoke a subscription of a non-existent index", async () => {
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData(
                            "revokeSubscription",
                            [superToken.address, alice, DEFAULT_INDEX_ID, "0x"]
                        ),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_INDEX_DOES_NOT_EXIST"
                );
            });

            it("#1.2.15 publisher should be able to delete an approved subscription", async () => {
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

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN(500),
                });

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });

                await shouldDeleteSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    senderName: "alice",
                });
            });

            // @note previous #1.2.16 moved to foundry
        });

        describe("#1.3 distribution workflows", () => {
            it("#1.3.1 approveSubscription -> updateSubscription -> updateIndex", async () => {
                let subs;
                await t.upgradeBalance("alice", INIT_BALANCE);

                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });

                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                expect(subs.indexIds.length).to.equal(1);
                expect(subs.publishers[0]).to.equal(alice);
                expect(subs.indexIds[0]).to.equal(Number(DEFAULT_INDEX_ID));
                expect(subs.unitsList[0]).to.equal(toBN(0));

                await shouldUpdateSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    units: toWad("0.001"),
                });

                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                expect(subs.indexIds.length).to.equal(1);
                expect(subs.publishers[0]).to.equal(alice);
                expect(subs.indexIds[0]).to.equal(Number(DEFAULT_INDEX_ID));
                expect(subs.unitsList[0]).to.equal(toWad("0.001"));

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("100"),
                });

                await verifyAll();
            });

            it("#1.3.2 updateSubscription -> updateIndex -> approveSubscription", async () => {
                let subs;
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
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldUpdateSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    units: toWad("0.003"),
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("100"),
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await verifyAll();

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 1);
                assert.equal(subs.publishers[0], alice);
                assert.equal(subs.indexIds[0], Number(DEFAULT_INDEX_ID));
                assert.equal(
                    subs.unitsList[0].toString(),
                    toWad("0.003").toString()
                );

                await verifyAll();
            });

            it("#1.3.3 updateSubscription -> approveSubscription -> updateIndex", async () => {
                let subs;
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
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 1);
                assert.equal(subs.publishers[0], alice);
                assert.equal(subs.indexIds[0], Number(DEFAULT_INDEX_ID));
                assert.equal(
                    subs.unitsList[0].toString(),
                    toWad("0.001").toString()
                );

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("100"),
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 1);
                assert.equal(subs.publishers[0], alice);
                assert.equal(subs.indexIds[0], Number(DEFAULT_INDEX_ID));
                assert.equal(
                    subs.unitsList[0].toString(),
                    toWad("0.001").toString()
                );

                await verifyAll();
            });

            it("#1.3.4 2x(updateSubscription -> shouldDistribute) ->  approveSubscription", async () => {
                let subs;
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
                    units: toWad("0.003"),
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("100"),
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldUpdateSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    units: toWad("0.005"),
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("200"),
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 1);
                assert.equal(subs.publishers[0], alice);
                assert.equal(subs.indexIds[0], Number(DEFAULT_INDEX_ID));
                assert.equal(
                    subs.unitsList[0].toString(),
                    toWad("0.005").toString()
                );

                await verifyAll();
            });
        });

        describe("#1.4 claim workflows", () => {
            it("#1.4.1 subscriber can claim distribution from its pending subscription", async () => {
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
                    units: toWad("0.003"),
                });

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("100"),
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("99.7")},
                    {address: bob, expectedBalance: toWad("0.0")},
                ]);

                const subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldClaimPendingDistribution({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    senderName: "bob",
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("99.7")},
                    {address: bob, expectedBalance: toWad("0.3")},
                ]);

                await shouldClaimPendingDistribution({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    senderName: "bob",
                });
                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("99.7")},
                    {address: bob, expectedBalance: toWad("0.3")},
                ]);

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("300"),
                });

                await verifyAll();
            });

            it("#1.4.2 anyone can claim distribution on behalf of other", async () => {
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
                    units: toWad("0.003"),
                });
                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    indexValue: toBN("100"),
                });
                await shouldClaimPendingDistribution({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    senderName: "dan",
                });
            });

            it("#1.4.3 one should not claim from a non-existent subscription", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData("claim", [
                            superToken.address,
                            alice,
                            DEFAULT_INDEX_ID,
                            bob,
                            "0x",
                        ]),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_SUBSCRIPTION_DOES_NOT_EXIST"
                );
            });

            it("#1.4.4 one should not claim from a subscription of a non-existent index", async () => {
                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData("claim", [
                            superToken.address,
                            alice,
                            DEFAULT_INDEX_ID,
                            bob,
                            "0x",
                        ]),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_INDEX_DOES_NOT_EXIST"
                );
            });

            it("#1.4.5 subscriber should not claim from a already approved subscription", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });

                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData("claim", [
                            superToken.address,
                            alice,
                            DEFAULT_INDEX_ID,
                            bob,
                            "0x",
                        ]),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_SUBSCRIPTION_ALREADY_APPROVED"
                );
            });

            it("#1.4.6 cannot claim from zero address", async () => {
                await shouldCreateIndex({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                });

                await expectCustomError(
                    t.agreementHelper.callAgreement({
                        agreementAddress: ida.address,
                        callData: t.agreementHelper.getIDACallData("claim", [
                            superToken.address,
                            alice,
                            DEFAULT_INDEX_ID,
                            ZERO_ADDRESS,
                            "0x",
                        ]),
                        signer: bobSigner,
                    }),
                    ida,
                    "IDA_ZERO_ADDRESS_SUBSCRIBER"
                );
            });
        });

        describe("#1.5 complex sequences", () => {
            it("#1.5.1 distributions using the correct token", async () => {
                await t.upgradeBalance("alice", INIT_BALANCE);
                const {superToken: superToken2} = await t.deployNewToken(
                    "TEST2",
                    {
                        doUpgrade: true,
                        isTruffle: true,
                    }
                );

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
                    units: toWad(0.01),
                });

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    amount: toWad(50),
                });

                expect(
                    await superToken.balanceOf(t.getAddress("alice"))
                ).to.equal(toWad("50"));
                expect(
                    await superToken2.balanceOf(t.getAddress("alice"))
                ).to.equal(INIT_BALANCE);
            });

            it("#1.5.2 context should not be exploited", async () => {
                const {superfluid, ida} = t.contracts;
                await expect(
                    superfluid.callAgreement(
                        ida.address,
                        t.agreementHelper.idaInterface.encodeFunctionData(
                            "createIndex",
                            [
                                superToken.address,
                                DEFAULT_INDEX_ID,
                                web3.eth.abi.encodeParameters(
                                    ["bytes", "bytes"],
                                    ["0xdeadbeef", "0x"]
                                ),
                            ]
                        ),
                        "0x"
                    )
                ).to.be.revertedWith("invalid ctx");
            });

            it("#1.5.3 publisher subscribing to their own index and receiving a distribution", async () => {
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
                    subscriberName: "alice",
                    units: toWad(0.01),
                });

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "alice",
                });

                await t.agreementHelper.callAgreement({
                    agreementAddress: ida.address,
                    callData: t.agreementHelper.getIDACallData("distribute", [
                        superToken.address,
                        DEFAULT_INDEX_ID,
                        toWad(30).toString(),
                        "0x",
                    ]),
                    signer: await ethers.getSigner(alice),
                });

                await testExpectedBalances([
                    {address: alice, expectedBalance: INIT_BALANCE},
                ]);
            });

            it("#1.5.4 subscribe -> distribute -> unsubscribe -> distribute -> subscribe -> distribute", async () => {
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
                    units: toWad(0.01),
                });

                await shouldApproveSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    amount: toWad(50),
                });

                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("50.00")},
                    {address: bob, expectedBalance: toWad("50.00")},
                ]);
                await shouldRevokeSubscription({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                });
                const subs = await t.contracts.ida.listSubscriptions(
                    superToken.address,
                    bob
                );
                assert.equal(subs.indexIds.length, 0);

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    amount: toWad(25),
                });

                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("25.00")},
                    {address: bob, expectedBalance: toWad("50.00")},
                ]);

                await shouldClaimPendingDistribution({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    senderName: "alice",
                });

                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("25.00")},
                    {address: bob, expectedBalance: toWad("75.00")},
                ]);

                await shouldDistribute({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    amount: toWad(25),
                });

                await shouldClaimPendingDistribution({
                    testenv: t,
                    superToken,
                    publisherName: "alice",
                    indexId: DEFAULT_INDEX_ID,
                    subscriberName: "bob",
                    senderName: "alice",
                });

                await testExpectedBalances([
                    {address: alice, expectedBalance: toWad("0")},
                    {address: bob, expectedBalance: toWad("100.00")},
                ]);
            });
        });
    });

    context("#3 misc", async () => {
        it("#3.1 only authorized host can access token", async () => {
            const fakeHostFactory =
                await ethers.getContractFactory("FakeSuperfluidMock");
            const fakeHost = await fakeHostFactory.deploy();
            const idaAddress = t.contracts.ida.address;
            await expect(
                fakeHost.callAgreement(
                    idaAddress,
                    t.agreementHelper.idaInterface.encodeFunctionData(
                        "createIndex",
                        [superToken.address, 42, "0x"]
                    )
                )
            ).to.be.revertedWith("unauthorized host");
            await expect(
                fakeHost.callAgreement(
                    idaAddress,
                    t.agreementHelper.idaInterface.encodeFunctionData(
                        "updateIndex",
                        [superToken.address, 42, 9000, "0x"]
                    )
                )
            ).to.be.revertedWith("unauthorized host");
            await expect(
                fakeHost.callAgreement(
                    idaAddress,
                    t.agreementHelper.idaInterface.encodeFunctionData(
                        "distribute",
                        [superToken.address, 42, 9000, "0x"]
                    )
                )
            ).to.be.revertedWith("unauthorized host");
            await expect(
                fakeHost.callAgreement(
                    idaAddress,
                    t.agreementHelper.idaInterface.encodeFunctionData(
                        "approveSubscription",
                        [superToken.address, bob, 42, "0x"]
                    )
                )
            ).to.be.revertedWith("unauthorized host");
            await expect(
                fakeHost.callAgreement(
                    idaAddress,
                    t.agreementHelper.idaInterface.encodeFunctionData(
                        "updateSubscription",
                        [superToken.address, 42, alice, 1000, "0x"]
                    )
                )
            ).to.be.revertedWith("unauthorized host");
        });
    });
});
