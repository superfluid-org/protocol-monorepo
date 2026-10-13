import {expect} from "chai";
import {assert} from "chai";
import {BigNumber, BigNumberish} from "ethers";
import _ from "lodash";

import {SuperToken} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {max, min, toBN} from "../utils/helpers";

import {FlowInfo, FlowParams, RealtimeBalance} from "./Agreement.types";

const INIT_FLOW_INFO = {
    flowRate: toBN(0),
    deposit: toBN(0),
    owedDeposit: toBN(0),
    timestamp: toBN(0),
};

/**
 * @dev CFA Data Model which contains the relevant CFA state,
 * updater functions and also validation functions.
 *
 */
export default class CFADataModel {
    readonly testenv: TestEnvironment;
    readonly superToken: SuperToken;
    readonly roles: {[role: string]: string};
    readonly _balanceSnapshotsBefore: {[role: string]: RealtimeBalance};
    readonly _accountFlowInfoBefore: {[flowName: string]: FlowInfo};
    readonly _accountFlowInfoAfter: {[flowName: string]: FlowInfo};
    readonly _balancesBefore: {[role: string]: RealtimeBalance};
    readonly _balancesAfter: {[role: string]: RealtimeBalance};
    readonly flows: {
        [role: string]: {
            flowInfoBefore: FlowInfo;
            flowInfoAfter: FlowInfo;
            flowId: {
                superToken: string;
                sender: string;
                receiver: string;
            };
            notTouched?: boolean;
        };
    };
    readonly expectedFlowInfo: {[flowName: string]: FlowInfo};
    readonly expectedNetFlowDeltas: {[address: string]: BigNumber};

    constructor(testenv: TestEnvironment, superToken: SuperToken) {
        this.testenv = testenv;
        this.superToken = superToken;
        this.roles = {};
        this._balanceSnapshotsBefore = {};
        this._accountFlowInfoBefore = {};
        this._accountFlowInfoAfter = {};
        this._balancesBefore = {};
        this._balancesAfter = {};
        this.flows = {};
        this.expectedFlowInfo = {};
        this.expectedNetFlowDeltas = {};
    }

    /** CFADataModel Class Data Specific Updaters */
    addRole(role: string, alias: string) {
        this.roles[role] = this.testenv.getAddress(alias);
        console.log(`${role} account address ${this.roles[role]} (${alias})`);
    }

    toRole(address: string) {
        return Object.values(this.roles).find((i) => i === address) || "";
    }

    addToBalanceSnapshotsBefore(role: string) {
        this._balanceSnapshotsBefore[this.roles[role]] =
            this.testenv.getAccountBalanceSnapshot(
                this.superToken.address,
                this.roles[role]
            );
        this.testenv.printRealtimeBalance(
            `${role} balance snapshot before`,
            this.getBalanceSnapshotsBefore(role)
        );
    }
    getBalanceSnapshotsBefore(role: string) {
        return this._balanceSnapshotsBefore[this.roles[role]];
    }

    addAccountFlowInfoBefore(role: string) {
        this._accountFlowInfoBefore[this.roles[role]] = this.getAccountFlowInfo(
            {
                superToken: this.superToken.address,
                account: this.roles[role],
            }
        );
        CFADataModel._printFlowInfo(
            `${role} account flow info snapshot before`,
            this.getAccountFlowInfoBefore(role)
        );
    }
    getAccountFlowInfoBefore(role: string) {
        return this._accountFlowInfoBefore[this.roles[role]];
    }

    async addAccountFlowInfoAfter(role: string) {
        const accountFlowInfo =
            await this.testenv.contracts.cfa.getAccountFlowInfo(
                this.superToken.address,
                this.roles[role]
            );
        this._accountFlowInfoAfter[this.roles[role]] = accountFlowInfo;
        CFADataModel._printFlowInfo(
            `${role} account flow info after`,
            this.getAccountFlowInfoAfter(role)
        );
    }
    getAccountFlowInfoAfter(role: string) {
        return this._accountFlowInfoAfter[this.roles[role]];
    }

