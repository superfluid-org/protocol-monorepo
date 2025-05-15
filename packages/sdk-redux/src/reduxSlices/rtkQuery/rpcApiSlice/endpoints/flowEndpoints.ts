import {getFramework} from '../../../../sdkReduxConfig';
import {type TransactionInfo} from '../../../argTypes';
import {registerNewTransactionAndReturnQueryFnResult} from '../../../transactionTrackerSlice/registerNewTransaction';
import {type RpcEndpointBuilder} from '../rpcEndpointBuilder';

import {type FlowCreateMutation, type FlowDeleteMutation, type FlowUpdateMutation} from './flowArgs';

export const createFlowEndpoints = (builder: RpcEndpointBuilder) => ({
    flowCreate: builder.mutation<TransactionInfo, FlowCreateMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const senderAddress = arg.senderAddress ? arg.senderAddress : await arg.signer.getAddress();

            const transactionResponse = await superToken
                .createFlow({
                    sender: senderAddress,
                    receiver: arg.receiverAddress,
                    flowRate: arg.flowRateWei,
                    userData: arg.userDataBytes,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: senderAddress,
                dispatch: queryApi.dispatch,
                title: 'Create Stream',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    flowUpdate: builder.mutation<TransactionInfo, FlowUpdateMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);
            const senderAddress = arg.senderAddress ? arg.senderAddress : await arg.signer.getAddress();

            const transactionResponse = await superToken
                .updateFlow({
                    sender: senderAddress,
                    receiver: arg.receiverAddress,
                    flowRate: arg.flowRateWei,
                    userData: arg.userDataBytes,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: senderAddress,
                dispatch: queryApi.dispatch,
                title: 'Update Stream',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    flowDelete: builder.mutation<TransactionInfo, FlowDeleteMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const senderAddress = arg.senderAddress ? arg.senderAddress : await arg.signer.getAddress();

            const transactionResponse = await superToken
                .deleteFlow({
                    sender: senderAddress,
                    receiver: arg.receiverAddress,
                    userData: arg.userDataBytes,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: senderAddress,
                dispatch: queryApi.dispatch,
                title: 'Close Stream',
                extraData: arg.transactionExtraData,
            });
        },
    }),
});
