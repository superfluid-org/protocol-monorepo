import { assert, beforeEach, clearStore, describe, test } from "matchstick-as";
import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts";
import { alice as alice_, bob as bob_, delta, echo, maticXAddress, superfluidPool } from "../constants";
import { getPoolMemberID } from "../../src/utils";
import { handleFlowDistributionUpdated, handleInstantDistributionUpdated, handlePoolCreated } from "../../src/mappings/gdav1";
import { createFlowDistributionUpdatedEvent, createInstantDistributionUpdatedEvent, createMemberUnitsUpdatedEvent, createPoolAndReturnPoolCreatedEvent } from "../gdav1/gdav1.helper";
import { mockedAppManifestAndRealtimeBalanceOf } from "../mockedFunctions";
import { handleMemberUnitsUpdated } from "../../src/mappings/superfluidPool";
import { Pool } from "../../generated/schema";

describe("PoolMember ending up with wrong `totalAmountReceivedUntilUpdatedAt`", () => {
    beforeEach(() => {
        clearStore();
    });

    /**
     * Problem description
        1. Create pool
        2. Add member A and update A units to 100
        3. Distribute 1000 tokens
        4. Add member B and update B units to 100
        5. Distribute 1000 tokens

        Expected result:
        member A 1500 tokens
        member B 500 tokens
    */
    test("create elaborate scenario with 2 instant distributions and 2 pool members", () => {
        const superTokenAddress = maticXAddress;
        const poolAdminAndDistributorAddress = Address.fromString(delta);
        const poolAddress = Address.fromString(superfluidPool);

        // # Arrange State 1
        // ## Arrange Pool
        const poolCreatedEvent = createPoolAndReturnPoolCreatedEvent(poolAdminAndDistributorAddress.toHexString(), superTokenAddress, poolAddress.toHexString());
        
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
        aliceCreatedEvent.block.timestamp = poolCreatedEvent.block.timestamp;

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, aliceAddress.toHexString(), aliceCreatedEvent.block.timestamp);
        handleMemberUnitsUpdated(aliceCreatedEvent);

        // # First distribution
        const firstDistributionEvent = createInstantDistributionUpdatedEvent(
            superTokenAddress,
            poolAddress.toHexString(),
            poolAdminAndDistributorAddress.toHexString(),
            echo,
            BigInt.fromI32(1000), // requested amount 
            BigInt.fromI32(1000), // actual amount
            Bytes.fromHexString("0x")
        );
        firstDistributionEvent.block.timestamp = poolCreatedEvent.block.timestamp;
        firstDistributionEvent.address = poolAddress;
            
        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, poolAdminAndDistributorAddress.toHexString(), firstDistributionEvent.block.timestamp);
        handleInstantDistributionUpdated(firstDistributionEvent);

        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "1000"
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
            "0"
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
        createBobEvent.block.timestamp = BigInt.fromI32(2);

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, bobAddress.toHexString(), createBobEvent.block.timestamp);
        handleMemberUnitsUpdated(createBobEvent);

        // # Second distribution
        const secondDistributionEvent = createInstantDistributionUpdatedEvent(
            superTokenAddress,
            poolAddress.toHexString(),
            poolAdminAndDistributorAddress.toHexString(),
            echo,
            BigInt.fromI32(1000), // requested amount 
            BigInt.fromI32(1000), // actual amount
            Bytes.fromHexString("0x")
        );
        secondDistributionEvent.block.timestamp = poolCreatedEvent.block.timestamp;
        secondDistributionEvent.address = poolAddress;
            
        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, poolAdminAndDistributorAddress.toHexString(), secondDistributionEvent.block.timestamp);
        handleInstantDistributionUpdated(secondDistributionEvent);

        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "2000"
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
            "0"
        );
        assert.fieldEquals(
            "PoolMember",
            bobId,
            "units",
            "100"
        );
        // ---

        // Arrange State 3
        // # Update PoolMember 2's units to get the `totalAmountReceivedUntilUpdatedAt`
        const updateBobEvent = createMemberUnitsUpdatedEvent(
            superTokenAddress,
            bobAddress.toHexString(),
            BigInt.fromI32(100), // old units
            BigInt.fromI32(100) // new units
        );
        // Note, the units can stay the same, we just want to trigger an update.
        updateBobEvent.address = poolAddress;
        updateBobEvent.block.timestamp = BigInt.fromI32(3);

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, bobAddress.toHexString(), updateBobEvent.block.timestamp);
        handleMemberUnitsUpdated(createBobEvent);

        assert.fieldEquals(
            "PoolMember",
            bobId,
            "totalAmountReceivedUntilUpdatedAt",
            "500"
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
        updateAliceEvent.block.timestamp = BigInt.fromI32(3);

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, aliceAddress.toHexString(), updateAliceEvent.block.timestamp);
        handleMemberUnitsUpdated(updateAliceEvent);

        assert.fieldEquals(
            "PoolMember",
            aliceId,
            "totalAmountReceivedUntilUpdatedAt",
            "1500"
        );
        assert.fieldEquals(
            "PoolMember",
            aliceId,
            "units",
            "100"
        );
    });
    /**
     * Problem description
        1. Create pool
        2. Add member A and update A units to 100
        3. Flow 1000 tokens (elapse 1 second)
        4. Add member B and update B units to 100
        5. Flow 1000 tokens (elapse 1 second)
        6. Update flow rate to 2000 tokens
        7. Flow 2000 tokens (elapse 1 second)

        Expected result:
        member A 2500 tokens
        member B 1500 tokens

        Actual result:
        member A 100 tokens
        member B 50 tokens
    */
    test("create elaborate scenario with 2 flowing distributions and 2 pool members", () => {
        const superTokenAddress = maticXAddress;
        const poolAdminAndDistributorAddress = Address.fromString(delta);
        const poolAddress = Address.fromString(superfluidPool);

        // # Arrange State 1
        // ## Arrange Pool
        const poolCreatedEvent = createPoolAndReturnPoolCreatedEvent(poolAdminAndDistributorAddress.toHexString(), superTokenAddress, poolAddress.toHexString());
        assert.stringEquals(poolCreatedEvent.block.timestamp.toString(), BigInt.fromI32(1).toString());

        handlePoolCreated(poolCreatedEvent);
        
        const pool = Pool.load(poolAddress.toHexString());

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
            BigInt.fromI32(1000), // newDistributorToPoolFlowRate
            BigInt.fromI32(1000), // newTotalDistributionFlowRate
            poolAdminAndDistributorAddress.toHexString(), // adjustmentFlowRecipient
            BigInt.fromI32(0),
            Bytes.fromHexString("0x")
        );
        firstFlowRateEvent.block.timestamp = poolCreatedEvent.block.timestamp; // 1
        firstFlowRateEvent.address = poolAddress;
            
        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, poolAdminAndDistributorAddress.toHexString(), firstFlowRateEvent.block.timestamp);
        handleFlowDistributionUpdated(firstFlowRateEvent);

        // # First flow rate
        if (pool) {
            pool.updatedAtTimestamp = firstFlowRateEvent.block.timestamp;
        }

        // TODO: This fails, how has this already flown???
        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "0" // nothing is flowed yet
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
            "0"
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
        createBobEvent.block.timestamp = BigInt.fromI32(2); // Skip 1 second to let it flow to Alice
        
        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, bobAddress.toHexString(), createBobEvent.block.timestamp);
        handleMemberUnitsUpdated(createBobEvent);

        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "1000"
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
            BigInt.fromI32(1000), // oldFlowRate
            BigInt.fromI32(2000), // newDistributorToPoolFlowRate
            BigInt.fromI32(2000), // newTotalDistributionFlowRate
            poolAdminAndDistributorAddress.toHexString(), // adjustmentFlowRecipient
            BigInt.fromI32(0),
            Bytes.fromHexString("0x")
        );
        secondFlowRateEvent.block.timestamp = BigInt.fromI32(3); // One second skipped, 2 seconds flown to Alice, 1 second to Bob
        secondFlowRateEvent.address = poolAddress;
            
        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, poolAdminAndDistributorAddress.toHexString(), secondFlowRateEvent.block.timestamp);
        handleFlowDistributionUpdated(secondFlowRateEvent);

        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "2000" // Only for first flow rate
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
            "0" // it's 500 if we query on-chain, but 0 here because update member units hasn't been called again since
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
            "0" // it's 1500 if we query on-chain, but 0 here because update member units hasn't been called again since
        );
        // ---

        // Arrange State 3
        // # Update PoolMember 2's units to get the `totalAmountReceivedUntilUpdatedAt`
        const updateBobEvent = createMemberUnitsUpdatedEvent(
            superTokenAddress,
            bobAddress.toHexString(),
            BigInt.fromI32(100), // old units
            BigInt.fromI32(100) // new units
        );
        // Note, the units can stay the same, we just want to trigger an update.
        updateBobEvent.address = poolAddress;
        updateBobEvent.block.timestamp = BigInt.fromI32(4); // 4 - 1 = 3 seconds of flow

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, bobAddress.toHexString(), updateBobEvent.block.timestamp);
        handleMemberUnitsUpdated(updateBobEvent);

        if (pool) {
            pool.updatedAtTimestamp = updateBobEvent.block.timestamp;
        }
        assert.fieldEquals(
            "Pool",
            poolAddress.toHexString(),
            "totalAmountDistributedUntilUpdatedAt",
            "4000"
        );
        assert.fieldEquals(
            "PoolMember",
            bobId,
            "totalAmountReceivedUntilUpdatedAt",
            "1500" // 50% of 2000
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
        updateAliceEvent.block.timestamp = updateBobEvent.block.timestamp; // 4

        mockedAppManifestAndRealtimeBalanceOf(superTokenAddress, aliceAddress.toHexString(), updateAliceEvent.block.timestamp);
        handleMemberUnitsUpdated(updateAliceEvent);

        if (pool) {
            pool.updatedAtTimestamp = updateAliceEvent.block.timestamp;
        }
        assert.fieldEquals(
            "PoolMember",
            aliceId,
            "totalAmountReceivedUntilUpdatedAt",
            "2500"
        );
        assert.fieldEquals(
            "PoolMember",
            aliceId,
            "units",
            "100"
        );
    })
});
 