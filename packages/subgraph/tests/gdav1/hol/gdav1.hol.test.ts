import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";
import { assert, beforeEach, clearStore, describe, test } from "matchstick-as/assembly/index";
import { BIG_INT_ONE, BIG_INT_ZERO, getPoolDistributorID, getPoolMemberID, ZERO_ADDRESS } from "../../../src/utils";
import { assertHigherOrderBaseProperties } from "../../assertionHelpers";
import { FALSE, TRUE, alice, bob, maticXAddress, superfluidPool } from "../../constants";
import {
    createBufferAdjustedEvent,
    createDistributionClaimedEvent,
    createFlowDistributionUpdatedEvent,
    createInstantDistributionUpdatedEvent,
    createMemberUnitsUpdatedEvent,
    createPoolAndReturnPoolCreatedEvent,
    updatePoolConnectionAndReturnPoolConnectionUpdatedEvent,
} from "../gdav1.helper";
import {
    handleBufferAdjusted,
    handleFlowDistributionUpdated,
    handleInstantDistributionUpdated,
} from "../../../src/mappings/gdav1";
import { updateMemberUnitsAndReturnMemberUnitsUpdatedEvent } from "../gdav1.helper";
import { handleDistributionClaimed, handleMemberUnitsUpdated } from "../../../src/mappings/superfluidPool";
import { getOrInitOrUpdatePoolMember } from "../../../src/mappingHelpers";
import { stringToBytes } from "../../converters";

const initialFlowRate = BigInt.fromI32(100);
const superToken = maticXAddress;
const admin = alice;

