import {type CreateApi} from '@reduxjs/toolkit/query';
import {type Framework} from '@superfluid-finance/sdk-core';

import {type ModuleName} from './reduxSlices/rtkQuery/ModuleName';
import {createRpcApiSlice} from './reduxSlices/rtkQuery/rpcApiSlice/rpcApiSlice';
import {createSubgraphApiSlice} from './reduxSlices/rtkQuery/subgraphApiSlice/subgraphApiSlice';
import {createTransactionTrackerSlice} from './reduxSlices/transactionTrackerSlice/transactionTrackerSlice';
import {getConfig} from './sdkReduxConfig';

/**
 * For initializing "rpcApiSlice" Redux slice.
 *
 * @param createApi Pass in either {@see createApiWithReactHooks} or {@see createApiWithoutReactHooks}.
 * You can wrap the function with your own function to add even more configuration to the RTK-Query API (e.g. "redux-persist" support).
 */
export const initializeRpcApiSlice = <T extends ModuleName>(createApi: CreateApi<T>) => {
    const rpcApiSlice = createRpcApiSlice(createApi);
    getConfig().setRpcApiSlice(rpcApiSlice as any);
    return rpcApiSlice;
};

/**
 * For initializing "subgraphApiSlice" Redux slice.
 *
 * @param createApi Pass in either {@see createApiWithReactHooks} or {@see createApiWithoutReactHooks}.
 * You can wrap the function with your own function to add even more configuration to the RTK-Query API (e.g. "redux-persist" support).
 */
export const initializeSubgraphApiSlice = <T extends ModuleName>(createApi: CreateApi<T>) => {
    const subgraphApiSlice = createSubgraphApiSlice(createApi);
    getConfig().setSubgraphApiSlice(subgraphApiSlice as any);
    return subgraphApiSlice;
};

/**
 * For initializing "sfTransaction" Redux slice.
 */
export const initializeTransactionTrackerSlice = () => {
    const transactiontTrackerSlice = createTransactionTrackerSlice();
    getConfig().setTransactionTrackerSlice(transactiontTrackerSlice);
    return transactiontTrackerSlice;
};

/**
 * SDK-Redux needs to know where to get SDK-Core's Framework for data querying.
 * @param chainId The chain.
 * @param framework The SDK-Framework getter. Can be either Promise or instance.
 */
export const setFrameworkForSdkRedux = (chainId: number, framework: (() => Promise<Framework>) | Framework) =>
    getConfig().setFramework(chainId, framework);
