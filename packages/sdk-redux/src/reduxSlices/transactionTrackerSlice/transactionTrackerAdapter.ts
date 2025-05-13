import {createEntityAdapter} from '@reduxjs/toolkit';

import {type TrackedTransaction} from './trackedTransaction';
import {type TransactionTrackerReducer, transactionTrackerSlicePrefix} from './transactionTrackerSlice';

export const transactionTrackerAdapter = createEntityAdapter<TrackedTransaction>({
    sortComparer: (a) => a.timestampMs,
});

export const transactionTrackerSelectors = transactionTrackerAdapter.getSelectors<{
    [transactionTrackerSlicePrefix]: TransactionTrackerReducer;
}>((state) => state[transactionTrackerSlicePrefix]);
