import { Address, BigInt } from "@graphprotocol/graph-ts";
import { assert, beforeEach, clearStore, describe, test } from "matchstick-as/assembly/index";
import { handleFlowOperatorUpdated, handleFlowUpdated } from "../../../src/mappings/cfav1";
import {
    BIG_INT_ZERO,
    getAccountTokenSnapshotID,
    getFlowOperatorID,
    getStreamID,
    ZERO_ADDRESS,
} from "../../../src/utils";
import { assertHigherOrderBaseProperties } from "../../assertionHelpers";
import { alice, bob, maticXAddress, maticXName, maticXSymbol } from "../../constants";
import {
    createFlowOperatorUpdatedEvent,
    getDeposit,
    modifyFlowAndAssertFlowUpdatedEventProperties,
    createFlowUpdatedEventWithMocks,
} from "../cfav1.helper";
import { mockedApprove } from "../../mockedFunctions";

const initialFlowRate = BigInt.fromI32(100);

describe("ConstantFlowAgreementV1 Higher Order Level Entity Unit Tests", () => {
    beforeEach(() => {
        clearStore();
    });

    test("handleFlowUpdated() - Should create a new Stream entity (create)", () => {
        // create flow
        const flowUpdatedEvent = modifyFlowAndAssertFlowUpdatedEventProperties(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            "0",                // expectedType
            BIG_INT_ZERO,       // expectedOwedDeposit
            initialFlowRate,    // flowRate
            BIG_INT_ZERO,       // previousSenderFlowRate
            BIG_INT_ZERO,       // previousReceiverFlowRate
            "henlo"             // userData
        );

        const id = getStreamID(
            flowUpdatedEvent.params.sender,
            flowUpdatedEvent.params.receiver,
            flowUpdatedEvent.params.token,
            0
        );
        const deposit = getDeposit(flowUpdatedEvent.params.flowRate);
        const streamedUntilUpdatedAt = _getStreamedUntilUpdatedAt(
            BIG_INT_ZERO,
            flowUpdatedEvent.block.timestamp,
            BIG_INT_ZERO,
            BIG_INT_ZERO
        );

        assertHigherOrderBaseProperties("Stream", id, flowUpdatedEvent);
        assert.fieldEquals("Stream", id, "currentFlowRate", flowUpdatedEvent.params.flowRate.toString());
        assert.fieldEquals("Stream", id, "deposit", deposit.toString());
        assert.fieldEquals("Stream", id, "streamedUntilUpdatedAt", streamedUntilUpdatedAt.toString());
        assert.fieldEquals("Stream", id, "token", flowUpdatedEvent.params.token.toHexString());
        assert.fieldEquals("Stream", id, "sender", flowUpdatedEvent.params.sender.toHexString());
        assert.fieldEquals("Stream", id, "receiver", flowUpdatedEvent.params.receiver.toHexString());
        assert.fieldEquals("Stream", id, "userData", flowUpdatedEvent.params.userData.toHexString());
    });

    test("handleFlowOperatorUpdated() - Should create a new FlowOperator entity", () => {
        const superToken = maticXAddress;
        const permissions = 1; // create only
        const flowRateAllowance = BigInt.fromI32(100);
        const allowance = BigInt.fromI32(0);
        const sender = alice;
        const flowOperator = bob;

        mockedApprove(superToken, sender, flowOperator, allowance);
        // Mocking is required here since it calls RPC inside getOrInitFlowOperator, when it is null.

        const flowOperatorUpdatedEvent = createFlowOperatorUpdatedEvent(
            superToken,
            sender,
            flowOperator,
            permissions,
            flowRateAllowance
        );

        handleFlowOperatorUpdated(flowOperatorUpdatedEvent);

        const id = getFlowOperatorID(
            Address.fromString(flowOperator),
            Address.fromString(superToken),
            Address.fromString(sender)
        );
        const atsId = getAccountTokenSnapshotID(Address.fromString(sender), Address.fromString(superToken));
        assertHigherOrderBaseProperties("FlowOperator", id, flowOperatorUpdatedEvent);
        assert.fieldEquals("FlowOperator", id, "permissions", permissions.toString());
        assert.fieldEquals("FlowOperator", id, "flowRateAllowanceGranted", flowRateAllowance.toString());
        assert.fieldEquals("FlowOperator", id, "flowRateAllowanceRemaining", flowRateAllowance.toString());
        assert.fieldEquals("FlowOperator", id, "flowOperator", flowOperator);
        assert.fieldEquals("FlowOperator", id, "allowance", allowance.toString());
        assert.fieldEquals("FlowOperator", id, "sender", sender);
        assert.fieldEquals("FlowOperator", id, "token", superToken);
        assert.fieldEquals("FlowOperator", id, "accountTokenSnapshot", atsId);
    });

    test("handleFlowUpdated() - Should update AccountTokenSnapshot totalStreamedInUntilUpdatedAt when time elapses", () => {
        // First, create an initial flow from alice to bob
        const flowRate = BigInt.fromI32(1000); // 1000 tokens per second
        const initialTimestamp = BigInt.fromI32(1000);
        const initialBlockNumber = BigInt.fromI32(100);
        
        // Create initial flow
        const deposit = getDeposit(flowRate);
        const firstFlowUpdatedEvent = createFlowUpdatedEventWithMocks(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            flowRate,           // flowRate
            BIG_INT_ZERO,       // previousSenderFlowRate
            BIG_INT_ZERO,       // previousReceiverFlowRate
            "initial flow",     // userData
            deposit,            // deposit
            BIG_INT_ZERO        // expectedOwedDeposit
        );
        
        // Override the timestamp and block number for the first event
        firstFlowUpdatedEvent.block.timestamp = initialTimestamp;
        firstFlowUpdatedEvent.block.number = initialBlockNumber;
        
        // Handle the first event
        handleFlowUpdated(firstFlowUpdatedEvent);
        
        // Get the receiver's AccountTokenSnapshot ID
        const receiverAtsId = getAccountTokenSnapshotID(
            Address.fromString(bob), 
            Address.fromString(maticXAddress)
        );
        
        // Assert initial totalStreamedInUntilUpdatedAt is 0
        assert.fieldEquals("AccountTokenSnapshot", receiverAtsId, "totalAmountStreamedInUntilUpdatedAt", "0");
        
        // Time passes - 100 seconds later
        const elapsedTime = BigInt.fromI32(100);
        const secondTimestamp = initialTimestamp.plus(elapsedTime);
        const secondBlockNumber = initialBlockNumber.plus(BigInt.fromI32(10));
        
        // Update the flow (increase flow rate)
        const newFlowRate = BigInt.fromI32(2000); // 2000 tokens per second
        const newDeposit = getDeposit(newFlowRate);
        const secondFlowUpdatedEvent = createFlowUpdatedEventWithMocks(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            newFlowRate,        // flowRate
            flowRate,           // previousSenderFlowRate
            flowRate,           // previousReceiverFlowRate
            "updated flow",     // userData
            newDeposit,         // deposit
            BIG_INT_ZERO        // expectedOwedDeposit
        );
        
        // Override the timestamp and block number for the second event
        secondFlowUpdatedEvent.block.timestamp = secondTimestamp;
        secondFlowUpdatedEvent.block.number = secondBlockNumber;
        
        // Handle the second event
        handleFlowUpdated(secondFlowUpdatedEvent);
        
        // Calculate expected totalStreamedIn: flowRate * elapsedTime = 1000 * 100 = 100000
        const expectedStreamedIn = flowRate.times(elapsedTime);
        
        // Assert totalStreamedInUntilUpdatedAt has increased
        assert.fieldEquals(
            "AccountTokenSnapshot", 
            receiverAtsId, 
            "totalAmountStreamedInUntilUpdatedAt", 
            expectedStreamedIn.toString()
        );
        
        // More time passes - another 50 seconds
        const additionalElapsedTime = BigInt.fromI32(50);
        const thirdTimestamp = secondTimestamp.plus(additionalElapsedTime);
        const thirdBlockNumber = secondBlockNumber.plus(BigInt.fromI32(5));
        
        // Delete the flow
        const thirdFlowUpdatedEvent = createFlowUpdatedEventWithMocks(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            BIG_INT_ZERO,       // flowRate (0 for delete)
            newFlowRate,        // previousSenderFlowRate
            newFlowRate,        // previousReceiverFlowRate
            "delete flow",      // userData
            BIG_INT_ZERO,       // deposit (0 for delete)
            BIG_INT_ZERO        // expectedOwedDeposit
        );
        
        // Override the timestamp and block number for the third event
        thirdFlowUpdatedEvent.block.timestamp = thirdTimestamp;
        thirdFlowUpdatedEvent.block.number = thirdBlockNumber;
        
        // Handle the third event
        handleFlowUpdated(thirdFlowUpdatedEvent);
        
        // Calculate new expected totalStreamedIn: 
        // previous (100000) + newFlowRate * additionalElapsedTime = 100000 + 2000 * 50 = 200000
        const newExpectedStreamedIn = expectedStreamedIn.plus(newFlowRate.times(additionalElapsedTime));
        
        // Assert totalStreamedInUntilUpdatedAt has increased further
        assert.fieldEquals(
            "AccountTokenSnapshot", 
            receiverAtsId, 
            "totalAmountStreamedInUntilUpdatedAt", 
            newExpectedStreamedIn.toString()
        );
    });


});

/**
 * Calculates the streamedUntilUpdatedAt.
 * @param streamedSoFar
 * @param currentTime
 * @param lastUpdatedAtTime
 * @param previousOutflowRate
 * @returns streamedUntilUpdatedAt at lastUpdatedAtTime timestamp
 */
function _getStreamedUntilUpdatedAt(
    streamedSoFar: BigInt,
    currentTime: BigInt,
    lastUpdatedAtTime: BigInt,
    previousOutflowRate: BigInt
): BigInt {
    return streamedSoFar.plus(previousOutflowRate.times(currentTime.minus(lastUpdatedAtTime)));
}
