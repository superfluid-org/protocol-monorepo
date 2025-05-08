import { Address, BigInt } from "@graphprotocol/graph-ts";
import { assert, beforeEach, clearStore, describe, test } from "matchstick-as/assembly/index";
import {
    handleBufferAdjusted,
    handleFlowDistributionUpdated,
    handleInstantDistributionUpdated,
} from "../../../src/mappings/gdav1";
import { handleDistributionClaimed } from "../../../src/mappings/superfluidPool";
import { BIG_INT_ZERO, getPoolDistributorID, getPoolMemberID } from "../../../src/utils";
import { assertEventBaseProperties } from "../../assertionHelpers";
import { FAKE_INITIAL_BALANCE, FALSE, TRUE, alice, bob, maticXAddress, superfluidPool } from "../../constants";
import {
    createBufferAdjustedEvent,
    createDistributionClaimedEvent,
    createFlowDistributionUpdatedEvent,
    createInstantDistributionUpdatedEvent,
    createPoolAndReturnPoolCreatedEvent
} from "../gdav1.helper";
import { mockedGetAppManifest, mockedRealtimeBalanceOf } from "../../mockedFunctions";
import { updatePoolConnectionAndReturnPoolConnectionUpdatedEvent } from "../gdav1.helper";
import { updateMemberUnitsAndReturnMemberUnitsUpdatedEvent } from "../gdav1.helper";
import { stringToBytes } from "../../converters";
import { AccountTokenSnapshot } from "../../../generated/schema";

const initialFlowRate = BigInt.fromI32(100);
const superToken = maticXAddress;

