import { BigInt } from "@graphprotocol/graph-ts";
import {
    BufferAdjusted,
    FlowDistributionUpdated,
    InstantDistributionUpdated,
    PoolConnectionUpdated,
    PoolCreated,
} from "../../generated/GeneralDistributionAgreementV1/IGeneralDistributionAgreementV1";
import {
    BufferAdjustedEvent,
    FlowDistributionUpdatedEvent,
    InstantDistributionUpdatedEvent,
    PoolConnectionUpdatedEvent,
    PoolCreatedEvent,
} from "../../generated/schema";
import { SuperfluidPool as SuperfluidPoolTemplate } from "../../generated/templates";
import {
    _createAccountTokenSnapshotLogEntity,
    _createTokenStatisticLogEntity,
    getOrInitPool,
    getOrInitPoolDistributor,
    getOrInitOrUpdatePoolMember,
    getOrInitTokenStatistic,
    settlePDPoolMemberMU,
    updateATSStreamedAndBalanceUntilUpdatedAt,
    updateAggregateDistributionAgreementData,
    updatePoolDistributorTotalAmountFlowedAndDistributed,
    updatePoolParticleAndTotalAmountFlowedAndDistributed,
    updateSenderATSStreamData,
    updateTokenStatisticStreamData,
    updateTokenStatsStreamedUntilUpdatedAt,
    getOrInitAccountTokenSnapshot,
} from "../mappingHelpers";
import {
    BIG_INT_ZERO,
    createEventID,
    divideOrZero,
    initializeEventEntity,
    membershipWithUnitsExists,
} from "../utils";

// @note use deltas where applicable

export function handlePoolCreated(event: PoolCreated): void {
    const eventName = "PoolCreated";

    const pool = getOrInitPool(event, event.params.pool.toHex());
    pool.token = event.params.token.toHex();
    pool.admin = event.params.admin.toHex();
    pool.save();

    // Note: this is necessary otherwise we will not be able to capture
    // template data source events.
    SuperfluidPoolTemplate.create(event.params.pool);

    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);

    const tokenStatistic = getOrInitTokenStatistic(
        event.params.token,
        event.block
    );
    tokenStatistic.totalNumberOfPools = tokenStatistic.totalNumberOfPools + 1;
    tokenStatistic.save();

    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.admin,
        event.params.token,
        event.block,
        BigInt.fromI32(0)
    );

    const accountTokenSnapshot = getOrInitAccountTokenSnapshot(
        event.params.admin,
        event.params.token,
        event.block,
    );
    accountTokenSnapshot.adminOfPoolCount = accountTokenSnapshot.adminOfPoolCount + 1;
    accountTokenSnapshot.save();

    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.admin,
        event.params.token,
        eventName
    );

    _createTokenStatisticLogEntity(event, event.params.token, eventName);
    // Create Event Entity
    _createPoolCreatedEntity(event);
}

