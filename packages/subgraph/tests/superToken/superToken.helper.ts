import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { newMockEvent } from "matchstick-as";
import {
    AgreementLiquidatedBy,
    AgreementLiquidatedV2,
    TokenUpgraded,
    TokenDowngraded,
    Transfer,
    Sent,
    Burned,
    Minted,
    Approval,
} from "../../generated/templates/SuperToken/ISuperToken";
import {getAddressEventParam, getBigIntEventParam, getBytesEventParam, getETHAddress} from "../converters";

export function createAgreementLiquidatedByEvent(
    liquidatorAccount: string,
    agreementClass: string,
    agreementId: Bytes,
    penaltyAccount: string,
    bondAccount: string,
    rewardAmount: BigInt,
    bailoutAmount: BigInt
): AgreementLiquidatedBy {
    const newAgreementLiquidatedByEvent = changetype<AgreementLiquidatedBy>(
        newMockEvent()
    );
    newAgreementLiquidatedByEvent.parameters = new Array();

    newAgreementLiquidatedByEvent.parameters = new Array();
    newAgreementLiquidatedByEvent.parameters.push(getAddressEventParam("liquidatorAccount", liquidatorAccount));
    newAgreementLiquidatedByEvent.parameters.push(getAddressEventParam("agreementClass", agreementClass));
    newAgreementLiquidatedByEvent.parameters.push(getBytesEventParam("id", agreementId));
    newAgreementLiquidatedByEvent.parameters.push(getAddressEventParam("penaltyAccount", penaltyAccount));
    newAgreementLiquidatedByEvent.parameters.push(getAddressEventParam("bondAccount", bondAccount));
    newAgreementLiquidatedByEvent.parameters.push(getBigIntEventParam("rewardAmount", rewardAmount));
    newAgreementLiquidatedByEvent.parameters.push(getBigIntEventParam("bailoutAmount", bailoutAmount));

    return newAgreementLiquidatedByEvent;
}

export function createAgreementLiquidatedV2Event(
    liquidatorAccount: string,
    agreementClass: string,
    agreementId: Bytes,
    targetAccount: string,
    rewardAmountReceiver: string,
    rewardAmount: BigInt,
    targetAccountBalanceDelta: BigInt,
    liquidationTypeData: Bytes
): AgreementLiquidatedV2 {
    const newAgreementLiquidatedV2Event = changetype<AgreementLiquidatedV2>(
        newMockEvent()
    );
    newAgreementLiquidatedV2Event.parameters = new Array();
    newAgreementLiquidatedV2Event.parameters.push(getAddressEventParam("agreementClass", agreementClass));
    newAgreementLiquidatedV2Event.parameters.push(getBytesEventParam("id", agreementId));
    newAgreementLiquidatedV2Event.parameters.push(getAddressEventParam("liquidatorAccount", liquidatorAccount));
    newAgreementLiquidatedV2Event.parameters.push(getAddressEventParam("targetAccount", targetAccount));
    newAgreementLiquidatedV2Event.parameters.push(getAddressEventParam("rewardAmountReceiver", rewardAmountReceiver));
    newAgreementLiquidatedV2Event.parameters.push(getBigIntEventParam("rewardAmount", rewardAmount));
    newAgreementLiquidatedV2Event.parameters.push(getBigIntEventParam("targetAccountBalanceDelta", targetAccountBalanceDelta));
    newAgreementLiquidatedV2Event.parameters.push(getBytesEventParam("liquidationTypeData", liquidationTypeData));

    return newAgreementLiquidatedV2Event;
}

export function createTokenUpgradedEvent(
    account: string,
    amount: BigInt
): TokenUpgraded {
    const newTokenUpgradedEvent = changetype<TokenUpgraded>(newMockEvent());
    newTokenUpgradedEvent.parameters = new Array();
    newTokenUpgradedEvent.parameters.push(getAddressEventParam("account", account));
    newTokenUpgradedEvent.parameters.push(getBigIntEventParam("amount", amount))

    return newTokenUpgradedEvent;
}