    async addToBalancesBefore(role: string) {
        this._balancesBefore[this.roles[role]] =
            await this.superToken.realtimeBalanceOfNow(this.roles[role]);
        this.testenv.printRealtimeBalance(
            `${role} balance before`,
            this.getBalancesBefore(role)
        );
    }
    getBalancesBefore(role: string) {
        return this._balancesBefore[this.roles[role]];
    }

    async addToBalancesAfter(role: string) {
        this._balancesAfter[this.roles[role]] =
            await this.superToken.realtimeBalanceOfNow(this.roles[role]);
        this.testenv.printRealtimeBalance(
            `${role} balance after`,
            this.getBalancesAfter(role)
        );
    }
    getBalancesAfter(role: string) {
        return this._balancesAfter[this.roles[role]];
    }

    async addFlowInfoBefore(flowName: string, flowParams: FlowParams) {
        const flowId = {
            superToken: this.superToken.address,
            sender: flowParams.sender,
            receiver: flowParams.receiver,
        };
        const flowInfo: FlowInfo = await this.testenv.contracts.cfa.getFlow(
            flowId.superToken,
            flowId.sender,
            flowId.receiver
        );
        this.flows[flowName] = {
            flowId,
            notTouched: flowParams.notTouched, // only used in MFA test case
            flowInfoBefore: flowInfo,
            flowInfoAfter: INIT_FLOW_INFO,
        };
        CFADataModel._printFlowInfo(`${flowName} flow info before`, flowInfo);
    }
    async addFlowInfoAfter(flowName: string) {
        const flowData = this.flows[flowName];
        const {flowId} = flowData;
        const flowInfo = await this.testenv.contracts.cfa.getFlow(
            flowId.superToken,
            flowId.sender,
            flowId.receiver
        );
        CFADataModel._printFlowInfo(`${flowName} flow info after`, flowInfo);
        flowData.flowInfoAfter = flowInfo;
    }

    // function to validate single flow info change
    validateFlowInfoChange(flowName: string, txnTimestamp: number) {
        console.log(`validating ${flowName} flow change...`);
        const flowData = this.flows[flowName];

        if (!flowData.notTouched) {
            // validate flow info
            if (flowData.flowInfoAfter.flowRate.toString() !== "0") {
                console.log(flowData.flowInfoAfter);
                console.log(txnTimestamp);
                expect(
                    flowData.flowInfoAfter.timestamp,
                    `wrong flow timestamp of the ${flowName} flow`
                ).to.equal(toBN(txnTimestamp));
            } else {
                expect(flowData.flowInfoAfter.timestamp).to.equal(toBN(0));
            }
            expect(
                flowData.flowInfoAfter.flowRate,
                `wrong flow rate of the ${flowName} flow`
            ).to.equal(this.expectedFlowInfo[flowName].flowRate);

            expect(
                flowData.flowInfoAfter.owedDeposit,
                `wrong owed deposit amount of the ${flowName} flow`
            ).to.equal(this.expectedFlowInfo[flowName].owedDeposit);

            expect(
                flowData.flowInfoAfter.deposit,
                `wrong deposit amount of the ${flowName} flow`
            ).to.equal(this.expectedFlowInfo[flowName].deposit);
        } else {
            expect(
                flowData.flowInfoAfter.flowRate,
                `flow rate of the ${flowName} flow should not change`
            ).to.equal(flowData.flowInfoBefore.flowRate);

            expect(
                flowData.flowInfoAfter.owedDeposit,
                `owed deposit amount of the ${flowName} flow should not change`
            ).to.equal(flowData.flowInfoBefore.owedDeposit);

            expect(
                flowData.flowInfoAfter.deposit,
                `deposit amount of the ${flowName} flow should not change`
            ).to.equal(flowData.flowInfoBefore.deposit);
        }
    }

