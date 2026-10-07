import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {assert} from "chai";
import {ethers} from "hardhat";

import {
    IDASuperAppTester,
    InstantDistributionAgreementV1,
    SuperToken,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectCustomError} from "../../utils/expectRevert";
import {encodeAbiParameters, sha3, toWad} from "../utils/helpers";

import {
    shouldApproveSubscription,
    shouldClaimPendingDistribution,
    shouldCreateIndex,
    shouldDeleteSubscription,
    shouldDistribute,
    shouldUpdateSubscription,
} from "./InstantDistributionAgreementV1.behaviour";

const expectEvent = require("../../lib/expect-emit");

const DEFAULT_INDEX_ID = "42";

describe("IDAv1 | Callback Tests", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    const {INIT_BALANCE} = t.configs;

    let alice: string;
    let superToken: SuperToken;
    let aliceSigner: SignerWithAddress;
    let ida: InstantDistributionAgreementV1;

    before(async function () {
        await t.beforeTestSuite({
            nAccounts: 5,
        });
        ({alice} = t.aliases);
        ({ida} = t.contracts);

        superToken = t.tokens.SuperToken;
        aliceSigner = await ethers.getSigner(alice);
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(async () => {
        t.afterEachTestCaseBenchmark();
    });

    let app: IDASuperAppTester;

    function idaSelector(functionName: string) {
        return t.sf.agreements.ida.abi.filter(
            (i: {name: string}) => i.name === functionName
        )[0].signature;
    }

    beforeEach(async () => {
        const appFactory = await ethers.getContractFactory("IDASuperAppTester");
        app = await appFactory.deploy(
            t.contracts.superfluid.address,
            1 /* APP_TYPE_FINAL_LEVEL */,
            t.contracts.ida.address,
            superToken.address,
            DEFAULT_INDEX_ID
        );
        await app.deployed();
        t.addAlias("app", app.address);
    });

    afterEach(async () => {
        assert.isFalse(
            await t.contracts.superfluid.isAppJailed(app.address),
            "App got jailed"
        );
    });

    it("#1.1 approveSubscription AgreementCreated callbacks", async () => {
        const tx = await shouldApproveSubscription({
            testenv: t,
            superToken,
            publisherName: "app",
            indexId: DEFAULT_INDEX_ID,
            subscriberName: "alice",
            userData: encodeAbiParameters(
                ["bytes32", "bytes4", "bytes"],
                [sha3("created"), idaSelector("approveSubscription"), "0x"]
            ),
        });
        await expectEvent.notEmitted.inTransaction(
            tx.tx,
            app,
            "SubscriptionDataBefore"
        );
        await expectEvent.inTransaction(tx.tx, app, "SubscriptionDataAfter", {
            publisher: app.address,
            indexId: DEFAULT_INDEX_ID,
            approved: true,
            units: "0",
            pendingDistribution: "0",
        });
    });

    it("#1.2 approveSubscription AgreementUpdated callbacks", async () => {
        const units = toWad("0.003");
        await shouldUpdateSubscription({
            testenv: t,
            superToken,
            publisherName: "app",
            indexId: DEFAULT_INDEX_ID,
            subscriberName: "alice",
            units,
            fn: async () => {
                console.log("app.updateSubscription alice");
                return await app.updateSubscription(alice, units);
            },
        });
        const tx = await shouldApproveSubscription({
            testenv: t,
            superToken,
            publisherName: "app",
            indexId: DEFAULT_INDEX_ID,
            subscriberName: "alice",
            userData: encodeAbiParameters(
                ["bytes32", "bytes4", "bytes"],
                [sha3("updated"), idaSelector("approveSubscription"), "0x"]
            ),
        });
        await expectEvent.inTransaction(tx.tx, app, "SubscriptionDataBefore", {
            publisher: app.address,
            indexId: DEFAULT_INDEX_ID,
            approved: false,
            units,
            pendingDistribution: "0",
        });
        await expectEvent.inTransaction(tx.tx, app, "SubscriptionDataAfter", {
            publisher: app.address,
            indexId: DEFAULT_INDEX_ID,
            approved: true,
            units,
            pendingDistribution: "0",
        });
    });

    it("#1.3 updateSubscription AgreementCreated callbacks", async () => {
        const units = toWad("0.003");
        await shouldCreateIndex({
            testenv: t,
            superToken,
            publisherName: "alice",
            indexId: DEFAULT_INDEX_ID,
        });
        const tx = await shouldUpdateSubscription({
            testenv: t,
            superToken,
            publisherName: "alice",
            indexId: DEFAULT_INDEX_ID,
            subscriberName: "app",
            units,
            userData: encodeAbiParameters(
                ["bytes32", "bytes4", "bytes"],
                [sha3("created"), idaSelector("updateSubscription"), "0x"]
            ),
        });
        await expectEvent.notEmitted.inTransaction(
            tx.tx,
            app,
            "SubscriptionDataBefore"
        );
        await expectEvent.inTransaction(tx.tx, app, "SubscriptionDataAfter", {
            publisher: alice,
            indexId: DEFAULT_INDEX_ID,
            approved: false,
            units,
            pendingDistribution: "0",
        });
    });

    it("#1.4 updateSubscription AgreementUpdated callbacks", async () => {
        const units1 = toWad("0.003");
        const units2 = toWad("0.004");
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
            subscriberName: "app",
            units: units1,
            userData: encodeAbiParameters(
                ["bytes32", "bytes4", "bytes"],
                [sha3("created"), idaSelector("updateSubscription"), "0x"]
            ),
        });
        const tx = await shouldUpdateSubscription({
            testenv: t,
            superToken,
            publisherName: "alice",
            indexId: DEFAULT_INDEX_ID,
            subscriberName: "app",
            units: units2,
            userData: encodeAbiParameters(
                ["bytes32", "bytes4", "bytes"],
                [sha3("updated"), idaSelector("updateSubscription"), "0x"]
            ),
        });
        await expectEvent.inTransaction(tx.tx, app, "SubscriptionDataBefore", {
            publisher: alice,
            indexId: DEFAULT_INDEX_ID,
            approved: false,
            units: units1,
            pendingDistribution: "0",
        });
        await expectEvent.inTransaction(tx.tx, app, "SubscriptionDataAfter", {
            publisher: alice,
            indexId: DEFAULT_INDEX_ID,
            approved: false,
            units: units2,
            pendingDistribution: "0",
        });
    });

    it("#1.6 publisher deleteSubscription callbacks", async () => {
        const units = toWad("0.003");
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
            subscriberName: "app",
            units,
            userData: encodeAbiParameters(
                ["bytes32", "bytes4", "bytes"],
                [sha3("created"), idaSelector("updateSubscription"), "0x"]
            ),
        });
        const tx = await shouldDeleteSubscription({
            testenv: t,
            superToken,
            publisherName: "alice",
            indexId: DEFAULT_INDEX_ID,
            subscriberName: "app",
            senderName: "alice",
            userData: encodeAbiParameters(
                ["bytes32", "bytes4", "bytes"],
                [sha3("deleted"), idaSelector("deleteSubscription"), "0x"]
            ),
        });
        await expectEvent.inTransaction(tx.tx, app, "SubscriptionDataBefore", {
            publisher: alice,
            indexId: DEFAULT_INDEX_ID,
            approved: false,
            units,
            pendingDistribution: "0",
        });
        await expectEvent.notEmitted.inTransaction(
            tx.tx,
            app,
            "SubscriptionDataAfter"
        );
    });

    it("#1.7 claim callbacks", async () => {
        await t.upgradeBalance("alice", INIT_BALANCE);
        await t.transferBalance("alice", "app", INIT_BALANCE);

        const units = toWad("0.005");
        const distributionAmount = toWad(1);
        await shouldUpdateSubscription({
            testenv: t,
            superToken,
            publisherName: "app",
            indexId: DEFAULT_INDEX_ID,
            subscriberName: "alice",
            units,
            fn: async () => {
                console.log("app.updateSubscription alice");
                return await app.updateSubscription(alice, units);
            },
        });
        await shouldDistribute({
            testenv: t,
            superToken,
            publisherName: "app",
            indexId: DEFAULT_INDEX_ID,
            amount: distributionAmount,
            fn: async () => {
                console.log("app.distribute");
                return await app.distribute(distributionAmount);
            },
        });
        const tx = await shouldClaimPendingDistribution({
            testenv: t,
            superToken,
            publisherName: "app",
            indexId: DEFAULT_INDEX_ID,
            subscriberName: "alice",
            senderName: "dan",
            userData: encodeAbiParameters(
                ["bytes32", "bytes4", "bytes"],
                [sha3("updated"), idaSelector("claim"), "0x"]
            ),
        });
        await expectEvent.inTransaction(tx.tx, app, "SubscriptionDataBefore", {
            publisher: app.address,
            indexId: DEFAULT_INDEX_ID,
            approved: false,
            units,
            pendingDistribution: distributionAmount,
        });
        await expectEvent.inTransaction(tx.tx, app, "SubscriptionDataAfter", {
            publisher: app.address,
            indexId: DEFAULT_INDEX_ID,
            approved: false,
            units,
            pendingDistribution: "0",
        });
    });

    it("#1.8 getSubscriptionByID revert with IDA_SUBSCRIPTION_DOES_NOT_EXIST", async () => {
        await app.setForceGetSubscriptionByID();
        await expectCustomError(
            t.agreementHelper.callAgreement({
                agreementAddress: ida.address,
                callData: t.agreementHelper.getIDACallData(
                    "approveSubscription",
                    [superToken.address, app.address, DEFAULT_INDEX_ID, "0x"]
                ),
                userData: encodeAbiParameters(
                    ["bytes32", "bytes4", "bytes"],
                    [sha3("created"), idaSelector("approveSubscription"), "0x"]
                ),
                signer: aliceSigner,
            }),
            ida,
            "IDA_SUBSCRIPTION_DOES_NOT_EXIST"
        );
    });
});
