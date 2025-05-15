import {createSlice} from '@reduxjs/toolkit';

import {transactionTrackerAdapter} from './transactionTrackerAdapter';

export const transactionTrackerSlicePrefix = 'superfluid_transactions' as const;

export const createTransactionTrackerSlice = () => ({
    ...createSlice({
        name: transactionTrackerSlicePrefix,
        initialState: transactionTrackerAdapter.getInitialState(),
        reducers: {
            addTransaction: transactionTrackerAdapter.addOne,
            updateTransaction: transactionTrackerAdapter.updateOne,
        },
    }),
    reducerPath: transactionTrackerSlicePrefix,
});

export type TransactionTrackerSlice = ReturnType<typeof createTransactionTrackerSlice>;
export type TransactionTrackerReducer = ReturnType<TransactionTrackerSlice['getInitialState']>;
