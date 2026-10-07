import {assert} from "chai";
import {BigNumberish} from "ethers";
import {ethers} from "hardhat";

import {
    ConstantFlowAgreementV1,
    MultiFlowTesterApp,
    SuperfluidMock,
    SuperTokenMock,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectCustomError} from "../../utils/expectRevert";
import MFASupport from "../utils/MFASupport";
import {encodeAbiParameters, toBN, toWad} from "../utils/helpers";

import {VerifyOptions} from "./Agreement.types";
import AgreementHelper, {
    FLOW_TYPE_CREATE,
    FLOW_TYPE_DELETE,
} from "./AgreementHelper";
import {
    expectNetFlow,
    shouldCreateFlow,
    shouldDeleteFlow,
    shouldUpdateFlow,
} from "./ConstantFlowAgreementV1.behavior";
import CFADataModel from "./ConstantFlowAgreementV1.data";

describe("CFAv1 | Multi Flow Super App Tests", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();
    let agreementHelper: AgreementHelper;

    const {LIQUIDATION_PERIOD, FLOW_RATE1, MINIMUM_DEPOSIT} = t.configs;

    let bob: string, dan: string;
    let superfluid: SuperfluidMock;
    let cfa: ConstantFlowAgreementV1;
    let superToken: SuperTokenMock;

    before(async () => {
        await t.beforeTestSuite({
            nAccounts: 5,
        });
        ({bob, dan} = t.aliases);

        ({superfluid, cfa} = t.contracts);
        superToken = t.tokens.SuperToken;
        agreementHelper = t.agreementHelper;
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(() => {
        t.afterEachTestCaseBenchmark();
        if (t.plotData.enabled) {
            t.writePlotDataIntoCSVFile(
                (this.ctx as any).test.title
                    .split("#")[1]
                    .split('"')[0]
                    .split(" ")
                    .join("_"),
                superToken.address
            );
        }
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

    async function timeTravelOnceAndVerifyAll(opts?: VerifyOptions) {
        await t.timeTravelOnce(opts?.time);
        await verifyAll(opts);
    }

    async function expectJailed(appAddress: string, reasonCode: number) {
        assert.isTrue(await t.contracts.superfluid.isAppJailed(appAddress));
        const eventsFilter = superfluid.filters.Jail(appAddress);
        const events = await superfluid.queryFilter(eventsFilter, 0, "latest");
        assert.equal(events.length, 1);
        assert.equal(events[0].args.reason.toString(), reasonCode.toString());
    }

    const sender = "alice";
    const receiver1 = "bob";
    const receiver2 = "carol";
    const lowFlowRate = FLOW_RATE1.mul(toBN(9)).div(toBN(10));
    const highFlowRate = FLOW_RATE1.mul(toBN(11)).div(toBN(10));
    let app: MultiFlowTesterApp;

    beforeEach(async () => {
        const mfaFactory =
            await ethers.getContractFactory("MultiFlowTesterApp");
        app = await mfaFactory.deploy(cfa.address, superfluid.address);
        t.addAlias("mfa", app.address);
    });

    // due to clipping of flow rate, mfa outgoing flow rate is always equal or less
    // then the sender's rate
    function mfaFlowRate(flowRate: BigNumberish, pct = 100) {
        return CFADataModel.clipDepositNumber(
            toBN(flowRate).mul(toBN(LIQUIDATION_PERIOD)).mul(pct).div(100),
            true
        ).div(toBN(LIQUIDATION_PERIOD));
    }

    it("#1.1 1to1_100pct_create-full_updates-full_delete", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE);

        const mfa = {
            ratioPct: 100,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(FLOW_RATE1),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: lowFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(lowFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: lowFlowRate.sub(mfaFlowRate(lowFlowRate)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(lowFlowRate),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: highFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(highFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: highFlowRate.sub(mfaFlowRate(highFlowRate)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(highFlowRate),
        });
        await timeTravelOnceAndVerifyAll();

        // fully delete everything
        await shouldDeleteFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            by: sender,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await timeTravelOnceAndVerifyAll();
    });

    it("#1.2 1to0_create-updates-delete", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE);

        const mfa = {
            ratioPct: 0,
            sender,
            receivers: {},
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1,
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: lowFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(lowFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: lowFlowRate,
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: highFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(highFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: highFlowRate,
        });
        await timeTravelOnceAndVerifyAll();

        // fully delete everything
        await shouldDeleteFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            by: sender,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: "0",
        });
        await timeTravelOnceAndVerifyAll();
    });

    it("#1.3 1to2[50,50]_100pct_create-full_updates-full_delete", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE);

        const mfa = {
            ratioPct: 100,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1, 50).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: lowFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(lowFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: lowFlowRate.sub(mfaFlowRate(lowFlowRate, 50).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(lowFlowRate, 50),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(lowFlowRate, 50),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: highFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(highFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: highFlowRate.sub(mfaFlowRate(highFlowRate, 50).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(highFlowRate, 50),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(highFlowRate, 50),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldDeleteFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            by: sender,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: "0",
        });
        await timeTravelOnceAndVerifyAll();
    });

    it("#1.4 1to2[50,50]_50pct_create-full_updates-full_delete", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE);

        const mfa = {
            ratioPct: 50,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1, 25).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(FLOW_RATE1, 25),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 25),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: lowFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(lowFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: lowFlowRate.sub(mfaFlowRate(lowFlowRate, 25).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(lowFlowRate, 25),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(lowFlowRate, 25),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: highFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(highFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: highFlowRate.sub(mfaFlowRate(highFlowRate, 25).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(highFlowRate, 25),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(highFlowRate, 25),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldDeleteFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            by: sender,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: "0",
        });
        await timeTravelOnceAndVerifyAll();
    });

    it("#1.5 1to2[50,50]_150pct_create-full_updates-full_delete", async () => {
        // double the amount since it's a "bigger" flow
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE.mul(2));
        await t.transferBalance(sender, "mfa", toWad(50));

        const mfa = {
            ratioPct: 150,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1, 75).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(FLOW_RATE1, 75),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 75),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: lowFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(lowFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: lowFlowRate.sub(mfaFlowRate(lowFlowRate, 75).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(lowFlowRate, 75),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(lowFlowRate, 75),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldUpdateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: highFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(highFlowRate),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: highFlowRate.sub(mfaFlowRate(highFlowRate, 75).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(highFlowRate, 75),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(highFlowRate, 75),
        });
        await timeTravelOnceAndVerifyAll();

        await shouldDeleteFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            by: sender,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: "0",
        });
        await timeTravelOnceAndVerifyAll();
    });

    it("#1.6 1to1-?pct_create-should-fail-without-extra-funds", async () => {
        // @note - the ratio pct is dependent on the additional app credit amount
        // in proportion to the flow deposit hence the ?pct
        const deposit = CFADataModel.clipDepositNumber(
            FLOW_RATE1.mul(LIQUIDATION_PERIOD)
        );
        // calculate what percentage minimum deposit is of the deposit
        const minDepositToDepositRatio =
            Number(MINIMUM_DEPOSIT.toString()) / Number(deposit.toString());
        const ratioPercentage = minDepositToDepositRatio * 100;
        console.log("MIN DEP / DEP RATIO:", ratioPercentage);
        // add this percentage to 100 to get the maximum ratiopct allowed
        // given the additional app credit amount then add 1 to make it not work
        const exceededRatioPct = 100 + ratioPercentage + 1;

        let mfa = {
            ratioPct: exceededRatioPct,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
            },
        };

        let {userData} = await MFASupport.setup({
            testenv: t,
            mfa,
            roles: {},
        });
        await expectCustomError(
            agreementHelper.modifyFlow({
                type: FLOW_TYPE_CREATE,
                flowRate: FLOW_RATE1,
                superToken: superToken.address,
                sender: t.aliases[sender],
                receiver: app.address,
                userData,
            }),
            cfa,
            "APP_RULE",
            t.customErrorCode.APP_RULE_NO_CRITICAL_RECEIVER_ACCOUNT
        );

        // original case
        mfa = {
            ...mfa,
            ratioPct: 101,
        };

        ({userData} = await MFASupport.setup({
            testenv: t,
            mfa,
            roles: {},
        }));
        await expectCustomError(
            agreementHelper.modifyFlow({
                type: FLOW_TYPE_CREATE,
                flowRate: FLOW_RATE1,
                superToken: superToken.address,
                sender: t.aliases[sender],
                receiver: app.address,
                userData,
            }),
            cfa,
            "CFA_INSUFFICIENT_BALANCE"
        );

        await timeTravelOnceAndVerifyAll();
    });

    it("#1.7 1to2[50,50]_100pct_create-partial_delete", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE.mul(2));
        await t.transferBalance(sender, "mfa", toWad(50));

        let mfa = {
            ratioPct: 100,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1, 50).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
        await timeTravelOnceAndVerifyAll();

        // delete flow of mfa => receiver 1
        mfa = {
            ratioPct: 100,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 0,
                },
            },
        };
        await shouldDeleteFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            by: sender,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: toBN(0).sub(mfaFlowRate(FLOW_RATE1, 50)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
    });

    it("#1.8 loopback-100pct", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE);

        const mfa = {
            ratioPct: 100,
            sender,
            receivers: {
                [sender]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: mfaFlowRate(FLOW_RATE1).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1)),
        });
        await timeTravelOnceAndVerifyAll();

        // shouldDeleteFlow doesn't support loopback mode for now, let's use the sf directly
        console.log("delete the mfa loopback flow");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_DELETE,
            superToken: superToken.address,
            sender: t.getAddress(sender),
            receiver: app.address,
            userData: encodeAbiParameters(
                ["address", "uint256", "address[]", "uint256[]"],
                [
                    t.getAddress(sender),
                    mfa.ratioPct,
                    [t.getAddress(sender)],
                    [1],
                ]
            ),
        });
        await t.validateSystemInvariance();
        assert.isFalse(await t.contracts.superfluid.isAppJailed(app.address));
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: "0",
        });
    });

    it("#1.9 1to2[50,50]_100pct_create_full_delete_by_receiver", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE);

        const mfa = {
            ratioPct: 100,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1, 50).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
        await timeTravelOnceAndVerifyAll();

        // fully delete everything by receiver1
        await shouldDeleteFlow({
            testenv: t,
            superToken,
            sender: "mfa",
            receiver: receiver1,
            by: receiver1,
            mfa,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: "0",
        });
        await timeTravelOnceAndVerifyAll();
    });

    it("#1.10 1to1_100pct_create_full_delete_mfa_sender_flow_by_liquidator", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE);

        const mfa = {
            ratioPct: 100,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1, 50).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });

        await expectCustomError(
            agreementHelper.modifyFlow({
                type: FLOW_TYPE_DELETE,
                superToken: superToken.address,
                sender: t.aliases[sender],
                receiver: app.address,
                signer: await ethers.getSigner(t.aliases[dan]),
            }),
            cfa,
            "CFA_NON_CRITICAL_SENDER"
        );

        const accountFlowInfo = await cfa.getAccountFlowInfo(
            superToken.address,
            t.aliases[sender]
        );
        await timeTravelOnceAndVerifyAll({
            time: t.configs.INIT_BALANCE.div(FLOW_RATE1)
                .sub(LIQUIDATION_PERIOD)
                .add(toBN(60)),
            allowCriticalAccount: true,
        });

        await shouldDeleteFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            by: "dan",
            mfa,
            accountFlowInfo,
        });
        assert.isFalse(await superfluid.isAppJailed(app.address));
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: "0",
        });
        await timeTravelOnceAndVerifyAll();
        t.writePlotDataIntoCSVFile(
            (this.ctx as any).test.title.split(" ").join("_"),
            superToken.address
        );
    });

    it("#1.11 1to1_150pct_create_full_delete_mfa_receiver_flow_by_liquidator", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE.mul(2));
        t.initializePlotData(true); // observing all accounts
        await t.transferBalance(sender, "mfa", toWad(50));

        const mfa = {
            ratioPct: 150,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        const mfaNetFlowRate = FLOW_RATE1.sub(
            mfaFlowRate(FLOW_RATE1, 75).mul(2)
        );
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: mfaNetFlowRate,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(FLOW_RATE1, 75),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 75),
        });

        await expectCustomError(
            agreementHelper.modifyFlow({
                type: FLOW_TYPE_DELETE,
                superToken: superToken.address,
                sender: app.address,
                receiver: t.getAddress(receiver1),
                signer: await ethers.getSigner(t.aliases[dan]),
            }),
            cfa,
            "CFA_NON_CRITICAL_SENDER"
        );

        // @note - need to consider new additional app credit rule CFA-2
        // it takes additional time to drain the account due to the
        // additional app credit amount/minimum deposit
        const minDepTime = MINIMUM_DEPOSIT.div(mfaNetFlowRate);
        await timeTravelOnceAndVerifyAll({
            time: toWad(50)
                .div(mfaNetFlowRate)
                .sub(LIQUIDATION_PERIOD)
                .add(minDepTime.mul(toBN(-1)))
                .add(toBN(60))
                .mul(toBN(-1)),
            allowCriticalAccount: true,
        });

        const danSigner = await ethers.getSigner(dan);

        console.log("liquidate the mfa receiver1 flow");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_DELETE,
            superToken: superToken.address,
            sender: app.address,
            receiver: t.getAddress(receiver1),
            signer: danSigner,
        });
        await expectJailed(
            app.address,
            t.customErrorCode.APP_RULE_NO_CRITICAL_SENDER_ACCOUNT
        );
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1, 75)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 75),
        });

        // try to rescue the app, but it's already in jail
        await t.transferBalance(sender, "mfa", toWad(10));
        assert.isTrue((await superToken.balanceOf(app.address)).gt(toBN(0)));

        console.log("liquidate the mfa receiver2 flow");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_DELETE,
            superToken: superToken.address,
            sender: app.address,
            receiver: t.getAddress(receiver2),
            signer: danSigner,
        });
        await expectJailed(
            app.address,
            t.customErrorCode.APP_RULE_NO_CRITICAL_SENDER_ACCOUNT
        );
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: "0",
        });

        console.log("liquidate the mfa sender flow");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_DELETE,
            superToken: superToken.address,
            sender: t.getAddress(sender),
            receiver: app.address,
            signer: danSigner,
        });
        await expectJailed(
            app.address,
            t.customErrorCode.APP_RULE_NO_CRITICAL_SENDER_ACCOUNT
        );
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: "0",
        });
        await t.validateSystemInvariance();
        t.writePlotDataIntoCSVFile(
            (this.ctx as any).test.title.split(" ").join("_"),
            superToken.address
        );
    });

    it("#1.12 1to2[50,50]_100pct_create-partial_delete-negative_app_balance", async () => {
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE);

        const mfa = {
            ratioPct: 100,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 1,
                },
            },
        };

        await shouldCreateFlow({
            testenv: t,
            superToken,
            sender,
            receiver: "mfa",
            mfa,
            flowRate: FLOW_RATE1,
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: toBN(0).sub(FLOW_RATE1),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: FLOW_RATE1.sub(mfaFlowRate(FLOW_RATE1, 50).mul(2)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });

        // delete flow of receiver 1
        console.log("delete the mfa flows partially");
        await agreementHelper.modifyFlow({
            type: FLOW_TYPE_DELETE,
            superToken: superToken.address,
            sender: t.getAddress(sender),
            receiver: app.address,
            userData: encodeAbiParameters(
                ["address", "uint256", "address[]", "uint256[]"],
                [
                    t.getAddress(sender),
                    mfa.ratioPct,
                    [t.getAddress(receiver1)],
                    [1],
                ]
            ),
        });
        await expectJailed(
            app.address,
            t.customErrorCode.APP_RULE_NO_CRITICAL_RECEIVER_ACCOUNT
        );
        await t.validateSystemInvariance();
        await expectNetFlow({
            testenv: t,
            superToken,
            account: sender,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: "mfa",
            value: toBN(0).sub(mfaFlowRate(FLOW_RATE1, 50)),
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver1,
            value: "0",
        });
        await expectNetFlow({
            testenv: t,
            superToken,
            account: receiver2,
            value: mfaFlowRate(FLOW_RATE1, 50),
        });
    });

    it("#1.20 createFlow via app action should respect deposit rule", async () => {
        await expectCustomError(
            agreementHelper.callAppAction({
                appAddress: app.address,
                callData: agreementHelper.cfaInterface.encodeFunctionData(
                    "createFlow",
                    [superToken.address, bob, FLOW_RATE1.toString(), "0x"]
                ),
                signer: await ethers.getSigner(t.accounts[0]),
            }),
            cfa,
            "CFA_INSUFFICIENT_BALANCE"
        );
    });

    it("#1.21 1to2[50,50]_150pct_create-full should fail without app balance", async () => {
        // double the amount since it's a "bigger" flow
        await t.upgradeBalance(sender, t.configs.INIT_BALANCE);

        const mfa = {
            ratioPct: 150,
            sender,
            receivers: {
                [receiver1]: {
                    proportion: 1,
                },
                [receiver2]: {
                    proportion: 1,
                },
            },
        };

        const {userData} = await MFASupport.setup({
            testenv: t,
            mfa,
            roles: {},
        });

        await expectCustomError(
            agreementHelper.modifyFlow({
                type: FLOW_TYPE_CREATE,
                superToken: superToken.address,
                sender: t.aliases[sender],
                receiver: app.address,
                flowRate: FLOW_RATE1,
                userData,
            }),
            cfa,
            "APP_RULE",
            t.customErrorCode.APP_RULE_NO_CRITICAL_RECEIVER_ACCOUNT
        );
    });
});
