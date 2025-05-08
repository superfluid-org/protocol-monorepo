import { BigInt } from "@graphprotocol/graph-ts";
import {
    FlowOperatorUpdated,
    FlowUpdated,
    FlowUpdatedExtension,
    IConstantFlowAgreementV1,
} from "../../generated/ConstantFlowAgreementV1/IConstantFlowAgreementV1";
import {
    FlowOperatorUpdatedEvent,
    FlowUpdatedEvent,
    StreamPeriod,
    StreamRevision,
} from "../../generated/schema";
import {
    BIG_INT_ONE,
    BIG_INT_ZERO,
    bytesToAddress,
    getFlowOperatorID,
    getStreamPeriodID,
    MAX_FLOW_RATE,
    initializeEventEntity,
    tokenHasValidHost,
    ZERO_ADDRESS,
    createEventID,
} from "../utils";
import {
    _createAccountTokenSnapshotLogEntity,
    _createTokenStatisticLogEntity,
    getOrInitFlowOperator,
    getOrInitStream,
    getOrInitStreamRevision,
    updateSenderATSStreamData,
    updateReceiverATSStreamData,
    updateATSStreamedAndBalanceUntilUpdatedAt,
    updateTokenStatisticStreamData,
    updateTokenStatsStreamedUntilUpdatedAt,
} from "../mappingHelpers";
import { getHostAddress } from "../addresses";

enum FlowActionType {
    create,
    update,
    terminate,
}

/******************
 * Event Handlers *
 *****************/
export function handleFlowUpdated(event: FlowUpdated): void {
    const senderAddress = event.params.sender;
    const receiverAddress = event.params.receiver;
    const tokenAddress = event.params.token;
    const flowRate = event.params.flowRate;
    const currentTimestamp = event.block.timestamp;
    const hostAddress = getHostAddress();

    const hasValidHost = tokenHasValidHost(hostAddress, tokenAddress);
    if (!hasValidHost) {
        return;
    }

    // create or update stream entity
    const cfaContract = IConstantFlowAgreementV1.bind(event.address);
    const depositResult = cfaContract.try_getFlow(
        event.params.token,
        event.params.sender,
        event.params.receiver
    );

    // NOTE: if we want to optimize this in the future,
    // we have to create a new global entity which is
    // updated once we first see the FlowUpdatedExtension event
    // and once we see it, we rely on the handleFlowUpdatedExtension
    // handler to get us the deposit instead of doing a web3 query
    // every time
    const newDeposit = depositResult.reverted
        ? BigInt.fromI32(0)
        : depositResult.value.value2; // deposit

    const stream = getOrInitStream(event);
    const oldDeposit = stream.deposit;
    const oldFlowRate = stream.currentFlowRate;

    const timeSinceLastUpdate = currentTimestamp.minus(
        stream.updatedAtTimestamp
    );
    const userAmountStreamedSinceLastUpdate =
        oldFlowRate.times(timeSinceLastUpdate);
    const newStreamedUntilLastUpdate = stream.streamedUntilUpdatedAt.plus(
        userAmountStreamedSinceLastUpdate
    );
    const depositDelta = newDeposit.minus(oldDeposit);
    stream.currentFlowRate = flowRate;
    stream.streamedUntilUpdatedAt = newStreamedUntilLastUpdate;
    stream.updatedAtTimestamp = currentTimestamp;
    stream.updatedAtBlockNumber = event.block.number;
    stream.deposit = newDeposit;
    stream.userData = event.params.userData;
    stream.save();

    const flowRateDelta = flowRate.minus(oldFlowRate);
    const isCreate = oldFlowRate.equals(BIG_INT_ZERO);
    const isDelete = flowRate.equals(BIG_INT_ZERO);

    if (isDelete) {
        const streamRevision = getOrInitStreamRevision(
            senderAddress,
            receiverAddress,
            tokenAddress
        );
        streamRevision.revisionIndex = streamRevision.revisionIndex + 1;

        streamRevision.save();
    }

    // create event entity
    const flowUpdateEvent = _createFlowUpdatedEntity(
        event,
        oldFlowRate,
        stream.id,
        newStreamedUntilLastUpdate,
        newDeposit
    );
    handleStreamPeriodUpdate(
        event,
        flowUpdateEvent,
        oldFlowRate,
        stream.id,
        newDeposit
    );

    // update streamed and balance until updated at for sender and receiver
    updateATSStreamedAndBalanceUntilUpdatedAt(
        senderAddress,
        tokenAddress,
        event.block,
        depositDelta
    );
    updateATSStreamedAndBalanceUntilUpdatedAt(
        receiverAddress,
        tokenAddress,
        event.block,
        BigInt.fromI32(0)
    );

    // update stream counter data for sender and receiver ATS
    updateSenderATSStreamData(
        senderAddress,
        tokenAddress,
        flowRate,
        flowRateDelta,
        depositDelta,
        isCreate,
        isDelete,
        true,
        event.block
    );
    updateReceiverATSStreamData(
        receiverAddress,
        tokenAddress,
        flowRate,
        flowRateDelta,
        isCreate,
        isDelete,
        event.block
    );

    // update token stats streamed until updated at
    updateTokenStatsStreamedUntilUpdatedAt(tokenAddress, event.block);

    // update token stats stream counter data
    updateTokenStatisticStreamData(
        tokenAddress,
        flowRate,
        flowRateDelta,
        depositDelta,
        isCreate,
        isDelete,
        true,
        event.block
    );

    // create ATS and token statistic log entities
    _createAccountTokenSnapshotLogEntity(
        event,
        senderAddress,
        tokenAddress,
        "FlowUpdated"
    );
    _createAccountTokenSnapshotLogEntity(
        event,
        receiverAddress,
        tokenAddress,
        "FlowUpdated"
    );
    _createTokenStatisticLogEntity(event, tokenAddress, "FlowUpdated");
}

