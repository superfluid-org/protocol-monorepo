import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts";
import { assert, newMockEvent } from "matchstick-as";
import {
    FlowUpdated,
    FlowUpdatedExtension,
    FlowOperatorUpdated,
} from "../../generated/ConstantFlowAgreementV1/IConstantFlowAgreementV1";
import { handleFlowUpdated } from "../../src/mappings/cfav1";
import { getStreamID, ZERO_ADDRESS, getAccountTokenSnapshotID } from "../../src/utils";
import { assertEventBaseProperties } from "../assertionHelpers";
import { DEFAULT_DECIMALS, LIQUIDATION_PERIOD } from "../constants";
import {
    getAddressEventParam,
    getBigIntEventParam,
    getBytesEventParam,
    getI32EventParam,
    stringToBytes,
} from "../converters";
import { mockedHandleFlowUpdatedRPCCalls } from "../mockedFunctions";

// Mock Event Creators
export function createFlowUpdatedEvent(
    token: string,
    sender: string,
    receiver: string,
    flowRate: BigInt,
    totalSenderFlowRate: BigInt,
    totalReceiverFlowRate: BigInt,
    userData: Bytes
): FlowUpdated {
    const newFlowUpdatedEvent = changetype<FlowUpdated>(newMockEvent());
    newFlowUpdatedEvent.parameters = new Array();
    newFlowUpdatedEvent.parameters.push(getAddressEventParam("token", token));
    newFlowUpdatedEvent.parameters.push(getAddressEventParam("sender", sender));
    newFlowUpdatedEvent.parameters.push(getAddressEventParam("receiver", receiver));
    newFlowUpdatedEvent.parameters.push(getBigIntEventParam("flowRate", flowRate));
    newFlowUpdatedEvent.parameters.push(getBigIntEventParam("totalSenderFlowRate", totalSenderFlowRate));
    newFlowUpdatedEvent.parameters.push(getBigIntEventParam("totalReceiverFlowRate", totalReceiverFlowRate));
    newFlowUpdatedEvent.parameters.push(getBytesEventParam("userData", userData));

    return newFlowUpdatedEvent;
}

export function createFlowUpdatedExtensionEvent(
    flowOperator: string,
    deposit: BigInt
): FlowUpdatedExtension {
    const newFlowUpdatedExtensionEvent = changetype<FlowUpdatedExtension>(
        newMockEvent()
    );
    newFlowUpdatedExtensionEvent.parameters = new Array();
    newFlowUpdatedExtensionEvent.parameters.push(getAddressEventParam("flowOperator", flowOperator));
    newFlowUpdatedExtensionEvent.parameters.push(getBigIntEventParam("deposit", deposit));

    return newFlowUpdatedExtensionEvent;
}

export function createFlowOperatorUpdatedEvent(
    token: string,
    sender: string,
    flowOperator: string,
    permissions: i32,
    flowRateAllowance: BigInt
): FlowOperatorUpdated {
    const newFlowOperatorUpdatedEvent = changetype<FlowOperatorUpdated>(
        newMockEvent()
    );
    newFlowOperatorUpdatedEvent.parameters = new Array();
    newFlowOperatorUpdatedEvent.parameters.push(getAddressEventParam("token", token));
    newFlowOperatorUpdatedEvent.parameters.push(getAddressEventParam("sender", sender));
    newFlowOperatorUpdatedEvent.parameters.push(getAddressEventParam("flowOperator", flowOperator));
    newFlowOperatorUpdatedEvent.parameters.push(getI32EventParam("permissions", permissions));
    newFlowOperatorUpdatedEvent.parameters.push(getBigIntEventParam("flowRateAllowance", flowRateAllowance));

    return newFlowOperatorUpdatedEvent;
}

// Misc Helper Functions
/**
 * Creates a flow updated event without handling it
 * @param superToken
 * @param tokenName
 * @param tokenSymbol
 * @param sender
 * @param receiver
 * @param underlyingToken
 * @param flowRate
 * @param previousSenderFlowRate
 * @param previousReceiverFlowRate
 * @param stringUserData
 * @param deposit
 * @param expectedOwedDeposit
 * @returns FlowUpdated event
 */
export function createFlowUpdatedEventWithMocks(
    superToken: string,
    tokenName: string,
    tokenSymbol: string,
    sender: string,
    receiver: string,
    underlyingToken: Address,
    flowRate: BigInt,
    previousSenderFlowRate: BigInt,
    previousReceiverFlowRate: BigInt,
    stringUserData: string,
    deposit: BigInt,
    expectedOwedDeposit: BigInt
): FlowUpdated {
    const flowRateDelta = flowRate.minus(previousSenderFlowRate);
    const totalSenderFlowRate = previousSenderFlowRate.minus(flowRateDelta);
    const totalReceiverFlowRate = previousReceiverFlowRate.plus(flowRateDelta);
    const userData = stringToBytes(stringUserData);

    const flowUpdatedEvent = createFlowUpdatedEvent(
        superToken,
        sender,
        receiver,
        flowRate,
        totalSenderFlowRate,
        totalReceiverFlowRate,
        userData
    );

    mockedHandleFlowUpdatedRPCCalls(
        flowUpdatedEvent,
        superToken,
        DEFAULT_DECIMALS,
        tokenName,
        tokenSymbol,
        underlyingToken,
        deposit,
        expectedOwedDeposit
    );

    return flowUpdatedEvent;
}

