import {type SerializedError} from '@reduxjs/toolkit';
import {type BaseQueryFn} from '@reduxjs/toolkit/query';

export const rpcBaseQuery = (): BaseQueryFn<void, unknown, SerializedError, Record<string, unknown>> => () => {
    throw new Error('All queries & mutations must use the `queryFn` definition syntax.');
};

export type RpcBaseQuery = ReturnType<typeof rpcBaseQuery>;