export function handlePoolConnectionUpdated(
    event: PoolConnectionUpdated
): void {
    // Update Pool Member Entity
    let poolMember = getOrInitOrUpdatePoolMember(
        event,
        event.params.pool,
        event.params.account
    );
    const previousIsConnected = poolMember.isConnected;
    const memberConnectedStatusUpdated =
        previousIsConnected !== event.params.connected;
    poolMember.isConnected = event.params.connected;

    const hasMembershipWithUnits = membershipWithUnitsExists(poolMember.id);

    // Update Pool Entity
    let pool = getOrInitPool(event, event.params.pool.toHex());
    // @note we modify pool and poolMember here in memory, but do not save
    pool = updatePoolParticleAndTotalAmountFlowedAndDistributed(event, pool);
    settlePDPoolMemberMU(pool, poolMember, event.block);
    if (poolMember.units.gt(BIG_INT_ZERO)) {
        if (memberConnectedStatusUpdated) {
            // disconnected -> connected case
            if (event.params.connected) {
                pool.totalConnectedUnits = pool.totalConnectedUnits.plus(
                    poolMember.units
                );
                pool.totalDisconnectedUnits = pool.totalDisconnectedUnits.minus(
                    poolMember.units
                );
                pool.totalConnectedMembers = pool.totalConnectedMembers + 1;
                pool.totalDisconnectedMembers =
                    pool.totalDisconnectedMembers - 1;
            } else {
                // connected -> disconnected case
                pool.totalConnectedUnits = pool.totalConnectedUnits.minus(
                    poolMember.units
                );
                pool.totalDisconnectedUnits = pool.totalDisconnectedUnits.plus(
                    poolMember.units
                );
                pool.totalConnectedMembers = pool.totalConnectedMembers - 1;
                pool.totalDisconnectedMembers =
                    pool.totalDisconnectedMembers + 1;
            }
        }
    }
    
    // Update Token Stats Streamed Until Updated At
    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);
    // Update ATS Balance and Streamed Until Updated At
    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.account,
        event.params.token,
        event.block,
        BigInt.fromI32(0)
    );

    pool.save();
    poolMember.save();
    
    const isConnecting = event.params.connected;

    // there is no concept of revoking in GDA, but in the subgraph
    // revoking is disconnecting and deleting is setting units to 0
    const isRevoking = !event.params.connected;

    updateAggregateDistributionAgreementData(
        event.params.account,
        event.params.token,
        hasMembershipWithUnits || poolMember.isConnected,
        poolMember.isConnected,
        false, // don't increment memberWithUnits
        isRevoking, // isRevoking
        false, // not deleting (setting units to 0)
        isConnecting, // approving membership here
        event.block,
        false // isIDA
    );

    // Create Event Entity
    _createPoolConnectionUpdatedEntity(event, poolMember.id);

    // Create ATS and Token Statistic Log Entities
    const eventName = "PoolConnectionUpdated";
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.account,
        event.params.token,
        eventName
    );

    _createTokenStatisticLogEntity(event, event.params.token, eventName);
}

export function handleBufferAdjusted(event: BufferAdjusted): void {
    // Update Pool Distributor
    let poolDistributor = getOrInitPoolDistributor(
        event,
        event.params.pool,
        event.params.from
    );
    poolDistributor = updatePoolDistributorTotalAmountFlowedAndDistributed(
        event,
        poolDistributor
    );
    poolDistributor.totalBuffer = event.params.newBufferAmount;
    poolDistributor.save();

    // Update Pool
    let pool = getOrInitPool(event, event.params.pool.toHex());
    pool = updatePoolParticleAndTotalAmountFlowedAndDistributed(event, pool);
    pool.totalBuffer = pool.totalBuffer.plus(event.params.bufferDelta);
    pool.save();

    // Update Token Stats Buffer
    const tokenStatistic = getOrInitTokenStatistic(
        event.params.token,
        event.block
    );
    tokenStatistic.totalGDADeposit = tokenStatistic.totalGDADeposit.plus(
        event.params.bufferDelta
    );
    tokenStatistic.save();

    // Create Event Entity
    _createBufferAdjustedEntity(event, poolDistributor.id);
}

