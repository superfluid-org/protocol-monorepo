import { newMockEvent } from "matchstick-as";
import {
    BufferAdjusted,
    FlowDistributionUpdated,
    InstantDistributionUpdated,
    PoolConnectionUpdated,
    PoolCreated,
} from "../../generated/GeneralDistributionAgreementV1/IGeneralDistributionAgreementV1";
import {
    DistributionClaimed,
    MemberUnitsUpdated,
} from "../../generated/GeneralDistributionAgreementV1/ISuperfluidPool";
import {
    getAddressEventParam,
    getBigIntEventParam,
    getBooleanEventParam,
    getBytesEventParam,
    getSignedBigIntEventParam,
} from "../converters";
import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { handlePoolConnectionUpdated, handlePoolCreated } from "../../src/mappings/gdav1";
import { BIG_INT_ZERO } from "../../src/utils";
import { FAKE_INITIAL_BALANCE } from "../constants";
import { mockedGetAppManifest, mockedRealtimeBalanceOf } from "../mockedFunctions";
import { handleMemberUnitsUpdated } from "../../src/mappings/superfluidPool";

export function createPoolAndReturnPoolCreatedEvent(
    admin: string,
    superToken: string,
    superfluidPool: string,
    initialFlowRate: BigInt = BIG_INT_ZERO
): PoolCreated {
    const poolCreatedEvent = createPoolCreatedEvent(superToken, admin, superfluidPool);

    // getOrInitAccountTokenSnapshot(event) => getOrInitAccount(admin) => host.try_getAppManifest(admin)
    mockedGetAppManifest(admin, false, false, BIG_INT_ZERO);

    // updateATSStreamedAndBalanceUntilUpdatedAt => updateATSBalanceAndUpdatedAt => try_realtimeBalanceOf(admin)
    mockedRealtimeBalanceOf(
        superToken,
        admin,
        poolCreatedEvent.block.timestamp,
        FAKE_INITIAL_BALANCE.plus(initialFlowRate),
        initialFlowRate,
        BIG_INT_ZERO
    );

    handlePoolCreated(poolCreatedEvent);
    return poolCreatedEvent;
}

export function updatePoolConnectionAndReturnPoolConnectionUpdatedEvent(
    superToken: string,
    account: string,
    superfluidPool: string,
    connected: boolean,
    initialFlowRate: BigInt,
    userData: Bytes
): PoolConnectionUpdated {
    const poolConnectionUpdatedEvent = createPoolConnectionUpdatedEvent(
        superToken,
        superfluidPool,
        account,
        connected,
        userData
    );

    // getOrInitAccountTokenSnapshot(event) => getOrInitAccount(account) => host.try_getAppManifest(account)
    mockedGetAppManifest(account, false, false, BIG_INT_ZERO);

    // updateATSStreamedAndBalanceUntilUpdatedAt => updateATSBalanceAndUpdatedAt => try_realtimeBalanceOf(account)
    mockedRealtimeBalanceOf(
        superToken,
        account,
        poolConnectionUpdatedEvent.block.timestamp,
        FAKE_INITIAL_BALANCE.plus(initialFlowRate),
        initialFlowRate,
        BIG_INT_ZERO
    );

    handlePoolConnectionUpdated(poolConnectionUpdatedEvent);
    return poolConnectionUpdatedEvent;
}

export function updateMemberUnitsAndReturnMemberUnitsUpdatedEvent(
    superToken: string,
    poolMember: string,
    oldUnits: BigInt,
    newUnits: BigInt
): MemberUnitsUpdated {
    const memberUnitsUpdatedEvent = createMemberUnitsUpdatedEvent(superToken, poolMember, oldUnits, newUnits);

    handleMemberUnitsUpdated(memberUnitsUpdatedEvent);

    return memberUnitsUpdatedEvent;
}

// Mock Event Creators
export function createPoolCreatedEvent(token: string, admin: string, pool: string): PoolCreated {
    const newPoolCreatedEvent = changetype<PoolCreated>(newMockEvent());
    newPoolCreatedEvent.parameters = new Array();
    newPoolCreatedEvent.parameters.push(getAddressEventParam("token", token));
    newPoolCreatedEvent.parameters.push(getAddressEventParam("admin", admin));
    newPoolCreatedEvent.parameters.push(getAddressEventParam("pool", pool));

    return newPoolCreatedEvent;
}

export function createPoolConnectionUpdatedEvent(
    token: string,
    pool: string,
    poolMember: string,
    connected: boolean,
    userData: Bytes
): PoolConnectionUpdated {
    const newPoolConnectionUpdatedEvent = changetype<PoolConnectionUpdated>(newMockEvent());
    newPoolConnectionUpdatedEvent.parameters = new Array();
    newPoolConnectionUpdatedEvent.parameters.push(getAddressEventParam("token", token));
    newPoolConnectionUpdatedEvent.parameters.push(getAddressEventParam("pool", pool));
    newPoolConnectionUpdatedEvent.parameters.push(getAddressEventParam("poolMember", poolMember));
    newPoolConnectionUpdatedEvent.parameters.push(getBooleanEventParam("connected", connected));
    newPoolConnectionUpdatedEvent.parameters.push(getBytesEventParam("userData", userData));

    return newPoolConnectionUpdatedEvent;
}

