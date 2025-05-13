import {type ThunkDispatch} from '@reduxjs/toolkit';
import {providers} from 'ethers';

import {initiateNewTransactionTrackingThunk} from './thunks/initiateNewTransactionTrackingThunk';
import {type TransactionTitle} from './transactionTitle';

/**
 * A simpler TransactionResponse type, similar to wagmi's SendTransactionResult,
 */
export type NewTransactionResponse = Flatten<
    Pick<providers.TransactionResponse, 'hash' | 'wait'> & Partial<providers.TransactionResponse>
>;

export interface RegisterNewTransactionArg {
    /**
     * The chain ID transaction is on.
     * WARNING: Don't pass `chainId` off of ether's `TransactionResponse` because it's not set correctly on timely manner.
     */
    chainId: number;
    signerAddress: string;
    transactionResponse: NewTransactionResponse;
    /**
     * For dispatching redux thunks.
     */
    dispatch: ThunkDispatch<any, any, any>;
    /**
     * Any key you want to give the transaction to identify it later.
     */
    title: TransactionTitle;
    /**
     * Any extra data you want to attach to the transaction. Make sure it's serializable!
     */
    extraData: Record<string, unknown> | undefined;
}

/**
 * Transactions have to be registered for them to be tracked inside the redux store and monitored for re-orgs.
 */
export const registerNewTransaction = async (arg: RegisterNewTransactionArg) => {
    const {chainId, signerAddress, transactionResponse, dispatch, title, extraData} = arg;

    dispatch(
        initiateNewTransactionTrackingThunk({
            chainId,
            signerAddress,
            transactionResponse,
            title,
            extraData: extraData ?? {},
        })
    );
};

export const registerNewTransactionAndReturnQueryFnResult = async (arg: RegisterNewTransactionArg) => {
    registerNewTransaction(arg);
    return {
        data: {
            hash: arg.transactionResponse.hash,
            chainId: arg.chainId,
        },
    };
};

// Prefer flattened/spread syntax for IDE-s. Example: `A: { hash: string } vs B: Pick<TransactionResponse, "hash">`. A is the flattened syntax.
type Flatten<T> = {
    [K in keyof T]: T[K];
};