// NOTE: This handler is run right after handleStreamUpdated as the FlowUpdatedExtension
// event is emitted right after the FlowUpdated event in the contract. We update the
// FlowUpdated event to include the flowOperator and deposit properties.
// Given that we know that the events occur right after each other in the same transaction
// we have the necessary information to load the FlowUpdated entity to update it.
export function handleFlowUpdatedExtension(event: FlowUpdatedExtension): void {
    const previousLogIndex = event.logIndex.minus(BIG_INT_ONE);
    const flowUpdatedEvent = FlowUpdatedEvent.load(
        "FlowUpdated-" +
            event.transaction.hash.toHexString() +
            "-" +
            previousLogIndex.toString()
    );
    if (flowUpdatedEvent != null) {
        flowUpdatedEvent.flowOperator = event.params.flowOperator;
        flowUpdatedEvent.deposit = event.params.deposit;
        flowUpdatedEvent.addresses = flowUpdatedEvent.addresses.concat([
            event.params.flowOperator,
        ]);
        flowUpdatedEvent.save();

        // we know that the flowOperator should be updated if the flowOperator is
        // not the sender - it doesn't matter when they delete as we don't need to
        // update anything in that scenario
        if (flowUpdatedEvent.flowOperator.notEqual(flowUpdatedEvent.sender)) {
            updateFlowOperatorForFlowUpdated(event, flowUpdatedEvent);
        }
    }
}

export function handleFlowOperatorUpdated(event: FlowOperatorUpdated): void {
    const flowOperator = getOrInitFlowOperator(
        event.block,
        event.params.flowOperator,
        event.params.token,
        event.params.sender
    );
    flowOperator.permissions = event.params.permissions;
    flowOperator.flowRateAllowanceGranted = event.params.flowRateAllowance;
    flowOperator.flowRateAllowanceRemaining = event.params.flowRateAllowance;
    flowOperator.flowOperator = event.params.flowOperator;
    flowOperator.save();

    _createFlowOperatorUpdatedEventEntity(event);
}

/****************************
 * Updater Helper Functions *
 ***************************/
function getFlowActionType(
    oldFlowRate: BigInt,
    newFlowRate: BigInt
): FlowActionType {
    return oldFlowRate.equals(BIG_INT_ZERO)
        ? FlowActionType.create
        : newFlowRate.equals(BIG_INT_ZERO)
        ? FlowActionType.terminate
        : FlowActionType.update;
}

function incrementPeriodRevisionIndex(streamRevision: StreamRevision): void {
    streamRevision.periodRevisionIndex = streamRevision.periodRevisionIndex + 1;
    streamRevision.save();
}

function handleStreamPeriodUpdate(
    event: FlowUpdated,
    eventEntity: FlowUpdatedEvent,
    previousFlowRate: BigInt,
    streamId: string,
    newDeposit: BigInt
): void {
    const streamRevision = getOrInitStreamRevision(
        event.params.sender,
        event.params.receiver,
        event.params.token
    );
    const flowActionType = getFlowActionType(
        previousFlowRate,
        event.params.flowRate
    );
    const previousStreamPeriod = StreamPeriod.load(
        getStreamPeriodID(streamId, streamRevision.periodRevisionIndex)
    );
    switch (flowActionType) {
        case FlowActionType.create:
            startStreamPeriod(
                eventEntity.id,
                event,
                streamRevision,
                streamId,
                newDeposit
            );
            break;
        case FlowActionType.update:
            if (!previousStreamPeriod) {
                throw Error(
                    "Previous StreamPeriod not found for flow update action"
                );
            }
            endStreamPeriod(
                eventEntity.id,
                previousStreamPeriod as StreamPeriod,
                event,
                streamRevision,
                previousFlowRate
            );
            startStreamPeriod(
                eventEntity.id,
                event,
                streamRevision,
                streamId,
                newDeposit
            );
            break;
        case FlowActionType.terminate:
            if (!previousStreamPeriod) {
                throw Error(
                    "Previous StreamPeriod not found for flow terminate action"
                );
            }
            endStreamPeriod(
                eventEntity.id,
                previousStreamPeriod as StreamPeriod,
                event,
                streamRevision,
                previousFlowRate
            );
            break;
        default:
            throw "Unrecognized FlowActionType";
    }
}

