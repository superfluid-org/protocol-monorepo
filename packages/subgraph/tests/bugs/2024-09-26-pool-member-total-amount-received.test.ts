import { assert, beforeEach, clearStore, describe, test, log } from "matchstick-as";
import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts";
import { alice as alice_, bob as bob_, delta, echo, maticXAddress, superfluidPool } from "../constants";
import { getPoolMemberID } from "../../src/utils";
import { handleFlowDistributionUpdated, handleInstantDistributionUpdated, handlePoolCreated } from "../../src/mappings/gdav1";
import { createFlowDistributionUpdatedEvent, createInstantDistributionUpdatedEvent, createMemberUnitsUpdatedEvent, createPoolAndReturnPoolCreatedEvent } from "../gdav1/gdav1.helper";
import { mockedAppManifestAndRealtimeBalanceOf } from "../mockedFunctions";
import { handleMemberUnitsUpdated } from "../../src/mappings/superfluidPool";
import { PoolMember } from "../../generated/schema";

describe("PoolMember ending up with wrong `totalAmountReceivedUntilUpdatedAt`", () => {
    beforeEach(() => {
        clearStore();
    });


    /**
     * Problem description
        1. Create pool
        2. Add member A and update A units to 100
        3. Flow 2000 tokens (elapse 1 second)
        4. Trigger A update
        5. Add member B and update B units to 100
        6. Flow 1000 tokens (elapse 1 second)
        7. Flow 0 tokens (elapse 1 second)

        Expected result:
        member A 2500 tokens
        member B 500 tokens
    */
    test("create elaborate scenario with 2 flowing distributions and 2 pool members (test syncedPerUnitFlowRate)", () => {
        const superTokenAddress = maticXAddress;
        const poolAdminAndDistributorAddress = Address.fromString(delta);
        const poolAddress = Address.fromString(superfluidPool);

        // # Arrange State 1
        // ## Arrange Pool
        const poolCreatedEvent = createPoolAndReturnPoolCreatedEvent(poolAdminAndDistributorAddress.toHexString(), superTokenAddress, poolAddress.toHexString());
        assert.stringEquals(poolCreatedEvent.block.timestamp.toString(), BigInt.fromI32(1).toString());

        handlePoolCreated(poolCreatedEvent);

        // ## Arrange PoolMember 1
        const aliceAddress = Address.fromString(alice_);
        const aliceId = getPoolMemberID(poolAddress, aliceAddress);
        const aliceCreatedEvent = createMemberUnitsUpdatedEvent(
            superTokenAddress,
            aliceAddress.toHexString(),
            BigInt.fromI32(0), // old units
            BigInt.fromI32(100) // new units
        );
        aliceCreatedEvent.address = poolAddress;
        aliceCreatedEvent.block.timestamp = poolCreatedEvent.block.timestamp; // 1

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, aliceAddress.toHexString(), aliceCreatedEvent.block.timestamp);
        handleMemberUnitsUpdated(aliceCreatedEvent);

        // # First flow rate
        const firstFlowRateEvent = createFlowDistributionUpdatedEvent(
            superTokenAddress,
            poolAddress.toHexString(),
            poolAdminAndDistributorAddress.toHexString(),
            echo,
            BigInt.fromI32(0), // oldFlowRate
            BigInt.fromI32(20000), // newDistributorToPoolFlowRate
            BigInt.fromI32(20000), // newTotalDistributionFlowRate
            poolAdminAndDistributorAddress.toHexString(), // adjustmentFlowRecipient
            BigInt.fromI32(0),
            Bytes.fromHexString("0x")
        );
        firstFlowRateEvent.block.timestamp = poolCreatedEvent.block.timestamp; // 1
        firstFlowRateEvent.address = poolAddress;

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, poolAdminAndDistributorAddress.toHexString(), firstFlowRateEvent.block.timestamp);
        handleFlowDistributionUpdated(firstFlowRateEvent);

        // # Trigger update
        const updateAliceUnitsEvent = createMemberUnitsUpdatedEvent(
            superTokenAddress,
            aliceAddress.toHexString(),
            BigInt.fromI32(100), // old units
            BigInt.fromI32(100) // new units
        )
        updateAliceUnitsEvent.address = poolAddress;
        updateAliceUnitsEvent.block.timestamp = BigInt.fromI32(2);

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, aliceAddress.toHexString(), updateAliceUnitsEvent.block.timestamp);
        handleMemberUnitsUpdated(updateAliceUnitsEvent);

        const alicePoolMember = PoolMember.load(aliceId)!;
        log.info(alicePoolMember.syncedPerUnitFlowRate.toString(), []);

        // # First flow rate
        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "20000" // nothing is flowed yet
        );
        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalUnits",
            "100"
        );
        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalMembers",
            "1"
        );
        assert.fieldEquals(
            "PoolMember",
            aliceId,
            "totalAmountReceivedUntilUpdatedAt",
            "20000"
        );
        assert.fieldEquals(
            "PoolMember",
            aliceId,
            "units",
            "100"
        );
        // --- 

        // # Arrange State 2
        // ## Arrange PoolMember 2 (new member)
        const bobAddress = Address.fromString(bob_);
        const bobId = getPoolMemberID(poolAddress, bobAddress);
        let createBobEvent = createMemberUnitsUpdatedEvent(
            superTokenAddress,
            bobAddress.toHexString(),
            BigInt.fromI32(0), // old units
            BigInt.fromI32(100) // new units
        );
        createBobEvent.address = poolAddress;
        createBobEvent.block.timestamp = BigInt.fromI32(3);

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, bobAddress.toHexString(), createBobEvent.block.timestamp);
        handleMemberUnitsUpdated(createBobEvent);

        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "40000"
        );
        assert.fieldEquals(
            "PoolMember",
            bobId,
            "totalAmountReceivedUntilUpdatedAt",
            "0" // Bob just joined, shouldn't have any received
        );

        // # Second flow rate
        const secondFlowRateEvent = createFlowDistributionUpdatedEvent(
            superTokenAddress,
            poolAddress.toHexString(),
            poolAdminAndDistributorAddress.toHexString(),
            echo,
            BigInt.fromI32(20000), // oldFlowRate
            BigInt.fromI32(0), // newDistributorToPoolFlowRate
            BigInt.fromI32(0), // newTotalDistributionFlowRate
            poolAdminAndDistributorAddress.toHexString(), // adjustmentFlowRecipient
            BigInt.fromI32(0),
            Bytes.fromHexString("0x")
        );
        secondFlowRateEvent.block.timestamp = BigInt.fromI32(3);
        secondFlowRateEvent.address = poolAddress;

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, poolAdminAndDistributorAddress.toHexString(), secondFlowRateEvent.block.timestamp);
        handleFlowDistributionUpdated(secondFlowRateEvent);

        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "40000" // Only for first flow rate
        );
        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalUnits",
            "200"
        );
        assert.fieldEquals(
            "PoolMember",
            bobId,
            "totalAmountReceivedUntilUpdatedAt",
            "0" // No update trigger for Bob
        );
        assert.fieldEquals(
            "PoolMember",
            bobId,
            "units",
            "100"
        );
        assert.fieldEquals(
            "PoolMember",
            aliceId,
            "totalAmountReceivedUntilUpdatedAt",
            "20000" // No additional update triggered for Alice
        );
        // ---

        // Arrange State 3
        // # Instant distribution
        const firstDistributionEvent = createInstantDistributionUpdatedEvent(
            superTokenAddress,
            poolAddress.toHexString(),
            poolAdminAndDistributorAddress.toHexString(),
            echo,
            BigInt.fromI32(3000), // requested amount 
            BigInt.fromI32(3000), // actual amount
            Bytes.fromHexString("0x")
        );
        firstDistributionEvent.block.timestamp = BigInt.fromI32(1000000); // Way in the future
        firstDistributionEvent.address = poolAddress;

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, poolAdminAndDistributorAddress.toHexString(), firstDistributionEvent.block.timestamp);
        handleInstantDistributionUpdated(firstDistributionEvent);

        // # Update PoolMember 2's units to get the `totalAmountReceivedUntilUpdatedAt`
        const updateBobEvent = createMemberUnitsUpdatedEvent(
            superTokenAddress,
            bobAddress.toHexString(),
            BigInt.fromI32(100), // old units
            BigInt.fromI32(100) // new units
        );
        // Note, the units can stay the same, we just want to trigger an update.
        updateBobEvent.address = poolAddress;
        updateBobEvent.block.timestamp = firstDistributionEvent.block.timestamp; // 1000000

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, bobAddress.toHexString(), updateBobEvent.block.timestamp);
        handleMemberUnitsUpdated(updateBobEvent);

        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "43000"
        );
        assert.fieldEquals(
            "PoolMember",
            bobId,
            "totalAmountReceivedUntilUpdatedAt",
            "1500"
        );
        assert.fieldEquals(
            "PoolMember",
            bobId,
            "units",
            "100"
        );

        // # Update PoolMember 1's units to get the `totalAmountReceivedUntilUpdatedAt`
        const updateAliceEvent = createMemberUnitsUpdatedEvent(
            superTokenAddress,
            aliceAddress.toHexString(),
            BigInt.fromI32(100), // old units
            BigInt.fromI32(100) // new units
        );
        // Note, the units can stay the same, we just want to trigger an update.
        updateAliceEvent.address = poolAddress;
        updateAliceEvent.block.timestamp = firstDistributionEvent.block.timestamp; // 1000000

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, aliceAddress.toHexString(), updateAliceEvent.block.timestamp);
        handleMemberUnitsUpdated(updateAliceEvent);

        assert.fieldEquals(
            "PoolMember",
            aliceId,
            "totalAmountReceivedUntilUpdatedAt",
            "41500"
        );
        assert.fieldEquals(
            "PoolMember",
            aliceId,
            "units",
            "100"
        );
    })
});
