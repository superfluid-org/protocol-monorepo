import {createAsyncThunk} from '@reduxjs/toolkit';
import {ethers} from 'ethers';

import {getTransactionTrackerSlice} from '../../../sdkReduxConfig';
import {type NewTransactionResponse} from '../registerNewTransaction';
import {type TransactionTitle} from '../transactionTitle';
import {transactionTrackerSlicePrefix} from '../transactionTrackerSlice';
import {trySerializeTransaction} from '../trySerializeTransaction';

import {trackPendingTransactionThunk} from './trackPendingTransactionThunk';

/**
 * Used for tracking _brand new_ transactions.
 */
export const initiateNewTransactionTrackingThunk = createAsyncThunk<
    void,
    {
        chainId: number;
        // NOTE: Using simpler type that TransactionResponse which is not returned when the TX is sent "unchecked".
        transactionResponse: NewTransactionResponse;
        signerAddress: string;
        title: TransactionTitle;
        extraData: Record<string, unknown>;
    }
>(`${transactionTrackerSlicePrefix}/initiateNewTransactionTracking`, async (arg, {dispatch}) => {
    arg.transactionResponse.chainId = arg.chainId; // Recommended by Ethers to specify Chain ID when doing serialization.

    const transactionHash = arg.transactionResponse.hash;

    dispatch(
        getTransactionTrackerSlice().actions.addTransaction({
            id: transactionHash,
            chainId: arg.chainId,
            hash: transactionHash,
            signerAddress: ethers.utils.getAddress(arg.signerAddress),
            timestampMs: new Date().getTime(),
            status: 'Pending',
            transactionResponse: trySerializeTransaction(arg.transactionResponse),
            title: arg.title,
            extraData: arg.extraData,
        })
    );

    dispatch(trackPendingTransactionThunk({transactionHash, chainId: arg.chainId, wait: arg.transactionResponse.wait}));
});
