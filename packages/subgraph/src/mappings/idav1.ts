import { BigInt } from "@graphprotocol/graph-ts";
import {
    IndexCreated,
    IndexDistributionClaimed,
    IndexSubscribed,
    IndexUnitsUpdated,
    IndexUnsubscribed,
    IndexUpdated,
    SubscriptionApproved,
    SubscriptionDistributionClaimed,
    SubscriptionRevoked,
    SubscriptionUnitsUpdated,
} from "../../generated/InstantDistributionAgreementV1/IInstantDistributionAgreementV1";
import {
    IndexCreatedEvent,
    IndexDistributionClaimedEvent,
    IndexSubscribedEvent,
    IndexUnitsUpdatedEvent,
    IndexUnsubscribedEvent,
    IndexUpdatedEvent,
    SubscriptionApprovedEvent,
    SubscriptionDistributionClaimedEvent,
    SubscriptionRevokedEvent,
    SubscriptionUnitsUpdatedEvent,
} from "../../generated/schema";
import {
    BIG_INT_ZERO,
    createEventID,
    getIndexID,
    initializeEventEntity,
    subscriptionWithUnitsExists,
    tokenHasValidHost,
} from "../utils";
import {
    _createAccountTokenSnapshotLogEntity,
    _createTokenStatisticLogEntity,
    getOrInitIndex,
    getOrInitSubscription,
    getOrInitTokenStatistic,
    updateAggregateDistributionAgreementData,
    updateATSStreamedAndBalanceUntilUpdatedAt,
    updateTokenStatsStreamedUntilUpdatedAt,
} from "../mappingHelpers";
import { getHostAddress } from "../addresses";

/******************
 * Event Handlers *
 *****************/
export function handleIndexCreated(event: IndexCreated): void {
    const eventName = "IndexCreated";
    const hostAddress = getHostAddress();
    const hasValidHost = tokenHasValidHost(hostAddress, event.params.token);
    if (!hasValidHost) {
        return;
    }

    const indexCreatedId = createEventID(eventName, event);
    const index = getOrInitIndex(
        event,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        indexCreatedId,
        eventName
    );
    index.save();

    // update streamed until updated at field
    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);

    const tokenStatistic = getOrInitTokenStatistic(
        event.params.token,
        event.block
    );
    tokenStatistic.totalNumberOfIndexes =
        tokenStatistic.totalNumberOfIndexes + 1;

    tokenStatistic.save();

    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.publisher,
        event.params.token,
        event.block,
        BigInt.fromI32(0) // will do RPC if any units exist anyways (balance isn't impacted by index creation)
    );

    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.publisher,
        event.params.token,
        eventName
    );
    _createTokenStatisticLogEntity(event, event.params.token, eventName);
    _createIndexCreatedEventEntity(event, eventName, index.id);
}

export function handleIndexDistributionClaimed(
    event: IndexDistributionClaimed
): void {
    const eventName = "IndexDistributionClaimed";
    const indexId = getIndexID(
        event.params.publisher,
        event.params.token,
        event.params.indexId
    );
    _createIndexDistributionClaimedEventEntity(event, eventName, indexId);
}

export function handleIndexUpdated(event: IndexUpdated): void {
    const eventName = "IndexUpdated";
    const hostAddress = getHostAddress();
    const hasValidHost = tokenHasValidHost(hostAddress, event.params.token);
    if (!hasValidHost) {
        return;
    }

    const totalUnits = event.params.totalUnitsPending.plus(
        event.params.totalUnitsApproved
    );
    const distributionDelta = event.params.newIndexValue
        .minus(event.params.oldIndexValue)
        .times(totalUnits);

    // update Index entity
    const index = getOrInitIndex(
        event,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        "",
        eventName
    );
    const previousTotalAmountDistributed =
        index.totalAmountDistributedUntilUpdatedAt;
    index.indexValue = event.params.newIndexValue;
    index.totalUnitsPending = event.params.totalUnitsPending;
    index.totalUnitsApproved = event.params.totalUnitsApproved;
    index.totalUnits = totalUnits;
    index.totalAmountDistributedUntilUpdatedAt =
        previousTotalAmountDistributed.plus(distributionDelta);
    index.save();

    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);

    const tokenStatistic = getOrInitTokenStatistic(
        event.params.token,
        event.block
    );

    // Note: only increment active index the first time distribution occurs.
    if (previousTotalAmountDistributed.equals(BIG_INT_ZERO)) {
        tokenStatistic.totalNumberOfActiveIndexes =
            tokenStatistic.totalNumberOfActiveIndexes + 1;
    }

    tokenStatistic.totalAmountDistributedUntilUpdatedAt =
        tokenStatistic.totalAmountDistributedUntilUpdatedAt.plus(
            distributionDelta
        );
    tokenStatistic.updatedAtTimestamp = event.block.timestamp;
    tokenStatistic.updatedAtBlockNumber = event.block.number;
    tokenStatistic.save();

    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.publisher,
        event.params.token,
        event.block,
        null // will do RPC if any units exist anyways
    );
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.publisher,
        event.params.token,
        eventName
    );
    _createTokenStatisticLogEntity(event, event.params.token, eventName);
    _createIndexUpdatedEventEntity(event, eventName, index.id);
}