/**
 * Create a flowUpdated event and assert the properties were created correctly
 * @param superToken
 * @param tokenName
 * @param tokenSymbol
 * @param sender
 * @param receiver
 * @param underlyingToken
 * @param expectedType 0 (create), 1 (update) or 2 (delete)
 * @param expectedOwedDeposit
 * @param flowRate
 * @param previousSenderFlowRate
 * @param previousReceiverFlowRate
 * @param stringUserData
 * @returns FlowUpdated event
 */
 export function modifyFlowAndAssertFlowUpdatedEventProperties(
    superToken: string,
    tokenName: string,
    tokenSymbol: string,
    sender: string,
    receiver: string,
    underlyingToken: Address,
    expectedType: string,
    expectedOwedDeposit: BigInt,
    flowRate: BigInt,
    previousSenderFlowRate: BigInt,
    previousReceiverFlowRate: BigInt,
    stringUserData: string
): FlowUpdated {
    const oldFlowRate = previousSenderFlowRate.abs();
    const flowRateDelta = flowRate.minus(previousSenderFlowRate);
    const totalSenderFlowRate = previousSenderFlowRate.minus(flowRateDelta);
    const totalReceiverFlowRate = previousReceiverFlowRate.plus(flowRateDelta);
    const userData = stringToBytes(stringUserData);

    const deposit = getDeposit(flowRate);

    const flowUpdatedEvent = createFlowUpdatedEvent(
        superToken,
        sender,
        receiver,
        flowRate,
        totalSenderFlowRate,
        totalReceiverFlowRate,
        userData
    );

    mockedHandleFlowUpdatedRPCCalls(
        flowUpdatedEvent,
        superToken,
        DEFAULT_DECIMALS,
        tokenName,
        tokenSymbol,
        underlyingToken,
        deposit,
        expectedOwedDeposit
    );

    handleFlowUpdated(flowUpdatedEvent);

    const id = assertEventBaseProperties(
        flowUpdatedEvent,
        "FlowUpdated"
    );
    const streamId = getStreamID(
        Address.fromString(sender),
        Address.fromString(receiver),
        Address.fromString(superToken),
        0
    );
    assert.fieldEquals("FlowUpdatedEvent", id, "token", superToken);
    assert.fieldEquals("FlowUpdatedEvent", id, "sender", sender);
    assert.fieldEquals("FlowUpdatedEvent", id, "receiver", receiver);
    assert.fieldEquals("FlowUpdatedEvent", id, "flowOperator", ZERO_ADDRESS.toHexString());
    assert.fieldEquals("FlowUpdatedEvent", id, "flowRate", flowRate.toString());
    assert.fieldEquals("FlowUpdatedEvent", id, "totalSenderFlowRate", totalSenderFlowRate.toString());
    assert.fieldEquals("FlowUpdatedEvent", id, "totalReceiverFlowRate", totalReceiverFlowRate.toString());
    assert.fieldEquals("FlowUpdatedEvent", id, "deposit", deposit.toString());
    assert.fieldEquals("FlowUpdatedEvent", id, "owedDeposit", expectedOwedDeposit.toString());
    assert.fieldEquals("FlowUpdatedEvent", id, "userData", userData.toHexString());
    assert.fieldEquals("FlowUpdatedEvent", id, "oldFlowRate", oldFlowRate.toString());
    assert.fieldEquals("FlowUpdatedEvent", id, "type", expectedType);
    assert.fieldEquals("FlowUpdatedEvent", id, "stream", streamId);

    assert.fieldEquals("Stream", streamId, "deposit", deposit.toString());
    assert.fieldEquals("Stream", streamId, "owedDeposit", expectedOwedDeposit.toString());

    // Assert account token snapshots were created for sender and receiver
    const senderAtsId = getAccountTokenSnapshotID(Address.fromString(sender), Address.fromString(superToken));
    const receiverAtsId = getAccountTokenSnapshotID(Address.fromString(receiver), Address.fromString(superToken));
    
    // Assert sender AccountTokenSnapshot exists and has expected properties
    assert.fieldEquals("AccountTokenSnapshot", senderAtsId, "account", sender);
    assert.fieldEquals("AccountTokenSnapshot", senderAtsId, "token", superToken);
    
    // Assert receiver AccountTokenSnapshot exists and has expected properties  
    assert.fieldEquals("AccountTokenSnapshot", receiverAtsId, "account", receiver);
    assert.fieldEquals("AccountTokenSnapshot", receiverAtsId, "token", superToken);

    return flowUpdatedEvent;
}

/**
 * Calculates the deposit amount given a flow rate.
 * NOTE: We ignore clipping here and only update flow: multiply flow rate by the liquidation period.
 * @param flowRate
 * @returns unclipped deposit
 */
 export function getDeposit(flowRate: BigInt): BigInt {
    return flowRate.times(LIQUIDATION_PERIOD);
}
