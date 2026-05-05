/**
 * Issue: https://github.com/superfluid-org/protocol-monorepo/issues/2155
 *
 * AccountTokenSnapshot.totalGDADeposit (and totalDeposit) can be 0 in the subgraph
 * when the account actually has nonzero GDA buffer on-chain.
 *
 * Root cause: handleBufferAdjusted updates TokenStatistic.totalGDADeposit but does
 * NOT update AccountTokenSnapshot.totalGDADeposit for the pool distributor (from).
 */
import { BigInt } from "@graphprotocol/graph-ts";
import { assert, beforeEach, clearStore, describe, test } from "matchstick-as/assembly/index";
import { handleBufferAdjusted } from "../../src/mappings/gdav1";
import { createBufferAdjustedEvent, createPoolAndReturnPoolCreatedEvent } from "../gdav1/gdav1.helper";
import { alice, maticXAddress, superfluidPool } from "../constants";
import { BIG_INT_ZERO } from "../../src/utils";

describe("Issue 2155: AccountTokenSnapshot totalGDADeposit on BufferAdjusted", () => {
    beforeEach(() => {
        clearStore();
    });

    test("handleBufferAdjusted() should update account and token deposits for the pool distributor", () => {
        // Create pool with alice as admin so AccountTokenSnapshot exists for alice
        createPoolAndReturnPoolCreatedEvent(alice, maticXAddress, superfluidPool, BIG_INT_ZERO);

        const bufferDelta = BigInt.fromI32(526847904); // e.g. 526e9 wei
        const newBufferAmount = bufferDelta;
        const totalBufferAmount = bufferDelta;
        const poolDistributor = alice;

        const bufferAdjustedEvent = createBufferAdjustedEvent(
            maticXAddress,
            superfluidPool,
            poolDistributor,
            bufferDelta,
            newBufferAmount,
            totalBufferAmount
        );

        handleBufferAdjusted(bufferAdjustedEvent);

        const accountTokenSnapshotId = poolDistributor + "-" + maticXAddress;
        assert.fieldEquals(
            "TokenStatistic",
            maticXAddress,
            "totalGDADeposit",
            bufferDelta.toString()
        );
        assert.fieldEquals(
            "TokenStatistic",
            maticXAddress,
            "totalDeposit",
            bufferDelta.toString()
        );
        assert.fieldEquals(
            "AccountTokenSnapshot",
            accountTokenSnapshotId,
            "totalGDADeposit",
            bufferDelta.toString()
        );
        assert.fieldEquals(
            "AccountTokenSnapshot",
            accountTokenSnapshotId,
            "totalDeposit",
            bufferDelta.toString()
        );
    });

    test("handleBufferAdjusted() should decrement account and token deposits when buffer shrinks", () => {
        createPoolAndReturnPoolCreatedEvent(alice, maticXAddress, superfluidPool, BIG_INT_ZERO);

        const poolDistributor = alice;
        const depositAmount = BigInt.fromI32(526847904);
        const withdrawAmount = BigInt.fromI32(-526847904);

        handleBufferAdjusted(
            createBufferAdjustedEvent(
                maticXAddress,
                superfluidPool,
                poolDistributor,
                depositAmount,
                depositAmount,
                depositAmount
            )
        );
        handleBufferAdjusted(
            createBufferAdjustedEvent(
                maticXAddress,
                superfluidPool,
                poolDistributor,
                withdrawAmount,
                BIG_INT_ZERO,
                BIG_INT_ZERO
            )
        );

        const accountTokenSnapshotId = poolDistributor + "-" + maticXAddress;
        assert.fieldEquals("TokenStatistic", maticXAddress, "totalGDADeposit", "0");
        assert.fieldEquals("TokenStatistic", maticXAddress, "totalDeposit", "0");
        assert.fieldEquals(
            "AccountTokenSnapshot",
            accountTokenSnapshotId,
            "totalGDADeposit",
            "0"
        );
        assert.fieldEquals(
            "AccountTokenSnapshot",
            accountTokenSnapshotId,
            "totalDeposit",
            "0"
        );
    });
});