export function handleIndexSubscribed(event: IndexSubscribed): void {
    const eventName = "IndexSubscribed";
    const indexId = getIndexID(
        event.params.publisher,
        event.params.token,
        event.params.indexId
    );
    _createIndexSubscribedEventEntity(event, eventName, indexId);
}

export function handleIndexUnitsUpdated(event: IndexUnitsUpdated): void {
    const eventName = "IndexUnitsUpdated";
    const indexId = getIndexID(
        event.params.publisher,
        event.params.token,
        event.params.indexId
    );
    const subscription = getOrInitSubscription(
        event,
        event.params.subscriber,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        eventName
    );
    _createIndexUnitsUpdatedEventEntity(
        event,
        eventName,
        indexId,
        subscription.units
    );
}

export function handleIndexUnsubscribed(event: IndexUnsubscribed): void {
    const eventName = "IndexUnsubscribed";
    const indexId = getIndexID(
        event.params.publisher,
        event.params.token,
        event.params.indexId
    );
    _createIndexUnsubscribedEventEntity(event, eventName, indexId);
}

export function handleSubscriptionApproved(event: SubscriptionApproved): void {
    const eventName = "SubscriptionApproved";
    const hostAddress = getHostAddress();
    const hasValidHost = tokenHasValidHost(hostAddress, event.params.token);
    if (!hasValidHost) {
        return;
    }

    const index = getOrInitIndex(
        event,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        "",
        eventName
    );

    const subscription = getOrInitSubscription(
        event,
        event.params.subscriber,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        eventName
    );

    const balanceDelta = index.indexValue
        .minus(subscription.indexValueUntilUpdatedAt)
        .times(subscription.units);

    subscription.approved = true;
    subscription.indexValueUntilUpdatedAt = index.indexValue;

    const hasSubscriptionWithUnits = subscriptionWithUnitsExists(
        subscription.id
    );

    // this must be done whether subscription exists or not
    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.subscriber,
        event.params.token,
        event.block,
        balanceDelta
    );

    if (hasSubscriptionWithUnits) {
        index.totalUnitsApproved = index.totalUnitsApproved.plus(
            subscription.units
        );
        index.totalUnitsPending = index.totalUnitsPending.minus(
            subscription.units
        );

        subscription.totalAmountReceivedUntilUpdatedAt =
            subscription.totalAmountReceivedUntilUpdatedAt.plus(balanceDelta);

        updateATSStreamedAndBalanceUntilUpdatedAt(
            event.params.publisher,
            event.params.token,
            event.block,
            BigInt.fromI32(0)
        );
        _createAccountTokenSnapshotLogEntity(
            event,
            event.params.publisher,
            event.params.token,
            eventName
        );
    }

    subscription.save();

    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);

    // we only want to increment approved here ALWAYS
    updateAggregateDistributionAgreementData(
        event.params.subscriber,
        event.params.token,
        hasSubscriptionWithUnits || subscription.approved,
        subscription.approved,
        false, // don't increment subWithUnits
        false, // not revoking
        false, // not deleting (setting units to 0)
        true, // approving subscription here
        event.block,
        true // isIDA
    );
    index.save();

    _createSubscriptionApprovedEventEntity(event, eventName, subscription.id);
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.subscriber,
        event.params.token,
        eventName
    );
    _createTokenStatisticLogEntity(event, event.params.token, eventName);
}

