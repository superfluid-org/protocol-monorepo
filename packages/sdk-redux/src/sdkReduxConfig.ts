import {type Framework} from '@superfluid-finance/sdk-core';
import {type Signer} from 'ethers';
import memoize from 'lodash.memoize';

// NOTE: This file is marked for side-effects inside the package.json for efficient tree-shaking.

import {type RpcApiSliceEmpty} from './reduxSlices/rtkQuery/rpcApiSlice/rpcApiSlice';
import {type SubgraphApiSliceEmpty} from './reduxSlices/rtkQuery/subgraphApiSlice/subgraphApiSlice';
import {type TransactionTrackerSlice} from './reduxSlices/transactionTrackerSlice/transactionTrackerSlice';

interface FrameworkLocator {
    getFramework: (chainId: number) => Promise<Framework>;
    setFramework: (chainId: number, frameworkOrFactory: Framework | (() => Promise<Framework>)) => void;
}

interface RpcApiSliceLocator {
    getRpcApiSlice: () => RpcApiSliceEmpty;
    setRpcApiSlice: (api: RpcApiSliceEmpty) => void;
}

interface SubgraphApiSliceLocator {
    getSubgraphApiSlice: () => SubgraphApiSliceEmpty;
    setSubgraphApiSlice: (api: SubgraphApiSliceEmpty) => void;
}

interface TransactionTrackerSliceLocator {
    getTransactionTrackerSlice: () => TransactionTrackerSlice;
    setTransactionTrackerSlice: (slice: TransactionTrackerSlice) => void;
}

/**
 * NOTE: The reason memoization is used is to avoid multiple instantiations by the factory functions.
 */
export default class SdkReduxConfig
    implements FrameworkLocator, RpcApiSliceLocator, SubgraphApiSliceLocator, TransactionTrackerSliceLocator
{
    rpcApiSlice: RpcApiSliceEmpty | undefined;
    subgraphApiSlice: SubgraphApiSliceEmpty | undefined;
    transactionTrackerSlice: TransactionTrackerSlice | undefined;
    memoizedFrameworkFactories = new Map<number, () => Promise<Framework>>();
    memoizedSignerFactories = new Map<number, () => Promise<Signer>>();

    static getOrCreateSingleton(): SdkReduxConfig {
        if (!globalThis.sdkReduxConfig) {
            globalThis.sdkReduxConfig = new SdkReduxConfig();
        }
        return globalThis.sdkReduxConfig;
    }

    getRpcApiSlice(): RpcApiSliceEmpty {
        if (!this.rpcApiSlice) {
            throw Error('The RpcApiSlice has not been set. Are you sure you initialized SDK-Redux properly?');
        }
        return this.rpcApiSlice;
    }

    getSubgraphApiSlice(): SubgraphApiSliceEmpty {
        if (!this.subgraphApiSlice) {
            throw Error('The SubgraphApiSlice has not been set. Are you sure you initialized SDK-Redux properly?');
        }
        return this.subgraphApiSlice;
    }

    getFramework(chainId: number): Promise<Framework> {
        const frameworkFactory = this.memoizedFrameworkFactories.get(chainId);
        if (!frameworkFactory)
            throw Error(
                `Don't know how to get Superfluid Framework. :( Please set up a *framework* source for chain [${chainId}].`
            );
        return frameworkFactory();
    }

    getTransactionTrackerSlice(): TransactionTrackerSlice {
        if (!this.transactionTrackerSlice) {
            throw Error(
                'The TransactionTrackerSlice has not been set. Are you sure you initialized SDK-Redux properly?'
            );
        }
        return this.transactionTrackerSlice;
    }

    setRpcApiSlice(slice: RpcApiSliceEmpty): void {
        if (this.rpcApiSlice) {
            console.log(
                "Warning! RpcApiSlice was already set and will be overriden. This shouldn't be happening in production."
            );
        }
        this.rpcApiSlice = slice;
    }

    setSubgraphApiSlice(slice: SubgraphApiSliceEmpty): void {
        if (this.subgraphApiSlice) {
            console.log(
                "Warning! SubgraphApiSlice was already set and will be overriden. This shouldn't be happening in production."
            );
        }
        this.subgraphApiSlice = slice;
    }

    setFramework(chainId: number, instanceOrFactory: Framework | (() => Promise<Framework>)) {
        const frameworkFactory = isFramework(instanceOrFactory)
            ? () => Promise.resolve(instanceOrFactory)
            : instanceOrFactory;

        this.memoizedFrameworkFactories.set(chainId, memoize(frameworkFactory));
    }

    setTransactionTrackerSlice(slice: TransactionTrackerSlice): void {
        if (this.transactionTrackerSlice) {
            console.log(
                "Warning! TransactionTrackerSlice was already set and will be overriden. This shouldn't be happening in production."
            );
        }
        this.transactionTrackerSlice = slice;
    }
}

export const getConfig = SdkReduxConfig.getOrCreateSingleton;
export const getRpcApiSlice = () => getConfig().getRpcApiSlice();
export const getSubgraphApiSlice = () => getConfig().getSubgraphApiSlice();
export const getTransactionTrackerSlice = () => getConfig().getTransactionTrackerSlice();
export const getFramework = (chainId: number) => getConfig().getFramework(chainId);
export const getSubgraphClient = (chainId: number) =>
    getConfig()
        .getFramework(chainId)
        .then((x) => x.query.subgraphClient);

const isFramework = (value: any): value is Framework => !!value.cfaV1;