describe("GeneralDistributionAgreementV1 Higher Order Level Entity Unit Tests", () => {
    beforeEach(() => {
        clearStore();
    });

    test("handlePoolCreated() - Should create a new Pool entity (create)", () => {
        const poolCreatedEvent = createPoolAndReturnPoolCreatedEvent(admin, superToken, superfluidPool);

        const id = superfluidPool;
        assertEmptyPoolData(id, poolCreatedEvent, superToken);
    });

    test("handlePoolConnectionUpdated() - Non-Member (0 units) connection updated: Pool entity is unchanged", () => {
        createPoolAndReturnPoolCreatedEvent(admin, superToken, superfluidPool);

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

        const id = superfluidPool;
        assertEmptyPoolData(id, poolConnectionUpdatedEvent, superToken);
    });

    test("handlePoolConnectionUpdated() - Member (>0 units) connection updated: Pool entity changes", () => {
        const account = bob;
        const connected = true;
        const userData = stringToBytes("");

        const memberUnitsUpdatedEvent = updateMemberUnitsAndReturnMemberUnitsUpdatedEvent(
            superToken,
            account,
            BigInt.fromI32(0),
            BigInt.fromI32(1)
        );

        const poolConnectionUpdatedEvent = updatePoolConnectionAndReturnPoolConnectionUpdatedEvent(
            superToken,
            account,
            memberUnitsUpdatedEvent.address.toHexString(),
            connected,
            initialFlowRate,
            userData
        );

        const id = memberUnitsUpdatedEvent.address.toHexString();

        assertHigherOrderBaseProperties("Pool", id, poolConnectionUpdatedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handlePoolConnectionUpdated() - Pool Entity: Disconnected member connection updated", () => {
        const account = bob;
        const connected = false;
        const userData = stringToBytes("");

        const memberUnitsUpdatedEvent = updateMemberUnitsAndReturnMemberUnitsUpdatedEvent(
            superToken,
            account,
            BigInt.fromI32(0),
            BigInt.fromI32(1)
        );

        const poolConnectionUpdatedEvent = updatePoolConnectionAndReturnPoolConnectionUpdatedEvent(
            superToken,
            account,
            memberUnitsUpdatedEvent.address.toHexString(),
            connected,
            initialFlowRate,
            userData
        );

        const id = memberUnitsUpdatedEvent.address.toHexString();

        assertHigherOrderBaseProperties("Pool", id, poolConnectionUpdatedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handleBufferAdjusted() - Pool Entity: Total buffer value updated", () => {
        const distributor = alice;

        const BUFFER = BigInt.fromI32(100);

        const bufferAdjustedEvent = createBufferAdjustedEvent(
            superToken, // token
            superfluidPool, // pool
            distributor, // poolDistributor
            BUFFER, // bufferDelta
            BUFFER, // newBufferAmount
            BUFFER // totalBufferAmount
        );

        handleBufferAdjusted(bufferAdjustedEvent);

        const id = bufferAdjustedEvent.params.pool.toHexString();

        assertHigherOrderBaseProperties("Pool", id, bufferAdjustedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BUFFER.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handleFlowDistributionUpdated() - Pool Entity: flow related fields updated:", () => {
        const distributor = alice;
        const operator = alice;
        const emptyFlowRate = BigInt.fromI32(0);
        const newFlowRate = BigInt.fromI32(100000000);
        const userData = stringToBytes("");
        const flowDistributionUpdatedEvent = createFlowDistributionUpdatedEvent(
            superToken,
            superfluidPool,
            distributor,
            operator,
            emptyFlowRate, // old flow rate
            newFlowRate, // new distributor to pool flow rate
            newFlowRate, // new total distribution flow rate
            alice, // adjustment flow recipient
            BigInt.fromI32(0), // adjustment flow rate
            userData
        );

        handleFlowDistributionUpdated(flowDistributionUpdatedEvent);

        const id = flowDistributionUpdatedEvent.params.pool.toHexString();

        assertHigherOrderBaseProperties("Pool", id, flowDistributionUpdatedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", newFlowRate.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handleInstantDistributionUpdated() - Pool Entity: Total distributed amount updated:", () => {
        const distributor = alice;
        const operator = alice;
        const requestedAmount = BigInt.fromI32(100000000);
        const userData = stringToBytes("");
        const instantDistributionUpdatedEvent = createInstantDistributionUpdatedEvent(
            superToken,
            superfluidPool,
            distributor,
            operator,
            requestedAmount,
            requestedAmount,
            userData
        );

        handleInstantDistributionUpdated(instantDistributionUpdatedEvent);

        const id = instantDistributionUpdatedEvent.params.pool.toHexString();

        assertHigherOrderBaseProperties("Pool", id, instantDistributionUpdatedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", requestedAmount.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", requestedAmount.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handleDistributionClaimed() - Pool Entity: No changes", () => {
        const poolMember = alice;
        const claimedAmount = BigInt.fromI32(100000000);
        const distributionClaimedEvent = createDistributionClaimedEvent(
            superToken,
            poolMember,
            claimedAmount,
            claimedAmount
        );

        handleDistributionClaimed(distributionClaimedEvent);

        const id = distributionClaimedEvent.address.toHexString();

        assertHigherOrderBaseProperties("Pool", id, distributionClaimedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handleMemberUnitsUpdated() - Pool Entity: Units data updated (connected member) 0 to > 0 units", () => {
        const poolMember = alice;
        const oldUnits = BigInt.fromI32(0);
        const newUnits = BigInt.fromI32(100000000);
        const memberUnitsUpdatedEvent = createMemberUnitsUpdatedEvent(superToken, poolMember, oldUnits, newUnits);
        const poolMemberEntity = getOrInitOrUpdatePoolMember(
            memberUnitsUpdatedEvent,
            memberUnitsUpdatedEvent.address,
            Address.fromString(poolMember)
        );
        poolMemberEntity.isConnected = true;
        poolMemberEntity.save();

        handleMemberUnitsUpdated(memberUnitsUpdatedEvent);

        const id = memberUnitsUpdatedEvent.address.toHexString();

        assertHigherOrderBaseProperties("Pool", id, memberUnitsUpdatedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", newUnits.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", newUnits.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handleMemberUnitsUpdated() - Pool Entity: Units data updated (connected member) > 0 to 0 units", () => {
        const poolMember = alice;
        const oldUnits = BigInt.fromI32(0);
        const newUnits = BigInt.fromI32(100000000);
        const memberUnitsUpdatedEvent = createMemberUnitsUpdatedEvent(superToken, poolMember, oldUnits, newUnits);
        const poolMemberEntity = getOrInitOrUpdatePoolMember(
            memberUnitsUpdatedEvent,
            memberUnitsUpdatedEvent.address,
            Address.fromString(poolMember)
        );
        poolMemberEntity.isConnected = true;
        poolMemberEntity.save();

        handleMemberUnitsUpdated(memberUnitsUpdatedEvent);

        const memberUnitsUpdatedEventZeroUnits = createMemberUnitsUpdatedEvent(
            superToken,
            poolMember,
            newUnits,
            BIG_INT_ZERO
        );

        handleMemberUnitsUpdated(memberUnitsUpdatedEventZeroUnits);

        const id = memberUnitsUpdatedEvent.address.toHexString();

        assertHigherOrderBaseProperties("Pool", id, memberUnitsUpdatedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handleMemberUnitsUpdated() - Pool Entity: Units data updated (disconnected member) 0 to > 0 units", () => {
        const poolMember = alice;
        const oldUnits = BigInt.fromI32(0);
        const newUnits = BigInt.fromI32(100000000);
        const memberUnitsUpdatedEvent = createMemberUnitsUpdatedEvent(superToken, poolMember, oldUnits, newUnits);
        const poolMemberEntity = getOrInitOrUpdatePoolMember(
            memberUnitsUpdatedEvent,
            memberUnitsUpdatedEvent.address,
            Address.fromString(poolMember)
        );
        poolMemberEntity.save();

        handleMemberUnitsUpdated(memberUnitsUpdatedEvent);

        const id = memberUnitsUpdatedEvent.address.toHexString();

        assertHigherOrderBaseProperties("Pool", id, memberUnitsUpdatedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", newUnits.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", newUnits.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ONE.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handleMemberUnitsUpdated() - Pool Entity: Units data updated (connected member) > 0 to 0 units", () => {
        const poolMember = alice;
        const oldUnits = BigInt.fromI32(0);
        const newUnits = BigInt.fromI32(100000000);
        const memberUnitsUpdatedEvent = createMemberUnitsUpdatedEvent(superToken, poolMember, oldUnits, newUnits);
        const poolMemberEntity = getOrInitOrUpdatePoolMember(
            memberUnitsUpdatedEvent,
            memberUnitsUpdatedEvent.address,
            Address.fromString(poolMember)
        );
        poolMemberEntity.save();

        handleMemberUnitsUpdated(memberUnitsUpdatedEvent);

        const memberUnitsUpdatedEventZeroUnits = createMemberUnitsUpdatedEvent(
            superToken,
            poolMember,
            newUnits,
            BIG_INT_ZERO
        );

        handleMemberUnitsUpdated(memberUnitsUpdatedEventZeroUnits);

        const id = memberUnitsUpdatedEvent.address.toHexString();

        assertHigherOrderBaseProperties("Pool", id, memberUnitsUpdatedEvent);
        assert.fieldEquals("Pool", id, "totalUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("Pool", id, "token", ZERO_ADDRESS.toHex());
        assert.fieldEquals("Pool", id, "admin", ZERO_ADDRESS.toHex());
    });

    test("handlePoolConnectionUpdated - PoolMember Entity: isConnected updated from false to true", () => {
        const account = bob;
        const connected = true;
        const oldUnits = BigInt.fromI32(0);
        const newUnits = BigInt.fromI32(1);
        const userData = stringToBytes("");

        const memberUnitsUpdatedEvent = updateMemberUnitsAndReturnMemberUnitsUpdatedEvent(
            superToken,
            account,
            oldUnits,
            newUnits
        );

        const poolAddress = memberUnitsUpdatedEvent.address;

        const poolConnectionUpdatedEvent = updatePoolConnectionAndReturnPoolConnectionUpdatedEvent(
            superToken,
            account,
            poolAddress.toHexString(),
            connected,
            initialFlowRate,
            userData
        );
        const id = getPoolMemberID(poolAddress, Address.fromString(account));

        assertHigherOrderBaseProperties("PoolMember", id, poolConnectionUpdatedEvent);
        assert.fieldEquals("PoolMember", id, "units", newUnits.toString());
        assert.fieldEquals("PoolMember", id, "isConnected", TRUE);
        assert.fieldEquals("PoolMember", id, "totalAmountClaimed", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolMember", id, "account", account);
        assert.fieldEquals("PoolMember", id, "pool", poolAddress.toHexString());
    });

    test("handlePoolConnectionUpdated - PoolMember Entity: isConnected updated from true to false", () => {
        const account = bob;
        const connected = true;
        const oldUnits = BigInt.fromI32(0);
        const newUnits = BigInt.fromI32(1);
        const userData = stringToBytes("");

        const memberUnitsUpdatedEvent = updateMemberUnitsAndReturnMemberUnitsUpdatedEvent(
            superToken,
            account,
            oldUnits,
            newUnits
        );

        const poolAddress = memberUnitsUpdatedEvent.address;

        const poolConnectionUpdatedEvent = updatePoolConnectionAndReturnPoolConnectionUpdatedEvent(
            superToken,
            account,
            poolAddress.toHexString(),
            connected,
            initialFlowRate,
            userData
        );

        updatePoolConnectionAndReturnPoolConnectionUpdatedEvent(
            superToken,
            account,
            poolAddress.toHexString(),
            false,
            initialFlowRate,
            userData
        );
        const id = getPoolMemberID(poolAddress, Address.fromString(account));

        assertHigherOrderBaseProperties("PoolMember", id, poolConnectionUpdatedEvent);
        assert.fieldEquals("PoolMember", id, "units", newUnits.toString());
        assert.fieldEquals("PoolMember", id, "isConnected", FALSE);
        assert.fieldEquals("PoolMember", id, "totalAmountClaimed", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolMember", id, "account", account);
        assert.fieldEquals("PoolMember", id, "pool", poolAddress.toHexString());
    });

    test("handleDistributionClaimed() - PoolMember Entity: totalAmountClaimed updated", () => {
        const poolMember = alice;
        const claimedAmount = BigInt.fromI32(100000000);
        const distributionClaimedEvent = createDistributionClaimedEvent(
            superToken,
            poolMember,
            claimedAmount,
            claimedAmount
        );

        const poolAddress = distributionClaimedEvent.address;

        handleDistributionClaimed(distributionClaimedEvent);

        const id = getPoolMemberID(poolAddress, Address.fromString(poolMember));

        assertHigherOrderBaseProperties("PoolMember", id, distributionClaimedEvent);
        assert.fieldEquals("PoolMember", id, "units", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolMember", id, "isConnected", FALSE);
        assert.fieldEquals("PoolMember", id, "totalAmountClaimed", claimedAmount.toString());
        assert.fieldEquals("PoolMember", id, "account", poolMember);
        assert.fieldEquals("PoolMember", id, "pool", poolAddress.toHexString());
    });

    test("handleMemberUnitsUpdated() - PoolMember Entity: units updated", () => {
        const poolMember = alice;
        const oldUnits = BigInt.fromI32(0);
        const newUnits = BigInt.fromI32(100000000);
        const memberUnitsUpdatedEvent = createMemberUnitsUpdatedEvent(superToken, poolMember, oldUnits, newUnits);

        const poolAddress = memberUnitsUpdatedEvent.address;

        handleMemberUnitsUpdated(memberUnitsUpdatedEvent);

        const id = getPoolMemberID(poolAddress, Address.fromString(poolMember));

        assertHigherOrderBaseProperties("PoolMember", id, memberUnitsUpdatedEvent);
        assert.fieldEquals("PoolMember", id, "units", newUnits.toString());
        assert.fieldEquals("PoolMember", id, "isConnected", FALSE);
        assert.fieldEquals("PoolMember", id, "totalAmountClaimed", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolMember", id, "account", poolMember);
        assert.fieldEquals("PoolMember", id, "pool", poolAddress.toHexString());
    });

    test("handleBufferAdjusted() - PoolDistributor Entity: totalBufferAmount updated", () => {
        const distributor = alice;

        const BUFFER = BigInt.fromI32(100);

        const bufferAdjustedEvent = createBufferAdjustedEvent(
            superToken, // token
            superfluidPool, // pool
            distributor, // poolDistributor
            BUFFER, // bufferDelta
            BUFFER, // newBufferAmount
            BUFFER // totalBufferAmount
        );

        handleBufferAdjusted(bufferAdjustedEvent);

        const id = getPoolDistributorID(Address.fromString(superfluidPool), Address.fromString(distributor));

        assertHigherOrderBaseProperties("PoolDistributor", id, bufferAdjustedEvent);
        assert.fieldEquals(
            "PoolDistributor",
            id,
            "totalAmountInstantlyDistributedUntilUpdatedAt",
            BIG_INT_ZERO.toString()
        );
        assert.fieldEquals(
            "PoolDistributor",
            id,
            "totalAmountFlowedDistributedUntilUpdatedAt",
            BIG_INT_ZERO.toString()
        );
        assert.fieldEquals("PoolDistributor", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolDistributor", id, "totalBuffer", BUFFER.toString());
        assert.fieldEquals("PoolDistributor", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolDistributor", id, "account", distributor);
        assert.fieldEquals("PoolDistributor", id, "pool", superfluidPool);
    });

    test("handleFlowDistributionUpdated() - PoolDistributor Entity: flowRate updated", () => {
        const distributor = alice;
        const operator = alice;
        const emptyFlowRate = BigInt.fromI32(0);
        const newFlowRate = BigInt.fromI32(100000000);
        const userData = stringToBytes("");
        const flowDistributionUpdatedEvent = createFlowDistributionUpdatedEvent(
            superToken,
            superfluidPool,
            distributor,
            operator,
            emptyFlowRate, // old flow rate
            newFlowRate, // new distributor to pool flow rate
            newFlowRate, // new total distribution flow rate
            alice, // adjustment flow recipient
            BigInt.fromI32(0), // adjustment flow rate
            userData
        );

        handleFlowDistributionUpdated(flowDistributionUpdatedEvent);

        const id = getPoolDistributorID(Address.fromString(superfluidPool), Address.fromString(distributor));

        assertHigherOrderBaseProperties("PoolDistributor", id, flowDistributionUpdatedEvent);
        assert.fieldEquals(
            "PoolDistributor",
            id,
            "totalAmountInstantlyDistributedUntilUpdatedAt",
            BIG_INT_ZERO.toString()
        );
        assert.fieldEquals(
            "PoolDistributor",
            id,
            "totalAmountFlowedDistributedUntilUpdatedAt",
            BIG_INT_ZERO.toString()
        );
        assert.fieldEquals("PoolDistributor", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolDistributor", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolDistributor", id, "flowRate", newFlowRate.toString());
        assert.fieldEquals("PoolDistributor", id, "account", distributor);
        assert.fieldEquals("PoolDistributor", id, "pool", superfluidPool);
    });

    test("handleInstantDistributionUpdated() - PoolDistributor Entity: flowRate updated", () => {
        const distributor = alice;
        const operator = alice;
        const requestedAmount = BigInt.fromI32(100000000);
        const userData = stringToBytes("");
        const instantDistributionUpdatedEvent = createInstantDistributionUpdatedEvent(
            superToken,
            superfluidPool,
            distributor,
            operator,
            requestedAmount,
            requestedAmount,
            userData
        );

        handleInstantDistributionUpdated(instantDistributionUpdatedEvent);

        const id = getPoolDistributorID(Address.fromString(superfluidPool), Address.fromString(distributor));

        assertHigherOrderBaseProperties("PoolDistributor", id, instantDistributionUpdatedEvent);
        assert.fieldEquals(
            "PoolDistributor",
            id,
            "totalAmountInstantlyDistributedUntilUpdatedAt",
            requestedAmount.toString()
        );
        assert.fieldEquals(
            "PoolDistributor",
            id,
            "totalAmountFlowedDistributedUntilUpdatedAt",
            BIG_INT_ZERO.toString()
        );
        assert.fieldEquals("PoolDistributor", id, "totalAmountDistributedUntilUpdatedAt", requestedAmount.toString());
        assert.fieldEquals("PoolDistributor", id, "totalBuffer", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolDistributor", id, "flowRate", BIG_INT_ZERO.toString());
        assert.fieldEquals("PoolDistributor", id, "account", distributor);
        assert.fieldEquals("PoolDistributor", id, "pool", superfluidPool);
    });
});

function assertEmptyPoolData(id: string, event: ethereum.Event, token: string): void {
    assertHigherOrderBaseProperties("Pool", id, event);
    assert.fieldEquals("Pool", id, "totalUnits", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "totalConnectedUnits", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "totalDisconnectedUnits", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "totalAmountInstantlyDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "totalAmountFlowedDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "totalAmountDistributedUntilUpdatedAt", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "totalMembers", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "totalConnectedMembers", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "totalDisconnectedMembers", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "adjustmentFlowRate", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "flowRate", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "totalBuffer", BIG_INT_ZERO.toString());
    assert.fieldEquals("Pool", id, "token", token);
    assert.fieldEquals("Pool", id, "admin", admin);
}