export function createSuperTokenApprovalEvent(
    owner: string,
    spender: string,
    value: BigInt
): Approval {
    const newApprovalEvent = changetype<Approval>(newMockEvent());
    newApprovalEvent.parameters = new Array();
    newApprovalEvent.parameters.push(getAddressEventParam("owner", owner));
    newApprovalEvent.parameters.push(getAddressEventParam("spender", spender));
    newApprovalEvent.parameters.push(getBigIntEventParam("value", value));

    return newApprovalEvent;
}

export function createTokenDowngradedEvent(
    account: string,
    amount: BigInt
): TokenDowngraded {
    const newTokenDowngradedEvent = changetype<TokenDowngraded>(newMockEvent());
    newTokenDowngradedEvent.parameters = new Array();
    newTokenDowngradedEvent.parameters.push(getAddressEventParam("account", account));
    newTokenDowngradedEvent.parameters.push(getBigIntEventParam("amount", amount));

    return newTokenDowngradedEvent;
}

export function createTransferEvent(
    from: string,
    to: string,
    value: BigInt
): Transfer {
    const newTransferEvent = changetype<Transfer>(newMockEvent());
    newTransferEvent.parameters = new Array();

    newTransferEvent.parameters.push(getAddressEventParam("from", from));
    newTransferEvent.parameters.push(getAddressEventParam("to", to));
    newTransferEvent.parameters.push(getBigIntEventParam("value", value));

    return newTransferEvent;
}

export function createSentEvent(
    operator: string,
    from: string,
    to: string,
    amount: BigInt,
    data: Bytes,
    operatorData: Bytes
): Sent {
    const newSentEvent = changetype<Sent>(newMockEvent());
    newSentEvent.parameters = new Array();

    newSentEvent.parameters.push(getAddressEventParam("operator", operator));
    newSentEvent.parameters.push(getAddressEventParam("from", from));
    newSentEvent.parameters.push(getAddressEventParam("to", to));
    newSentEvent.parameters.push(getBigIntEventParam("amount", amount));
    newSentEvent.parameters.push(getBytesEventParam("data", data));
    newSentEvent.parameters.push(getBytesEventParam("operatorData", operatorData));

    return newSentEvent;
}

export function createBurnedEvent(
    operator: string,
    from: string,
    amount: BigInt,
    data: Bytes,
    operatorData: Bytes
): Burned {
    const newBurnedEvent = changetype<Burned>(newMockEvent());
    newBurnedEvent.parameters = new Array();
    newBurnedEvent.parameters.push(getAddressEventParam("operator", operator));
    newBurnedEvent.parameters.push(getAddressEventParam("from", from));
    newBurnedEvent.parameters.push(getBigIntEventParam("amount", amount));
    newBurnedEvent.parameters.push(getBytesEventParam("data", data));
    newBurnedEvent.parameters.push(getBytesEventParam("operatorData", operatorData));

    return newBurnedEvent;
}

export function createMintedEvent(
    operator: string,
    to: string,
    amount: BigInt,
    data: Bytes,
    operatorData: Bytes
): Minted {
    const newMintedEvent = changetype<Minted>(newMockEvent());
    newMintedEvent.parameters = new Array();
    newMintedEvent.parameters.push(getAddressEventParam("operator", operator));
    newMintedEvent.parameters.push(getAddressEventParam("to", to));
    newMintedEvent.parameters.push(getBigIntEventParam("amount", amount));
    newMintedEvent.parameters.push(getBytesEventParam("data", data));
    newMintedEvent.parameters.push(getBytesEventParam("operatorData", operatorData));

    return newMintedEvent;
}

export function createApprovalEvent(
    token: string,
    owner: string,
    spender: string,
    value: BigInt
): Approval {
    const approvalEvent = changetype<Approval>(
        newMockEvent()
    );

    approvalEvent.address = getETHAddress(token).toAddress();
    approvalEvent.parameters = new Array();
    approvalEvent.parameters.push(getAddressEventParam("owner", owner));
    approvalEvent.parameters.push(getAddressEventParam("spender", spender));
    approvalEvent.parameters.push(getBigIntEventParam("value", value));

    return approvalEvent;
}

