import {getFramework} from '../../../../sdkReduxConfig';
import {type TransactionInfo} from '../../../argTypes';
import {registerNewTransactionAndReturnQueryFnResult} from '../../../transactionTrackerSlice/registerNewTransaction';
import {type RpcEndpointBuilder} from '../rpcEndpointBuilder';

import {
    IndexCreateMutation,
    IndexDeleteSubscriptionMutation,
    IndexDistributeMutation,
    IndexSubscriptionApproveMutation,
    IndexSubscriptionClaimMutation,
    IndexSubscriptionRevokeMutation,
    IndexUpdateSubscriptionUnitsMutation,
} from './indexArgs';

export const createIndexEndpoints = (builder: RpcEndpointBuilder) => ({
    indexCreate: builder.mutation<TransactionInfo, IndexCreateMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const transactionResponse = await superToken
                .createIndex({
                    indexId: arg.indexId,
                    userData: arg.userDataBytes,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Create Index',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    indexDistribute: builder.mutation<TransactionInfo, IndexDistributeMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const transactionResponse = await superToken
                .distribute({
                    indexId: arg.indexId,
                    userData: arg.userDataBytes,
                    amount: arg.amountWei,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Distribute Index',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    indexUpdateSubscriptionUnits: builder.mutation<TransactionInfo, IndexUpdateSubscriptionUnitsMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const transactionResponse = await superToken
                .updateSubscriptionUnits({
                    indexId: arg.indexId,
                    subscriber: arg.subscriberAddress,
                    units: arg.unitsNumber,
                    userData: arg.userDataBytes,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Update Index Subscription Units',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    indexSubscriptionApprove: builder.mutation<TransactionInfo, IndexSubscriptionApproveMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const transactionResponse = await superToken
                .approveSubscription({
                    indexId: arg.indexId,
                    publisher: arg.publisherAddress,
                    userData: arg.userDataBytes,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Approve Index Subscription',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    indexSubscriptionClaim: builder.mutation<TransactionInfo, IndexSubscriptionClaimMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const transactionResponse = await superToken
                .claim({
                    indexId: arg.indexId,
                    publisher: arg.publisherAddress,
                    subscriber: arg.subscriberAddress,
                    userData: arg.userDataBytes,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Claim from Index Subscription',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    indexDeleteSubscription: builder.mutation<TransactionInfo, IndexDeleteSubscriptionMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const transactionResponse = await superToken
                .deleteSubscription({
                    indexId: arg.indexId,
                    publisher: arg.publisherAddress,
                    subscriber: arg.subscriberAddress,
                    userData: arg.userDataBytes,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Delete Index Subscription',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    indexSubscriptionRevoke: builder.mutation<TransactionInfo, IndexSubscriptionRevokeMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const transactionResponse = await superToken
                .revokeSubscription({
                    indexId: arg.indexId,
                    publisher: arg.publisherAddress,
                    userData: arg.userDataBytes,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Revoke Index Subscription',
                extraData: arg.transactionExtraData,
            });
        },
    }),
});