function startStreamPeriod(
    flowUpdatedEventId: string,
    event: FlowUpdated,
    streamRevision: StreamRevision,
    streamId: string,
    newDeposit: BigInt
): void {
    const streamPeriod = new StreamPeriod(
        getStreamPeriodID(streamId, streamRevision.periodRevisionIndex)
    );
    streamPeriod.sender = event.params.sender.toHex();
    streamPeriod.receiver = event.params.receiver.toHex();
    streamPeriod.token = event.params.token.toHex();
    streamPeriod.flowRate = event.params.flowRate;
    streamPeriod.startedAtTimestamp = event.block.timestamp;
    streamPeriod.startedAtBlockNumber = event.block.number;
    streamPeriod.startedAtEvent = flowUpdatedEventId;
    streamPeriod.stream = streamId;
    streamPeriod.deposit = newDeposit;
    streamPeriod.save();
}

function endStreamPeriod(
    flowUpdatedEventId: string,
    existingStreamPeriod: StreamPeriod,
    event: FlowUpdated,
    streamRevision: StreamRevision,
    flowRateBeforeUpdate: BigInt
): void {
    const streamStopTime = event.block.timestamp;
    existingStreamPeriod.stoppedAtTimestamp = streamStopTime;
    existingStreamPeriod.stoppedAtBlockNumber = event.block.number;
    existingStreamPeriod.stoppedAtEvent = flowUpdatedEventId;
    existingStreamPeriod.totalAmountStreamed = flowRateBeforeUpdate.times(
        streamStopTime.minus(existingStreamPeriod.startedAtTimestamp)
    );
    existingStreamPeriod.save();
    incrementPeriodRevisionIndex(streamRevision);
}

export function updateFlowOperatorForFlowUpdated(
    event: FlowUpdatedExtension,
    flowUpdatedEvent: FlowUpdatedEvent
): void {
    if (flowUpdatedEvent.type == FlowActionType.terminate) {
        return;
    }
    const flowOperator = getOrInitFlowOperator(
        event.block,
        event.params.flowOperator,
        bytesToAddress(flowUpdatedEvent.token),
        bytesToAddress(flowUpdatedEvent.sender)
    );

    if (flowUpdatedEvent.type == FlowActionType.create) {
        flowOperator.flowRateAllowanceRemaining =
            flowOperator.flowRateAllowanceGranted.equals(MAX_FLOW_RATE)
                ? flowOperator.flowRateAllowanceGranted
                : flowOperator.flowRateAllowanceRemaining.minus(
                      flowUpdatedEvent.flowRate
                  );
    }

    if (flowUpdatedEvent.type == FlowActionType.update) {
        const flowRateAllowanceDelta = flowUpdatedEvent.flowRate.minus(
            flowUpdatedEvent.oldFlowRate
        );
        flowOperator.flowRateAllowanceRemaining =
            flowOperator.flowRateAllowanceGranted.equals(MAX_FLOW_RATE) ||
            flowRateAllowanceDelta.lt(BIG_INT_ZERO)
                ? flowOperator.flowRateAllowanceGranted
                : flowOperator.flowRateAllowanceRemaining.minus(
                      flowRateAllowanceDelta
                  );
    }
    flowOperator.save();
}

/****************************************
 * Create Event Entity Helper Functions *
 ***************************************/
function _createFlowUpdatedEntity(
    event: FlowUpdated,
    oldFlowRate: BigInt,
    streamId: string,
    totalAmountStreamedUntilTimestamp: BigInt,
    deposit: BigInt
): FlowUpdatedEvent {
    const ev = new FlowUpdatedEvent(createEventID("FlowUpdated", event));
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.sender,
        event.params.receiver,
    ]);

    ev.token = event.params.token;
    ev.sender = event.params.sender;
    ev.receiver = event.params.receiver;
    ev.flowRate = event.params.flowRate;
    ev.totalSenderFlowRate = event.params.totalSenderFlowRate;
    ev.totalReceiverFlowRate = event.params.totalReceiverFlowRate;
    ev.userData = event.params.userData;
    ev.oldFlowRate = oldFlowRate;
    ev.stream = streamId;
    ev.totalAmountStreamedUntilTimestamp = totalAmountStreamedUntilTimestamp;
    ev.flowOperator = ZERO_ADDRESS;
    ev.deposit = deposit;

    const type = getFlowActionType(oldFlowRate, event.params.flowRate);
    ev.type = type;
    ev.save();
    return ev;
}

function _createFlowOperatorUpdatedEventEntity(
    event: FlowOperatorUpdated
): FlowOperatorUpdatedEvent {
    const ev = new FlowOperatorUpdatedEvent(
        createEventID("FlowOperatorUpdated", event)
    );
    initializeEventEntity(ev, event, [
        event.params.token,
        event.params.sender,
        event.params.flowOperator,
    ]);

    ev.token = event.params.token;
    ev.sender = event.params.sender;
    ev.permissions = event.params.permissions;
    ev.flowRateAllowance = event.params.flowRateAllowance;
    ev.flowOperator = getFlowOperatorID(
        event.params.flowOperator,
        event.params.token,
        event.params.sender
    );

    ev.save();
    return ev;
}
