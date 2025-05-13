import {type DocumentNode} from 'graphql';

import {type BaseQuery, type NothingString} from '../../../argTypes';

export interface CustomSubgraphQuery extends BaseQuery<unknown> {
    document: string | DocumentNode;
    variables?: {
        [key: string]: any;
    };
}

/**
 * Continuously poll for new events to know when to invalidate cache for re-fetching of the data.
 */
export interface MonitorForEventsToInvalidateCacheMutation {
    /** The chain to poll. */
    chainId: number;
    /** The address (account or token) to filter events for. */
    address: string | NothingString;
}