export function handleSubscriptionDistributionClaimed(
    event: SubscriptionDistributionClaimed
): void {
    const eventName = "SubscriptionDistributionClaimed";
    const index = getOrInitIndex(
        event,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        "",
        eventName
    );

    const subscription = getOrInitSubscription(
        event,
        event.params.subscriber,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        eventName
    );

    const pendingDistribution = subscription.units.times(
        index.indexValue.minus(subscription.indexValueUntilUpdatedAt)
    );

    subscription.totalAmountReceivedUntilUpdatedAt =
        subscription.totalAmountReceivedUntilUpdatedAt.plus(
            pendingDistribution
        );
    subscription.indexValueUntilUpdatedAt = index.indexValue;
    subscription.save();

    _createSubscriptionDistributionClaimedEventEntity(
        event,
        eventName,
        subscription.id
    );

    // // update streamed until updated at field
    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);

    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.publisher,
        event.params.token,
        event.block,
        BigInt.fromI32(0)
    );
    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.subscriber,
        event.params.token,
        event.block,
        event.params.amount
    );
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.publisher,
        event.params.token,
        eventName
    );
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.subscriber,
        event.params.token,
        eventName
    );
    _createTokenStatisticLogEntity(event, event.params.token, eventName);
}

/**
 * This function will be triggered in _revokeOrUpdateSubscription
 * as well as updateSubscription, but we only handle
 * _revokeOrUpdateSubscription - it runs whenever a subscription
 * is revoked or deleted.
 * @param event
 */
export function handleSubscriptionRevoked(event: SubscriptionRevoked): void {
    const eventName = "SubscriptionRevoked";
    const hostAddress = getHostAddress();
    const hasValidHost = tokenHasValidHost(hostAddress, event.params.token);
    if (!hasValidHost) {
        return;
    }

    const index = getOrInitIndex(
        event,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        "",
        eventName
    );

    // This will always execute on an existing subscription
    const subscription = getOrInitSubscription(
        event,
        event.params.subscriber,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        eventName
    );

    const balanceDelta = index.indexValue
        .minus(subscription.indexValueUntilUpdatedAt)
        .times(subscription.units);

    // we only shift the balance from approved to pending for approved subscriptions
    // when you delete an approved subscription, we run through this and we clear the
    // totalUnitsPending in handleSubscriptionUnitsUpdated
    // when you delete as an unapproved user, we just subtract subscription units
    // in handleSubscriptionUnitsUpdated
    if (subscription.approved) {
        index.totalUnitsApproved = index.totalUnitsApproved.minus(
            subscription.units
        );
        index.totalUnitsPending = index.totalUnitsPending.plus(
            subscription.units
        );
    }
    subscription.indexValueUntilUpdatedAt = index.indexValue;

    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.subscriber,
        event.params.token,
        event.block,
        balanceDelta
    );

    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);

    updateAggregateDistributionAgreementData(
        event.params.subscriber,
        event.params.token,
        true,
        subscription.approved,
        false, // don't increment subWithUnits
        true, // revoking subscription here
        false, // not deleting
        false, // not approving
        event.block,
        true // isIDA
    );
    // mimic ida logic more closely
    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.publisher,
        event.params.token,
        event.block,
        BigInt.fromI32(0)
    );

    // occurs on revoke or delete
    subscription.totalAmountReceivedUntilUpdatedAt =
        subscription.totalAmountReceivedUntilUpdatedAt.plus(balanceDelta);
    subscription.approved = false;

    index.save();
    subscription.save();

    _createSubscriptionRevokedEventEntity(event, eventName, subscription.id);
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.subscriber,
        event.params.token,
        eventName
    );
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.publisher,
        event.params.token,
        eventName
    );
    _createTokenStatisticLogEntity(event, event.params.token, eventName);
}

/**
 * This function will be triggered in _revokeOrUpdateSubscription
 * as well as updateSubscription, but we only handle
 * updateSubscription.
 * @param event
 */