    // function to validate overall account flow info change
    validateAccountFlowInfoChange(role: string) {
        console.log(`validating ${role} account deposit changes...`);

        const inFlowNames = Object.keys(this.flows).filter(
            (i) => this.flows[i].flowId.receiver === this.roles[role]
        );
        const outFlowNames = Object.keys(this.flows).filter(
            (i) => this.flows[i].flowId.sender === this.roles[role]
        );
        console.log("in flows", inFlowNames);
        console.log("out flows", outFlowNames);

        let expectedDepositDelta = toBN(0);
        let expectedOwedDepositDelta = toBN(0);

        inFlowNames.forEach((flowName) => {
            const flowData = this.flows[flowName];
            expectedOwedDepositDelta = expectedOwedDepositDelta
                .add(toBN(flowData.flowInfoAfter.owedDeposit))
                .sub(toBN(flowData.flowInfoBefore.owedDeposit));
        });
        outFlowNames.forEach((flowName) => {
            const flowData = this.flows[flowName];
            expectedDepositDelta = expectedDepositDelta
                .add(toBN(flowData.flowInfoAfter.deposit))
                .sub(toBN(flowData.flowInfoBefore.deposit));
        });

        const flowRateDelta = toBN(
            this.getAccountFlowInfoAfter(role).flowRate
        ).sub(toBN(this.getAccountFlowInfoBefore(role).flowRate));
        assert.equal(
            flowRateDelta.toString(),
            this.expectedNetFlowDeltas[this.roles[role]].toString(),
            `wrong netflow delta of ${role}`
        );

        const depositDelta = toBN(
            this.getBalancesAfter(role).deposit.toString()
        ).sub(toBN(this.getBalancesBefore(role).deposit.toString()));
        assert.equal(
            depositDelta.toString(),
            expectedDepositDelta.toString(),
            `wrong deposit delta amount of ${role}`
        );

        const owedDepositDelta = toBN(
            this.getBalancesAfter(role).owedDeposit.toString()
        ).sub(toBN(this.getBalancesBefore(role).owedDeposit.toString()));
        assert.equal(
            owedDepositDelta.toString(),
            expectedOwedDepositDelta.toString(),
            `wrong owed deposit delta amount of ${role}`
        );
    }

    /** TestEnvironment Data Specific Updaters */
    //
    // Account flow info test data operations
    //
    updateAccountFlowInfo({
        superToken,
        account,
        flowInfo,
    }: {
        superToken: string;
        account: string;
        flowInfo: FlowInfo;
    }) {
        _.merge(this.testenv.data, {
            tokens: {
                [superToken]: {
                    accounts: {
                        [account]: {
                            cfa: {
                                flowInfo: {
                                    timestamp: flowInfo.timestamp,
                                    flowRate: flowInfo.flowRate,
                                    deposit: flowInfo.deposit,
                                    owedDeposit: flowInfo.owedDeposit,
                                },
                            },
                        },
                    },
                },
            },
        });
    }
    getAccountFlowInfo({
        superToken,
        account,
    }: {
        superToken: string;
        account: string;
    }) {
        _.defaultsDeep(this.testenv.data, {
            tokens: {
                [superToken]: {
                    accounts: {
                        [account]: {
                            cfa: {
                                flowInfo: {
                                    timestamp: toBN(0),
                                    flowRate: toBN(0),
                                    deposit: toBN(0),
                                    owedDeposit: toBN(0),
                                },
                            },
                        },
                    },
                },
            },
        });
        return _.clone(
            this.testenv.data.tokens[superToken].accounts[account].cfa.flowInfo
        );
    }
    //
    // Flow info test data operations
    //
    updateFlowInfo({
        superToken,
        sender,
        receiver,
        flowInfo,
    }: {
        superToken: string;
        sender: string;
        receiver: string;
        flowInfo: FlowInfo;
    }) {
        _.merge(this.testenv.data, {
            tokens: {
                [superToken]: {
                    cfa: {
                        flows: {
                            [`${sender}:${receiver}`]: {
                                sender,
                                receiver,
                                timestamp: flowInfo.timestamp,
                                flowRate: flowInfo.flowRate,
                                deposit: flowInfo.deposit,
                                owedDeposit: flowInfo.owedDeposit,
                            },
                        },
                    },
                },
            },
        });
    }

    getFlowInfo({
        superToken,
        sender,
        receiver,
    }: {
        superToken: string;
        sender: string;
        receiver: string;
    }) {
        _.defaultsDeep(this.testenv.data, {
            tokens: {
                [superToken]: {
                    cfa: {
                        flows: {
                            [`${sender}:${receiver}`]: {
                                sender,
                                receiver,
                                timestamp: toBN(0),
                                flowRate: toBN(0),
                                deposit: toBN(0),
                                owedDeposit: toBN(0),
                            },
                        },
                    },
                },
            },
        });
        return _.clone(
            this.testenv.data.tokens[superToken].cfa.flows[
                `${sender}:${receiver}`
            ]
        );
    }

