import type { Framework } from './Framework';
import type BN from 'bn.js';
import type { Transaction } from 'web3-core';
import type { FlowInfo, FlowList } from './ConstantFlowAgreementV1Helper';
import type { SubscriptionData } from './InstantDistributionAgreementV1Helper';

// params options types
export interface UserOptions {
    sf: Framework;
    address: string;
    token: string;
}

// specified User to avoid confusion with CFA CreateFlowOptions
export interface UserFlowOptions {
    recipient: string;
    flowRate: string;
    userData?: string;
    onTransaction?: ()=>any;
    by?: string;
}


export interface UserDetails {
    cfa: {
        flows: FlowList
        netFlow: string // numeric string
    }
    ida: {
        subscriptions: Array<SubscriptionData>;
    }
}

export declare class User {
    constructor({ sf, address, token }: UserOptions);
    sf: Framework;
    address: string;
    token: string;
    details(): Promise<UserDetails>;
    flow({
        recipient,
        flowRate,
        ...options
    }: UserFlowOptions): Promise<Transaction | undefined>;
}
