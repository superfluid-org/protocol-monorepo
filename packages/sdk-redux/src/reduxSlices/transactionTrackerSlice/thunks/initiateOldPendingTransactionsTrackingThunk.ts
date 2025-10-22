import {createAsyncThunk} from '@reduxjs/toolkit';
import {ethers} from 'ethers';

import {transactionTrackerSelectors} from '../transactionTrackerAdapter';
import {type TransactionTrackerReducer, transactionTrackerSlicePrefix} from '../transactionTrackerSlice';

import {trackPendingTransactionThunk} from './trackPendingTransactionThunk';

/**
 * Use this if you want your application to pick up tracking of old pending transactions.
 */
export const initiateOldPendingTransactionsTrackingThunk = createAsyncThunk<
    void,
    {
        signerAddress: string;
        chainIds: number[];
    }
>(`${transactionTrackerSlicePrefix}/initiateOldPendingTransactionsTracking`, async (arg, {getState, dispatch}) => {
    const signerAddress = ethers.utils.getAddress(arg.signerAddress);
    const state = getState() as {[transactionTrackerSlicePrefix]: TransactionTrackerReducer};

    const transactions = transactionTrackerSelectors
        .selectAll(state)
        .filter((x) => x.signerAddress === signerAddress && arg.chainIds.includes(x.chainId) && x.status === 'Pending');

    transactions.forEach((x) => dispatch(trackPendingTransactionThunk({chainId: x.chainId, transactionHash: x.hash})));
});
