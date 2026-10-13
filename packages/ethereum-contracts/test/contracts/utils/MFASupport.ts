import {BigNumber} from "ethers";
import {assert} from "chai";
import {SuperToken} from "../../../typechain-types";
import {toBN} from "./helpers";
import CFADataModel from "../agreements/ConstantFlowAgreementV1.data";
import TestEnvironment from "../../TestEnvironment";
import {encodeAbiParameter, encodeAbiParameters} from "../utils/helpers";

export interface MFAParams {
    ratioPct: number;
    sender: string;
    receivers: {
        [receiver: string]: {proportion: number};
    };
}

interface BaseMFAParams {
    testenv: TestEnvironment;
    mfa: MFAParams;
}

interface UpdateFlowExpectationsParams extends BaseMFAParams {
    superToken: SuperToken;
    flowRate: BigNumber;
    cfaDataModel: CFADataModel;
}
export default class MFASupport {
    static async setup({
        testenv,
        mfa,
        roles,
    }: BaseMFAParams & {
        roles: {[role: string]: string};
    }) {
        roles.mfaSender = testenv.getAddress(mfa.sender);
        roles.mfa = testenv.getAddress("mfa");

        Object.keys(mfa.receivers).forEach(async (receiverAlias) => {
            const mfaReceiverName = "mfa.receiver." + receiverAlias;
            roles[mfaReceiverName] = testenv.getAddress(receiverAlias);
            console.log(
                `${receiverAlias} account address ${roles[mfaReceiverName]} (${receiverAlias})`
            );
        });

        const receivers = Object.keys(mfa.receivers).filter(
            (i) => mfa.receivers[i].proportion > 0
        );
        return {
            userData: encodeAbiParameters(
                ["address", "uint256", "address[]", "uint256[]"],
                [
                    testenv.getAddress(mfa.sender),
                    mfa.ratioPct,
                    receivers.map((i) => testenv.getAddress(i)),
                    receivers.map((i) => mfa.receivers[i].proportion),
                ]
            ),
        };
    }

    static async updateFlowExpectations({
        testenv,
        superToken,
        mfa,
        flowRate,
        cfaDataModel,
    }: UpdateFlowExpectationsParams) {
        const roles = cfaDataModel.roles;
        let expectedNetFlowDeltas = cfaDataModel.expectedNetFlowDeltas;
        const expectedFlowInfo = cfaDataModel.expectedFlowInfo;
        let totalProportions = Object.values(mfa.receivers)
            .map((i) => i.proportion)
            .reduce((acc, cur) => acc + cur, 0);

        const depositAllowance = CFADataModel.clipDepositNumber(
            toBN(flowRate).mul(toBN(testenv.configs.LIQUIDATION_PERIOD)),
            true /* rounding down */
        );

        // expected unwinding of mfa receiver flows
        Object.keys(mfa.receivers).forEach((receiverAlias) => {
            const receiverAddress = testenv.getAddress(receiverAlias);
            if (!(receiverAddress in expectedNetFlowDeltas)) {
                expectedNetFlowDeltas[receiverAddress] = toBN(0);
            }
        });
        await Promise.all(
            Object.keys(mfa.receivers).map(async (receiverAlias) => {
                const mfaReceiverName = "mfa.receiver." + receiverAlias;
                const mfaFlowName = "mfa.flow." + receiverAlias;
                const receiverAddress = testenv.getAddress(receiverAlias);
                const notTouched =
                    mfa.receivers[receiverAlias].proportion === 0;

                // skip if it's been deleted by one of the mfa receivers
                if (receiverAddress == roles.receiver) return;

                await cfaDataModel.addFlowInfoBefore(mfaFlowName, {
                    sender: roles.mfa,
                    receiver: roles[mfaReceiverName],
                    notTouched,
                });

                const originalMfaFlowDepositAllowance =
                    CFADataModel.clipDepositNumber(
                        toBN(depositAllowance)
                            .mul(toBN(mfa.receivers[receiverAlias].proportion))
                            .mul(toBN(mfa.ratioPct))
                            .div(100)
                            .div(toBN(totalProportions)),
                        true /* rounding down */
                    );
                const mfaFlowDepositAllowance =
                    originalMfaFlowDepositAllowance.lt(
                        testenv.configs.MINIMUM_DEPOSIT
                    ) && toBN(flowRate).gt(toBN(0))
                        ? testenv.configs.MINIMUM_DEPOSIT
                        : originalMfaFlowDepositAllowance;

                const mfaFlowRate = toBN(originalMfaFlowDepositAllowance).div(
                    toBN(testenv.configs.LIQUIDATION_PERIOD)
                );

                if (!notTouched) {
                    const mfaFlowRateDelta = toBN(mfaFlowRate).sub(
                        toBN(
                            cfaDataModel.getAccountFlowInfoBefore(
                                mfaReceiverName
                            ).flowRate
                        )
                    );
                    expectedNetFlowDeltas[receiverAddress] =
                        expectedNetFlowDeltas[receiverAddress].add(
                            mfaFlowRateDelta
                        );
                    expectedNetFlowDeltas[roles.mfa] =
                        expectedNetFlowDeltas[roles.mfa].sub(mfaFlowRateDelta);
                }

                expectedFlowInfo[mfaFlowName] = {
                    flowRate: mfaFlowRate,
                    deposit: mfaFlowDepositAllowance,
                    owedDeposit: toBN(0),
                    timestamp: toBN(0),
                };
            })
        );

        // expected unwinding of mfa sender flow if the flow being deleted is not sending to the mfa
        if (roles.mfa != roles.receiver) {
            const mfaSenderFlow = cfaDataModel.getFlowInfo({
                superToken: superToken.address,
                sender: roles.mfaSender,
                receiver: roles.mfa,
            });
            if (!(roles.mfaSender in expectedNetFlowDeltas))
                expectedNetFlowDeltas[roles.mfaSender] = toBN(0);
            if (!(roles.mfa in expectedNetFlowDeltas))
                expectedNetFlowDeltas[roles.mfa] = toBN(0);
            expectedNetFlowDeltas[roles.mfaSender] = expectedNetFlowDeltas[
                roles.mfaSender
            ].add(toBN(mfaSenderFlow.flowRate));
            expectedNetFlowDeltas[roles.mfa] = expectedNetFlowDeltas[
                roles.mfa
            ].sub(toBN(mfaSenderFlow.flowRate));
            await cfaDataModel.addFlowInfoBefore("mfa.sender", {
                sender: roles.mfaSender,
                receiver: roles.mfa,
            });
            expectedFlowInfo["mfa.sender"] = {
                flowRate: toBN(0),
                deposit: toBN(0),
                owedDeposit: toBN(0),
                timestamp: toBN(0),
            };
        }
    }

    static async postCheck({
        testenv,
        roles,
    }: {
        testenv: TestEnvironment;
        roles: {[role: string]: string};
    }) {
        assert.isFalse(
            await testenv.contracts.superfluid.isAppJailed(roles.mfa),
            "MFA app was jailed"
        );
    }
}