describe("GeneralDistributionAgreementV1 Event Entity Unit Tests", () => {
    beforeEach(() => {
        clearStore();
    });

    test("handlePoolCreated() - Should create a new PoolCreatedEvent entity", () => {
        const admin = bob;
        const accountTokenSnapshotId = admin + "-" + superToken;

        // Act
        const poolCreatedEvent = createPoolAndReturnPoolCreatedEvent(admin, superToken, superfluidPool);

        // Assert
        const id = assertEventBaseProperties(poolCreatedEvent, "PoolCreated");
        assert.fieldEquals("PoolCreatedEvent", id, "token", superToken);
        assert.fieldEquals("PoolCreatedEvent", id, "caller", poolCreatedEvent.transaction.from.toHexString());
        assert.fieldEquals("PoolCreatedEvent", id, "admin", admin);
        assert.fieldEquals("PoolCreatedEvent", id, "pool", superfluidPool);

        assert.fieldEquals("AccountTokenSnapshot", accountTokenSnapshotId, "adminOfPoolCount", BigInt.fromI32(1).toString());
    });

    test("handlePoolConnectionUpdated() - Should create a new handlePoolConnectionUpdatedEvent entity (connected)", () => {
        const account = bob;
        const connected = true;
        const userData = stringToBytes("");

        const poolConnectionUpdatedEvent = updatePoolConnectionAndReturnPoolConnectionUpdatedEvent(
            superToken,
            account,
            superfluidPool,
            connected,
            initialFlowRate,
            userData
        );

        const poolMemberId = getPoolMemberID(Address.fromString(superfluidPool), Address.fromString(account));

        const id = assertEventBaseProperties(poolConnectionUpdatedEvent, "PoolConnectionUpdated");
        assert.fieldEquals("PoolConnectionUpdatedEvent", id, "token", superToken);
        assert.fieldEquals("PoolConnectionUpdatedEvent", id, "connected", TRUE);
        assert.fieldEquals("PoolConnectionUpdatedEvent", id, "pool", superfluidPool);
        assert.fieldEquals("PoolConnectionUpdatedEvent", id, "poolMember", poolMemberId);
    });

    test("handlePoolConnectionUpdated() - Should create a new handlePoolConnectionUpdatedEvent entity (disconnected)", () => {
        const account = bob;
        const connected = false;
        const userData = stringToBytes("");

        const poolConnectionUpdatedEvent = updatePoolConnectionAndReturnPoolConnectionUpdatedEvent(
            superToken,
            account,
            superfluidPool,
            connected,
            initialFlowRate,
            userData
        );

        const poolMemberId = getPoolMemberID(Address.fromString(superfluidPool), Address.fromString(account));

        const id = assertEventBaseProperties(poolConnectionUpdatedEvent, "PoolConnectionUpdated");
        assert.fieldEquals("PoolConnectionUpdatedEvent", id, "token", superToken);
        assert.fieldEquals("PoolConnectionUpdatedEvent", id, "connected", FALSE);
        assert.fieldEquals("PoolConnectionUpdatedEvent", id, "pool", superfluidPool);
        assert.fieldEquals("PoolConnectionUpdatedEvent", id, "poolMember", poolMemberId);
    });

    test("handleBufferAdjusted() - Should create a new handleBufferAdjustedEvent entity", () => {
        const bufferDelta = BigInt.fromI32(69);
        const newBufferAmount = BigInt.fromI32(420);
        const totalBufferAmount = BigInt.fromI32(42069);
        const poolDistributor = alice;

        const bufferAdjustedEvent = createBufferAdjustedEvent(
            maticXAddress,
            superfluidPool,
            poolDistributor,
            bufferDelta,
            newBufferAmount,
            totalBufferAmount
        );

        const poolDistributorId = getPoolDistributorID(
            Address.fromString(superfluidPool),
            Address.fromString(poolDistributor)
        );

        handleBufferAdjusted(bufferAdjustedEvent);

        const id = assertEventBaseProperties(bufferAdjustedEvent, "BufferAdjusted");
        assert.fieldEquals("BufferAdjustedEvent", id, "token", maticXAddress);
        assert.fieldEquals("BufferAdjustedEvent", id, "pool", superfluidPool);
        assert.fieldEquals("BufferAdjustedEvent", id, "poolDistributor", poolDistributorId.toString());
        assert.fieldEquals("BufferAdjustedEvent", id, "bufferDelta", bufferDelta.toString());
        assert.fieldEquals("BufferAdjustedEvent", id, "newBufferAmount", newBufferAmount.toString());
        assert.fieldEquals("BufferAdjustedEvent", id, "totalBufferAmount", totalBufferAmount.toString());
    });

    test("handleInstantDistributionUpdated() - Should create a new handleInstantDistributionUpdatedEvent entity", () => {
        const operator = alice;
        const requestedAmount = BigInt.fromI32(69);
        const actualAmount = BigInt.fromI32(70);
        const poolDistributor = bob;
        const userData = stringToBytes("");

        const instantDistributionUpdatedEvent = createInstantDistributionUpdatedEvent(
            superToken,
            superfluidPool,
            poolDistributor,
            operator,
            requestedAmount,
            actualAmount,
            userData
        );

        const poolDistributorId = getPoolDistributorID(
            Address.fromString(superfluidPool),
            Address.fromString(poolDistributor)
        );

        handleInstantDistributionUpdated(instantDistributionUpdatedEvent);

        const id = assertEventBaseProperties(instantDistributionUpdatedEvent, "InstantDistributionUpdated");
        assert.fieldEquals("InstantDistributionUpdatedEvent", id, "token", superToken);
        assert.fieldEquals("InstantDistributionUpdatedEvent", id, "pool", superfluidPool);
        assert.fieldEquals("InstantDistributionUpdatedEvent", id, "poolDistributor", poolDistributorId.toString());
        assert.fieldEquals("InstantDistributionUpdatedEvent", id, "operator", operator);
        assert.fieldEquals("InstantDistributionUpdatedEvent", id, "requestedAmount", requestedAmount.toString());
        assert.fieldEquals("InstantDistributionUpdatedEvent", id, "actualAmount", actualAmount.toString());
    });

    test("handleFlowDistributionUpdated() - Should create a new handleFlowDistributionUpdatedEvent entity", () => {
        const operator = alice;
        const oldFlowRate = BigInt.fromI32(69);
        const newDistributorToPoolFlowRate = BigInt.fromI32(420);
        const newTotalDistributionFlowRate = BigInt.fromI32(42069);
        const adjustmentFlowRecipient = alice;
        const adjustmentFlowRate = BigInt.fromI32(5);
        const poolDistributor = bob;
        const userData = stringToBytes("");

        const flowDistributionUpdatedEvent = createFlowDistributionUpdatedEvent(
            superToken,
            superfluidPool,
            poolDistributor,
            operator,
            oldFlowRate,
            newDistributorToPoolFlowRate,
            newTotalDistributionFlowRate,
            adjustmentFlowRecipient,
            adjustmentFlowRate,
            userData
        );

        const poolDistributorId = getPoolDistributorID(
            Address.fromString(superfluidPool),
            Address.fromString(poolDistributor)
        );

        handleFlowDistributionUpdated(flowDistributionUpdatedEvent);

        const id = assertEventBaseProperties(flowDistributionUpdatedEvent, "FlowDistributionUpdated");
        assert.fieldEquals("FlowDistributionUpdatedEvent", id, "token", superToken);
        assert.fieldEquals("FlowDistributionUpdatedEvent", id, "pool", superfluidPool);
        assert.fieldEquals("FlowDistributionUpdatedEvent", id, "poolDistributor", poolDistributorId.toString());
        assert.fieldEquals("FlowDistributionUpdatedEvent", id, "operator", operator);
        assert.fieldEquals("FlowDistributionUpdatedEvent", id, "oldFlowRate", oldFlowRate.toString());
        assert.fieldEquals(
            "FlowDistributionUpdatedEvent",
            id,
            "newDistributorToPoolFlowRate",
            newDistributorToPoolFlowRate.toString()
        );
        assert.fieldEquals(
            "FlowDistributionUpdatedEvent",
            id,
            "newTotalDistributionFlowRate",
            newTotalDistributionFlowRate.toString()
        );
        assert.fieldEquals("FlowDistributionUpdatedEvent", id, "adjustmentFlowRecipient", adjustmentFlowRecipient);
        assert.fieldEquals("FlowDistributionUpdatedEvent", id, "adjustmentFlowRate", adjustmentFlowRate.toString());
    });

    test("handleDistributionClaimed() - Should create a new DistributionClaimedEvent entity", () => {
        const poolMember = alice;
        const claimedAmount = BigInt.fromI32(69);
        const totalClaimed = BigInt.fromI32(420);

        const distributionClaimedEvent = createDistributionClaimedEvent(
            superToken,
            poolMember,
            claimedAmount,
            totalClaimed
        );

        // getOrInitAccountTokenSnapshot(event) => getOrInitAccount(account) => host.try_getAppManifest(account)
        mockedGetAppManifest(poolMember, false, false, BIG_INT_ZERO);

        // updateATSStreamedAndBalanceUntilUpdatedAt => updateATSBalanceAndUpdatedAt => try_realtimeBalanceOf(poolMember)
        mockedRealtimeBalanceOf(
            superToken,
            poolMember,
            distributionClaimedEvent.block.timestamp,
            FAKE_INITIAL_BALANCE.plus(initialFlowRate),
            initialFlowRate,
            BIG_INT_ZERO
        );

        const poolMemberId = getPoolMemberID(distributionClaimedEvent.address, Address.fromString(poolMember));

        handleDistributionClaimed(distributionClaimedEvent);

        const id = assertEventBaseProperties(distributionClaimedEvent, "DistributionClaimed");
        assert.fieldEquals("DistributionClaimedEvent", id, "token", superToken);
        assert.fieldEquals("DistributionClaimedEvent", id, "claimedAmount", claimedAmount.toString());
        assert.fieldEquals("DistributionClaimedEvent", id, "totalClaimed", totalClaimed.toString());
        assert.fieldEquals("DistributionClaimedEvent", id, "poolMember", poolMemberId.toString());
    });

    test("handleMemberUnitsUpdated() - Should create a new MemberUnitsUpdatedEvent entity", () => {
        const oldUnits = BigInt.fromI32(0);
        const newUnits = BigInt.fromI32(69);
        const poolMember = bob;

        const memberUnitsUpdatedEvent = updateMemberUnitsAndReturnMemberUnitsUpdatedEvent(
            superToken,
            poolMember,
            oldUnits,
            newUnits
        );

        const poolMemberId = getPoolMemberID(memberUnitsUpdatedEvent.address, Address.fromString(poolMember));

        const id = assertEventBaseProperties(memberUnitsUpdatedEvent, "MemberUnitsUpdated");
        assert.fieldEquals("MemberUnitsUpdatedEvent", id, "token", superToken);
        assert.fieldEquals("MemberUnitsUpdatedEvent", id, "poolMember", poolMemberId.toString());
        assert.fieldEquals("MemberUnitsUpdatedEvent", id, "units", newUnits.toString());
    });
});
