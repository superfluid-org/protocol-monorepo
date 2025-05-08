import { handleMemberUnitsUpdated } from "../../src/mappings/superfluidPool";
import { createMemberUnitsUpdatedEvent } from "../gdav1/gdav1.helper";
import { Address, BigInt } from "@graphprotocol/graph-ts";
import { FAKE_INITIAL_BALANCE, alice, bob, charlie } from "../constants";
import { BIG_INT_ZERO, getPoolMemberID } from "../../src/utils";
import { assert, describe, test } from "matchstick-as";
import { mockedGetAppManifest, mockedRealtimeBalanceOf } from "../mockedFunctions";

describe("PoolMember not updating when units changed", () => {
    test("emit MemberUnitsUpdated event", () => {
        const superTokenAddress = alice;

        const poolAddress = Address.fromString(bob);
        const poolMemberAccountAddress = Address.fromString(charlie);
        const poolMemberId = getPoolMemberID(poolAddress, poolMemberAccountAddress);

        mockedGetAppManifest(poolMemberAccountAddress.toHexString(), false, false, BIG_INT_ZERO);
        
        // Initialize pool member for the first time
        const firstEvent = createMemberUnitsUpdatedEvent(
            superTokenAddress,
            poolMemberAccountAddress.toHexString(),
            BigInt.fromI32(0), // old units
            BigInt.fromI32(0) // new units
        );
        firstEvent.address = poolAddress;

        mockedRealtimeBalanceOf(
            superTokenAddress,
            poolMemberAccountAddress.toHexString(),
            firstEvent.block.timestamp,
            FAKE_INITIAL_BALANCE,
            BigInt.fromI32(0),
            BIG_INT_ZERO
        );

        handleMemberUnitsUpdated(firstEvent);
        // ---


        const newUnits = BigInt.fromI32(100);
        const blockNumber = BigInt.fromI32(200)
        const timestamp = BigInt.fromI32(300)

        const secondEvent = createMemberUnitsUpdatedEvent(
            superTokenAddress,
            poolMemberAccountAddress.toHexString(),
            BigInt.fromI32(0), // old units
            newUnits
        );
        secondEvent.block.timestamp = timestamp
        secondEvent.address = poolAddress;
        secondEvent.block.number = blockNumber;

        mockedRealtimeBalanceOf(
            superTokenAddress,
            poolMemberAccountAddress.toHexString(),
            secondEvent.block.timestamp,
            FAKE_INITIAL_BALANCE,
            BigInt.fromI32(0),
            BIG_INT_ZERO
        );
        
        // Act
        handleMemberUnitsUpdated(secondEvent);

        // Assert
        assert.fieldEquals(
            "PoolMember",
            poolMemberId,
            "units",
            newUnits.toString()
        );

        assert.fieldEquals(
            "PoolMember",
            poolMemberId,
            "updatedAtTimestamp",
            timestamp.toString()
        );

        assert.fieldEquals(
            "PoolMember",
            poolMemberId,
            "updatedAtBlockNumber",
            blockNumber.toString()
        );
    });
});
