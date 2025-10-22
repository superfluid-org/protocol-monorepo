import {ethers} from 'ethers';

import {type TransactionTitle} from './transactionTitle';

export type TransactionStatus = 'Pending' | 'Succeeded' | 'Failed' | 'Replaced' | 'Unknown';

// "Redux" stuff needs to be serializable. Blockchain transaction object is unserializable.
export interface TrackedTransaction {
    id: string;
    chainId: number;
    hash: string;
    /**
     * The address this transaction is from.
     */
    signerAddress: string;
    /**
     * Milliseconds since epoch when started tracking the transaction.
     */
    timestampMs: number;
    status: TransactionStatus;
    transactionResponse?: string;
    transactionReceipt?: string;
    ethersErrorCode?: ethers.errors;
    ethersErrorMessage?: string;
    title: TransactionTitle;
    extraData: Record<string, unknown>;
    /**
     * `true` when Subgraph polling was successful, i.e. Subgraph has indexed the transaction. Will be `undefined` if the polling was unsuccessful or we don't know whether it's in sync or not.
     */
    isSubgraphInSync?: true;
    /**
     * The block number where transaction succeeded. Useful for creating polling mechanisms outside of the SDK. For example, another Subgraph API slize.
     */
    blockTransactionSucceededIn?: number;
}