export function createBufferAdjustedEvent(
    token: string,
    pool: string,
    poolDistributor: string,
    bufferDelta: BigInt,
    newBufferAmount: BigInt,
    totalBufferAmount: BigInt
): BufferAdjusted {
    const newBufferAdjustedEvent = changetype<BufferAdjusted>(newMockEvent());
    newBufferAdjustedEvent.parameters = new Array();
    newBufferAdjustedEvent.parameters.push(getAddressEventParam("token", token));
    newBufferAdjustedEvent.parameters.push(getAddressEventParam("pool", pool));
    newBufferAdjustedEvent.parameters.push(getAddressEventParam("poolDistributor", poolDistributor));
    newBufferAdjustedEvent.parameters.push(getSignedBigIntEventParam("bufferDelta", bufferDelta));
    newBufferAdjustedEvent.parameters.push(getBigIntEventParam("newBufferAmount", newBufferAmount));
    newBufferAdjustedEvent.parameters.push(getBigIntEventParam("totalBufferAmount", totalBufferAmount));

    return newBufferAdjustedEvent;
}

export function createInstantDistributionUpdatedEvent(
    token: string,
    pool: string,
    poolDistributor: string,
    operator: string,
    requestedAmount: BigInt,
    actualAmount: BigInt,
    userData: Bytes
): InstantDistributionUpdated {
    const newInstantDistributionUpdatedEvent = changetype<InstantDistributionUpdated>(newMockEvent());
    newInstantDistributionUpdatedEvent.parameters = new Array();
    newInstantDistributionUpdatedEvent.parameters.push(getAddressEventParam("token", token));
    newInstantDistributionUpdatedEvent.parameters.push(getAddressEventParam("pool", pool));
    newInstantDistributionUpdatedEvent.parameters.push(getAddressEventParam("poolDistributor", poolDistributor));
    newInstantDistributionUpdatedEvent.parameters.push(getAddressEventParam("operator", operator));
    newInstantDistributionUpdatedEvent.parameters.push(getBigIntEventParam("requestedAmount", requestedAmount));
    newInstantDistributionUpdatedEvent.parameters.push(getBigIntEventParam("actualAmount", actualAmount));
    newInstantDistributionUpdatedEvent.parameters.push(getBytesEventParam("userData", userData));

    return newInstantDistributionUpdatedEvent;
}

export function createFlowDistributionUpdatedEvent(
    token: string,
    pool: string,
    poolDistributor: string,
    operator: string,
    oldFlowRate: BigInt,
    newDistributorToPoolFlowRate: BigInt,
    newTotalDistributionFlowRate: BigInt,
    adjustmentFlowRecipient: string,
    adjustmentFlowRate: BigInt,
    userData: Bytes
): FlowDistributionUpdated {
    const newFlowDistributionUpdatedEvent = changetype<FlowDistributionUpdated>(newMockEvent());
    newFlowDistributionUpdatedEvent.parameters = new Array();
    newFlowDistributionUpdatedEvent.parameters.push(getAddressEventParam("token", token));
    newFlowDistributionUpdatedEvent.parameters.push(getAddressEventParam("pool", pool));
    newFlowDistributionUpdatedEvent.parameters.push(getAddressEventParam("poolDistributor", poolDistributor));
    newFlowDistributionUpdatedEvent.parameters.push(getAddressEventParam("operator", operator));
    newFlowDistributionUpdatedEvent.parameters.push(getBigIntEventParam("oldFlowRate", oldFlowRate));
    newFlowDistributionUpdatedEvent.parameters.push(
        getBigIntEventParam("newDistributorToPoolFlowRate", newDistributorToPoolFlowRate)
    );
    newFlowDistributionUpdatedEvent.parameters.push(
        getBigIntEventParam("newTotalDistributionFlowRate", newTotalDistributionFlowRate)
    );
    newFlowDistributionUpdatedEvent.parameters.push(
        getAddressEventParam("adjustmentFlowRecipient", adjustmentFlowRecipient)
    );
    newFlowDistributionUpdatedEvent.parameters.push(getBigIntEventParam("adjustmentFlowRate", adjustmentFlowRate));
    newFlowDistributionUpdatedEvent.parameters.push(getBytesEventParam("userData", userData));

    return newFlowDistributionUpdatedEvent;
}

export function createDistributionClaimedEvent(
    token: string,
    poolMember: string,
    claimedAmount: BigInt,
    totalClaimed: BigInt
): DistributionClaimed {
    const newDistributionClaimedEvent = changetype<DistributionClaimed>(newMockEvent());
    newDistributionClaimedEvent.parameters = new Array();
    newDistributionClaimedEvent.parameters.push(getAddressEventParam("token", token));
    newDistributionClaimedEvent.parameters.push(getAddressEventParam("poolMember", poolMember));
    newDistributionClaimedEvent.parameters.push(getBigIntEventParam("claimedAmount", claimedAmount));
    newDistributionClaimedEvent.parameters.push(getBigIntEventParam("totalClaimed", totalClaimed));

    return newDistributionClaimedEvent;
}

export function createMemberUnitsUpdatedEvent(
    token: string,
    poolMember: string,
    oldUnits: BigInt,
    newUnits: BigInt
): MemberUnitsUpdated {
    const newMemberUnitsUpdatedEvent = changetype<MemberUnitsUpdated>(newMockEvent());
    newMemberUnitsUpdatedEvent.parameters = new Array();
    newMemberUnitsUpdatedEvent.parameters.push(getAddressEventParam("token", token));
    newMemberUnitsUpdatedEvent.parameters.push(getAddressEventParam("poolMember", poolMember));
    newMemberUnitsUpdatedEvent.parameters.push(getBigIntEventParam("oldUnits", oldUnits));
    newMemberUnitsUpdatedEvent.parameters.push(getBigIntEventParam("newUnits", newUnits));

    return newMemberUnitsUpdatedEvent;
}