export function handleFlowDistributionUpdated(
    event: FlowDistributionUpdated
): void {
    // Update Pool Distributor
    let poolDistributor = getOrInitPoolDistributor(
        event,
        event.params.pool,
        event.params.distributor
    );
    poolDistributor = updatePoolDistributorTotalAmountFlowedAndDistributed(
        event,
        poolDistributor
    );
    poolDistributor.flowRate = event.params.newDistributorToPoolFlowRate;
    poolDistributor.save();

    // Update Pool
    let pool = getOrInitPool(event, event.params.pool.toHex());

    // @note that we are duplicating update of updatedAtTimestamp/BlockNumber here
    // in the two functions
    pool = updatePoolParticleAndTotalAmountFlowedAndDistributed(event, pool);
    pool.perUnitFlowRate = divideOrZero(event.params.newDistributorToPoolFlowRate, pool.totalUnits);
    pool.flowRate = event.params.newTotalDistributionFlowRate;
    pool.adjustmentFlowRate = event.params.adjustmentFlowRate;
    pool.save();

    const flowRateDelta = event.params.newDistributorToPoolFlowRate.minus(
        event.params.oldFlowRate
    );

    const isCreate = event.params.oldFlowRate.equals(BIG_INT_ZERO);
    const isDelete =
        event.params.newDistributorToPoolFlowRate.equals(BIG_INT_ZERO);

    // Update Token Statistics
    const eventName = "FlowDistributionUpdated";
    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);
    _createTokenStatisticLogEntity(event, event.params.token, eventName);
    updateTokenStatisticStreamData(
        event.params.token,
        event.params.newDistributorToPoolFlowRate,
        flowRateDelta,
        BIG_INT_ZERO,
        isCreate,
        isDelete,
        false,
        event.block
    );
    _createTokenStatisticLogEntity(event, event.params.token, eventName);

    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.distributor,
        event.params.token,
        event.block,
        null
    );
    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.distributor,
        event.params.token,
        eventName
    );

    // Update ATS
    updateSenderATSStreamData(
        event.params.distributor,
        event.params.token,
        event.params.newDistributorToPoolFlowRate,
        flowRateDelta,
        BIG_INT_ZERO,
        isCreate,
        isDelete,
        false,
        event.block
    );

    // Create Event Entity
    _createFlowDistributionUpdatedEntity(event, poolDistributor.id, pool.totalUnits);
}

export function handleInstantDistributionUpdated(
    event: InstantDistributionUpdated
): void {
    // Update Pool Distributor
    let poolDistributor = getOrInitPoolDistributor(
        event,
        event.params.pool,
        event.params.distributor
    );
    poolDistributor = updatePoolDistributorTotalAmountFlowedAndDistributed(
        event,
        poolDistributor
    );
    poolDistributor.totalAmountInstantlyDistributedUntilUpdatedAt =
        poolDistributor.totalAmountInstantlyDistributedUntilUpdatedAt.plus(
            event.params.actualAmount
        );
    poolDistributor.totalAmountDistributedUntilUpdatedAt =
        poolDistributor.totalAmountDistributedUntilUpdatedAt.plus(
            event.params.actualAmount
        );
    poolDistributor.save();

    // Update Pool
    let pool = getOrInitPool(event, event.params.pool.toHex());

    // @note that we are duplicating update of updatedAtTimestamp/BlockNumber here
    // in the two functions
    pool = updatePoolParticleAndTotalAmountFlowedAndDistributed(event, pool);
    // @note a speculations on what needs to be done
    pool.perUnitSettledValue = pool.perUnitSettledValue.plus(divideOrZero(event.params.actualAmount, pool.totalUnits));
    const previousTotalAmountDistributed =
        pool.totalAmountDistributedUntilUpdatedAt;
    pool.totalAmountInstantlyDistributedUntilUpdatedAt =
        pool.totalAmountInstantlyDistributedUntilUpdatedAt.plus(
            event.params.actualAmount
        );
    pool.totalAmountDistributedUntilUpdatedAt =
        pool.totalAmountDistributedUntilUpdatedAt.plus(
            event.params.actualAmount
        );
    pool.save();

    // Update Token Statistic
    const tokenStatistic = getOrInitTokenStatistic(
        event.params.token,
        event.block
    );

    if (previousTotalAmountDistributed.equals(BIG_INT_ZERO)) {
        tokenStatistic.totalNumberOfActivePools =
            tokenStatistic.totalNumberOfActivePools + 1;
    }

    tokenStatistic.totalAmountDistributedUntilUpdatedAt =
        tokenStatistic.totalAmountDistributedUntilUpdatedAt.plus(
            event.params.actualAmount
        );
    tokenStatistic.save();

    const eventName = "InstantDistributionUpdated";
    updateTokenStatsStreamedUntilUpdatedAt(event.params.token, event.block);
    _createTokenStatisticLogEntity(event, event.params.token, eventName);

    // Update ATS
    updateATSStreamedAndBalanceUntilUpdatedAt(
        event.params.distributor,
        event.params.token,
        event.block,
        null
    );

    _createAccountTokenSnapshotLogEntity(
        event,
        event.params.distributor,
        event.params.token,
        eventName
    );

    // Create Event Entity
    _createInstantDistributionUpdatedEntity(event, poolDistributor.id, pool.totalUnits);
}

