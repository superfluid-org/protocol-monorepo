import {NativeAssetSuperToken, WrapperSuperToken} from '@superfluid-finance/sdk-core';

import {getFramework} from '../../../../sdkReduxConfig';
import {type TransactionInfo} from '../../../argTypes';
import {registerNewTransactionAndReturnQueryFnResult} from '../../../transactionTrackerSlice/registerNewTransaction';
import {createGeneralTags, createSpecificTags} from '../../cacheTags/CacheTagTypes';
import {type RpcEndpointBuilder} from '../rpcEndpointBuilder';

import {
    type SuperTokenDowngradeMutation,
    type SuperTokenTransferMutation,
    type SuperTokenUpgradeAllowanceQuery,
    type SuperTokenUpgradeMutation,
} from './superTokenArgs';

export const createSuperTokenEndpoints = (builder: RpcEndpointBuilder) => ({
    superTokenUpgrade: builder.mutation<TransactionInfo, SuperTokenUpgradeMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const canUpgradeTokenType =
                superToken instanceof WrapperSuperToken || superToken instanceof NativeAssetSuperToken;
            if (!canUpgradeTokenType) {
                throw new Error('Only WrapperSuperToken or NativeAssetSuperToken can be upgraded.');
            }

            const transactionResponse = await superToken
                .upgrade({
                    amount: arg.amountWei,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Upgrade to Super Token',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    superTokenUpgradeAllowance: builder.query<string, SuperTokenUpgradeAllowanceQuery>({
        queryFn: async (arg) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            // TODO(KK): "!"
            return {
                data: await superToken.underlyingToken!.allowance({
                    providerOrSigner: framework.settings.provider,
                    owner: arg.accountAddress,
                    spender: superToken.address,
                }),
            };
        },
        providesTags: (_result, _error, arg) => [
            ...createGeneralTags({chainId: arg.chainId}),
            ...createSpecificTags({
                chainId: arg.chainId,
                address1: arg.superTokenAddress,
                address2: arg.accountAddress,
            }),
        ],
    }),
    superTokenDowngrade: builder.mutation<TransactionInfo, SuperTokenDowngradeMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const canDowngradeTokenType =
                superToken instanceof WrapperSuperToken || superToken instanceof NativeAssetSuperToken;
            if (!canDowngradeTokenType) {
                throw new Error('Only WrapperSuperToken or NativeAssetSuperToken can be downgraded.');
            }

            const transactionResponse = await superToken
                .downgrade({
                    amount: arg.amountWei,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Downgrade from Super Token',
                extraData: arg.transactionExtraData,
            });
        },
    }),
    superTokenTransfer: builder.mutation<TransactionInfo, SuperTokenTransferMutation>({
        queryFn: async (arg, queryApi) => {
            const framework = await getFramework(arg.chainId);
            const superToken = await framework.loadSuperToken(arg.superTokenAddress);

            const transactionResponse = await superToken
                .transfer({
                    amount: arg.amountWei,
                    receiver: arg.receiverAddress,
                    overrides: arg.overrides,
                })
                .exec(arg.signer);

            return await registerNewTransactionAndReturnQueryFnResult({
                transactionResponse,
                chainId: arg.chainId,
                signerAddress: await arg.signer.getAddress(),
                dispatch: queryApi.dispatch,
                title: 'Transfer Super Token',
                extraData: arg.transactionExtraData,
            });
        },
    }),
});