export function handleSubscriptionUnitsUpdated(
    event: SubscriptionUnitsUpdated
): void {
    const eventName = "SubscriptionUnitsUpdated";
    const hostAddress = getHostAddress();
    const hasValidHost = tokenHasValidHost(hostAddress, event.params.token);
    if (!hasValidHost) {
        return;
    }

    const subscription = getOrInitSubscription(
        event,
        event.params.subscriber,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        eventName
    );

    const index = getOrInitIndex(
        event,
        event.params.publisher,
        event.params.token,
        event.params.indexId,
        "",
        eventName
    );
    const units = event.params.units;
    const oldUnits = subscription.units;
    const hasSubscriptionWithUnits = subscriptionWithUnitsExists(
        subscription.id
    );

    // we only handle updateSubscription in this function
    // is updateSubscription
    const totalUnitsDelta = units.minus(subscription.units);

    // if you have an approved subscription, you just add to totalUnitsApproved
    if (subscription.approved) {
        index.totalUnitsApproved =
            index.totalUnitsApproved.plus(totalUnitsDelta);
        index.totalUnits = index.totalUnits.plus(totalUnitsDelta);
        // else, you just add to the pending units
    } else {
        index.totalUnitsPending = index.totalUnitsPending.plus(totalUnitsDelta);
        index.totalUnits = index.totalUnits.plus(totalUnitsDelta);
    }

    const balanceDelta = index.indexValue
        .minus(subscription.indexValueUntilUpdatedAt)
        .times(subscription.units);

    // token.settleBalance should be the trigger for updating
    // totalAmountReceivedUntilUpdatedAt and calling
    subscription.totalAmountReceivedUntilUpdatedAt =
        subscription.totalAmountReceivedUntilUpdatedAt.plus(balanceDelta);

    // We move both of these in here as we handle this in revoke or delete
    // as well, so if we put it outside it will be a duplicate call
    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.publisher,
        event.params.token,
        event.block,
        BigInt.fromI32(0)
    );
    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.subscriber,
        event.params.token,
        event.block,
        balanceDelta
    );

    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);

    // when units are set to 0, the graph marks this as a deletion
    // and therefore subtracts the number of totalSubscriptionWithUnits and
    // totalApprovedSubscriptions
    if (units.equals(BIG_INT_ZERO)) {
        updateAggregateDistributionAgreementData(
            event.params.subscriber,
            event.params.token,
            hasSubscriptionWithUnits,
            subscription.approved,
            false, // don't increment subWithUnits
            false, // not revoking subscription
            true, // only place we decrement subWithUnits IF subscriber has subWithUnits
            false, // not approving
            event.block,
            true // isIDA
        );
        index.totalSubscriptionsWithUnits = hasSubscriptionWithUnits
            ? index.totalSubscriptionsWithUnits - 1
            : index.totalSubscriptionsWithUnits;
    }

    subscription.indexValueUntilUpdatedAt = index.indexValue;
    subscription.units = event.params.units;

    // to simplify things, we only tally subscriptions in our stats
    // if you have units - the opposite of subscription deletion
    // this only executes when someone is allocated units the first time
    if (units.gt(BIG_INT_ZERO) && oldUnits.equals(BIG_INT_ZERO)) {
        index.totalSubscriptionsWithUnits =
            index.totalSubscriptionsWithUnits + 1;

        updateAggregateDistributionAgreementData(
            event.params.subscriber,
            event.params.token,
            hasSubscriptionWithUnits,
            subscription.approved,
            true, // only place we increment subWithUnits
            false, // not revoking
            false, // not deleting
            false, // not approving
            event.block,
            true // isIDA
        );
    }

    index.save();
    subscription.save();

    _createSubscriptionUnitsUpdatedEventEntity(
        event,
        eventName,
        subscription.id,
        oldUnits
    );
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.publisher,
        event.params.token,
        eventName
    );
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.subscriber,
        event.params.token,
        eventName
    );
    _createTokenStatisticLogEntity(event, event.params.token, eventName);
}

/****************************************
 * Create Event Entity Helper Functions *
 ***************************************/
function _createIndexCreatedEventEntity(
    event: IndexCreated,
    eventName: string,
    indexId: string
): void {
    const eventId = createEventID(eventName, event);
    const ev = new IndexCreatedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
    ]);

    ev.token = event.params.token;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.userData = event.params.userData;
    ev.index = indexId;
    ev.save();
}