    validateAccountNetFlow({
        superToken,
        account,
    }: {
        superToken: string;
        account: string;
    }) {
        const alias = this.testenv.toAlias(account);
        console.log(`validating ${alias} account net flow ...`);

        // ${sender}:${receiver} => flowInfo
        const flows = this.testenv.data.tokens[superToken].cfa.flows;

        const inFlows = Object.keys(flows)
            .filter((i) => i.endsWith(`:${account}`))
            .map((i) => flows[i]);
        const outFlows = Object.keys(flows)
            .filter((i) => i.startsWith(`${account}:`))
            .map((i) => flows[i]);
        console.log(
            "in flows",
            inFlows.map((i) => this.testenv.toAlias(i.sender))
        );
        console.log(
            "out flows",
            outFlows.map((i) => this.testenv.toAlias(i.receiver))
        );

        let actualNetFlow = toBN(0);

        inFlows.forEach((flowInfo) => {
            actualNetFlow = actualNetFlow.add(toBN(flowInfo.flowRate));
        });
        outFlows.forEach((flowInfo) => {
            actualNetFlow = actualNetFlow.sub(toBN(flowInfo.flowRate));
        });

        const accountFlowInfo = this.getAccountFlowInfo({
            superToken,
            account,
        });

        assert.equal(
            accountFlowInfo.flowRate.toString(),
            actualNetFlow.toString(),
            `unexpected netflow of ${alias}`
        );
    }

    syncAccountExpectedBalanceDeltas({
        superToken,
        timestamp,
    }: {
        superToken: string;
        timestamp: BigNumberish;
    }) {
        console.log(
            "syncing accounting expected balance deltas due to flows..."
        );

        this.testenv.listAddresses().forEach((account: string) => {
            const accountFlowInfo = this.getAccountFlowInfo({
                superToken,
                account,
            });
            const balanceSnapshot = this.testenv.getAccountBalanceSnapshot(
                superToken,
                account
            );
            const expectedBalanceDelta1 =
                this.testenv.getAccountExpectedBalanceDelta(
                    superToken,
                    account
                );
            const expectedBalanceDelta2 = expectedBalanceDelta1.add(
                toBN(accountFlowInfo.flowRate.toString()).mul(
                    toBN(timestamp.toString()).sub(
                        toBN(balanceSnapshot.timestamp.toString())
                    )
                )
            );
            this.testenv.updateAccountExpectedBalanceDelta(
                superToken,
                account,
                expectedBalanceDelta2
            );
        });
    }

    /** Static Functions */
    static _printFlowInfo(title: string, flowInfo: FlowInfo) {
        console.log(
            title,
            flowInfo.timestamp.toString(),
            flowInfo.flowRate.toString(),
            flowInfo.deposit.toString(),
            flowInfo.owedDeposit.toString()
        );
    }
    static clipDepositNumber(deposit: BigNumber, roundingDown = false) {
        // last 32 bites of the deposit (96 bites) is clipped off
        const rounding = roundingDown
            ? 0
            : deposit.and(toBN(0xffffffff)).isZero()
              ? 0
              : 1;
        return deposit.shr(32).add(rounding).shl(32);
    }

    getDeposit(flowRate: BigNumber, liquidationPeriod: BigNumber) {
        const deposit = CFADataModel.clipDepositNumber(
            flowRate.mul(liquidationPeriod)
        );
        return deposit.lt(this.testenv.configs.MINIMUM_DEPOSIT) &&
            toBN(flowRate).gt(toBN(0))
            ? this.testenv.configs.MINIMUM_DEPOSIT
            : deposit;
    }

    static adjustNewAppCreditUsed(
        appCreditGranted: BigNumber,
        appCreditUsed: BigNumber
    ) {
        // [appCreditUsed...appCreditGranted];
        return max(toBN(0), min(appCreditGranted, appCreditUsed));
    }
}