// Event Entity Creation Functions

function _createPoolCreatedEntity(event: PoolCreated): PoolCreatedEvent {
    const ev = new PoolCreatedEvent(createEventID("PoolCreated", event));
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.pool,
        event.transaction.from,
        event.params.admin,
    ]);

    ev.token = event.params.token;
    ev.caller = event.transaction.from;
    ev.admin = event.params.admin;
    ev.pool = event.params.pool.toHex();

    ev.save();

    return ev;
}

function _createPoolConnectionUpdatedEntity(
    event: PoolConnectionUpdated,
    poolMemberId: string
): PoolConnectionUpdatedEvent {
    const ev = new PoolConnectionUpdatedEvent(
        createEventID("PoolConnectionUpdated", event)
    );
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.pool,
        event.params.account,
    ]);

    ev.token = event.params.token;
    ev.connected = event.params.connected;
    ev.pool = event.params.pool.toHex();
    ev.poolMember = poolMemberId;
    ev.userData = event.params.userData;

    ev.save();

    return ev;
}

function _createBufferAdjustedEntity(
    event: BufferAdjusted,
    poolDistributorId: string
): BufferAdjustedEvent {
    const ev = new BufferAdjustedEvent(createEventID("BufferAdjusted", event));
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.pool,
        event.params.from,
    ]);

    ev.token = event.params.token;
    ev.bufferDelta = event.params.bufferDelta;
    ev.newBufferAmount = event.params.newBufferAmount;
    ev.totalBufferAmount = event.params.totalBufferAmount;
    ev.pool = event.params.pool.toHex();
    ev.poolDistributor = poolDistributorId;

    ev.save();

    return ev;
}

function _createInstantDistributionUpdatedEntity(
    event: InstantDistributionUpdated,
    poolDistributorId: string,
    totalUnits: BigInt
): InstantDistributionUpdatedEvent {
    const ev = new InstantDistributionUpdatedEvent(
        createEventID("InstantDistributionUpdated", event)
    );
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.pool,
        event.params.distributor,
        event.params.operator,
    ]);

    ev.token = event.params.token;
    ev.operator = event.params.operator;
    ev.requestedAmount = event.params.requestedAmount;
    ev.actualAmount = event.params.actualAmount;
    ev.pool = event.params.pool.toHex();
    ev.poolDistributor = poolDistributorId;
    ev.totalUnits = totalUnits;
    ev.userData = event.params.userData;

    ev.save();

    return ev;
}

function _createFlowDistributionUpdatedEntity(
    event: FlowDistributionUpdated,
    poolDistributorId: string,
    totalUnits: BigInt
): FlowDistributionUpdatedEvent {
    const ev = new FlowDistributionUpdatedEvent(
        createEventID("FlowDistributionUpdated", event)
    );
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.pool,
        event.params.distributor,
        event.params.operator,
    ]);

    ev.token = event.params.token;
    ev.operator = event.params.operator;
    ev.oldFlowRate = event.params.oldFlowRate;
    ev.newDistributorToPoolFlowRate = event.params.newDistributorToPoolFlowRate;
    ev.newTotalDistributionFlowRate = event.params.newTotalDistributionFlowRate;
    ev.adjustmentFlowRecipient = event.params.adjustmentFlowRecipient;
    ev.adjustmentFlowRate = event.params.adjustmentFlowRate;
    ev.pool = event.params.pool.toHex();
    ev.poolDistributor = poolDistributorId;
    ev.totalUnits = totalUnits;
    ev.userData = event.params.userData;

    ev.save();

    return ev;
}