function _createIndexDistributionClaimedEventEntity(
    event: IndexDistributionClaimed,
    eventName: string,
    indexId: string
): void {
    const eventId = createEventID(eventName, event);
    const ev = new IndexDistributionClaimedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
        event.params.subscriber,
    ]);

    ev.token = event.params.token;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.subscriber = event.params.subscriber;
    ev.amount = event.params.amount;
    ev.index = indexId;
    ev.save();
}

function _createIndexUpdatedEventEntity(
    event: IndexUpdated,
    eventName: string,
    indexId: string
): void {
    const eventId = createEventID(eventName, event);
    const ev = new IndexUpdatedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
    ]);

    ev.token = event.params.token;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.oldIndexValue = event.params.oldIndexValue;
    ev.newIndexValue = event.params.newIndexValue;
    ev.totalUnitsPending = event.params.totalUnitsPending;
    ev.totalUnitsApproved = event.params.totalUnitsApproved;
    ev.userData = event.params.userData;
    ev.index = indexId;
    ev.save();
}
function _createIndexSubscribedEventEntity(
    event: IndexSubscribed,
    eventName: string,
    indexId: string
): void {
    const eventId = createEventID(eventName, event);
    const ev = new IndexSubscribedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
        event.params.subscriber,
    ]);

    ev.token = event.params.token;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.subscriber = event.params.subscriber;
    ev.userData = event.params.userData;
    ev.index = indexId;
    ev.save();
}

function _createIndexUnitsUpdatedEventEntity(
    event: IndexUnitsUpdated,
    eventName: string,
    indexId: string,
    oldUnits: BigInt
): void {
    const eventId = createEventID(eventName, event);
    const ev = new IndexUnitsUpdatedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
        event.params.subscriber,
    ]);

    ev.token = event.params.token;
    ev.subscriber = event.params.subscriber;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.units = event.params.units;
    ev.userData = event.params.userData;
    ev.oldUnits = oldUnits;
    ev.index = indexId;
    ev.save();
}

function _createIndexUnsubscribedEventEntity(
    event: IndexUnsubscribed,
    eventName: string,
    indexId: string
): void {
    const eventId = createEventID(eventName, event);
    const ev = new IndexUnsubscribedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
        event.params.subscriber,
    ]);

    ev.token = event.params.token;
    ev.subscriber = event.params.subscriber;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.userData = event.params.userData;
    ev.index = indexId;
    ev.save();
}

function _createSubscriptionApprovedEventEntity(
    event: SubscriptionApproved,
    eventName: string,
    subscriptionId: string
): void {
    const eventId = createEventID(eventName, event);
    const ev = new SubscriptionApprovedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
        event.params.subscriber,
    ]);
    ev.token = event.params.token;
    ev.subscriber = event.params.subscriber;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.userData = event.params.userData;
    ev.subscription = subscriptionId;
    ev.save();
}

function _createSubscriptionDistributionClaimedEventEntity(
    event: SubscriptionDistributionClaimed,
    eventName: string,
    subscriptionId: string
): void {
    const eventId = createEventID(eventName, event);
    const ev = new SubscriptionDistributionClaimedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
        event.params.subscriber,
    ]);

    ev.token = event.params.token;
    ev.subscriber = event.params.subscriber;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.amount = event.params.amount;
    ev.subscription = subscriptionId;
    ev.save();
}

function _createSubscriptionRevokedEventEntity(
    event: SubscriptionRevoked,
    eventName: string,
    subscriptionId: string
): void {
    const eventId = createEventID(eventName, event);
    const ev = new SubscriptionRevokedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
        event.params.subscriber,
    ]);

    ev.token = event.params.token;
    ev.subscriber = event.params.subscriber;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.userData = event.params.userData;
    ev.subscription = subscriptionId;
    ev.save();
}

function _createSubscriptionUnitsUpdatedEventEntity(
    event: SubscriptionUnitsUpdated,
    eventName: string,
    subscriptionId: string,
    oldUnits: BigInt
): void {
    const eventId = createEventID(eventName, event);
    const ev = new SubscriptionUnitsUpdatedEvent(eventId);
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.publisher,
        event.params.subscriber,
    ]);

    ev.token = event.params.token;
    ev.subscriber = event.params.subscriber;
    ev.publisher = event.params.publisher;
    ev.indexId = event.params.indexId;
    ev.units = event.params.units;
    ev.userData = event.params.userData;
    ev.subscription = subscriptionId;
    ev.oldUnits = oldUnits;
    ev.save();
}
