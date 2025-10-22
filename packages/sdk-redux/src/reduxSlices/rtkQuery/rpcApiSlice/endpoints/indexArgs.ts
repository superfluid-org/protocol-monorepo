import {type BaseSuperTokenMutation, type NothingString} from '../../../argTypes';

/**
 * Creates an IDA Index.
 */
export interface IndexCreateMutation extends BaseSuperTokenMutation {
    /** The id of the index. */
    indexId: string;
    /** Extra user data provided. */
    userDataBytes: string | NothingString;
}

/**
 * Updates the `units` allocated to a Subscription.
 */
export interface IndexUpdateSubscriptionUnitsMutation extends BaseSuperTokenMutation {
    /** The subscriber address whose units you want to update. */
    subscriberAddress: string;
    /** The id of the index. */
    indexId: string;
    /** The amount of units you want to update to. */
    unitsNumber: string;
    /** Extra user data provided. */
    userDataBytes: string | NothingString;
}

/**
 * Deletes a Subscription by setting the `units` allocated to the Subscriber to 0.
 */
export interface IndexDeleteSubscriptionMutation extends BaseSuperTokenMutation {
    /** The id of the index. */
    indexId: string;
    /** The subscriber address whose subscription you want to delete. */
    publisherAddress: string;
    /** The publisher address of the index you are targeting. */
    subscriberAddress: string;
    /** Extra user data provided. */
    userDataBytes: string | NothingString;
}

/**
 * Distributes `amount` of token to an index
 */
export interface IndexDistributeMutation extends BaseSuperTokenMutation {
    /** The id of the index. */
    indexId: string;
    /** The amount of tokens to be distributed. */
    amountWei: string;
    /** Extra user data provided. */
    userDataBytes: string | NothingString;
}

/**
 * Approves a Subscription, so the Subscriber won't need to claim tokens when the Publisher distributes.
 */
export interface IndexSubscriptionApproveMutation extends BaseSuperTokenMutation {
    indexId: string;
    publisherAddress: string;
    userDataBytes: string | NothingString;
}

/**
 * Revokes a Subscription, so the Subscriber will need to claim tokens when the Publisher distributes.
 */
export interface IndexSubscriptionRevokeMutation extends BaseSuperTokenMutation {
    /** The id of the index. */
    indexId: string;
    /** The index publisher address you want to revoke for the subscriber. */
    publisherAddress: string;
    /** Extra user data provided. */
    userDataBytes: string | NothingString;
}

/**
 * Claims any pending tokens allocated to the Subscription (unapproved).
 */
export interface IndexSubscriptionClaimMutation extends BaseSuperTokenMutation {
    indexId: string;
    publisherAddress: string;
    subscriberAddress: string;
    userDataBytes: string | NothingString;
}
