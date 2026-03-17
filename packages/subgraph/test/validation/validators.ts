import {
    IAccountTokenSnapshot,
    IEvent,
    IExpectedFlowOperatorData,
    IIDAEvents,
    IIndex,
    IIndexSubscription,
    ILightEntity,
    IStreamData,
    ITokenStatistic,
} from "../interfaces";
import { fetchStreamPeriodAndValidate } from "./hol/streamPeriodValidator";
import { fetchIndexAndValidate } from "./hol/indexValidator";
import { fetchStreamAndValidate } from "./hol/streamValidator";
import { fetchSubscriptionAndValidate } from "./hol/subscriptionValidator";
import {
    fetchATSAndValidate,
    fetchTokenStatsAndValidate,
} from "./aggregateValidators";
import { Framework } from "@superfluid-finance/sdk-core";
import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { FlowActionType, IDAEventType } from "../helpers/constants";
import { fetchFlowOperatorAndValidate } from "./hol/flowOperatorValidator";

export async function validateFlowUpdated(
    pastStreamData: IStreamData,
    streamedAmountUntilTimestamp: BigNumber,
    newFlowRate: BigNumber,
    updatedSenderATS: IAccountTokenSnapshot,
    updatedReceiverATS: IAccountTokenSnapshot,
    updatedTokenStats: ITokenStatistic,
    event: IEvent,
    actionType: FlowActionType,
    newDeposit: string
) {
    // validate Stream HOL
    await fetchStreamAndValidate(
        pastStreamData,
        streamedAmountUntilTimestamp,
        newFlowRate.toString(),
        event,
        actionType === FlowActionType.Create,
        newDeposit
    );
    // validate StreamPeriod HOL
    await fetchStreamPeriodAndValidate(
        pastStreamData,
        newFlowRate.toString(),
        event,
        actionType,
        newDeposit
    );

    // validate sender ATS
    await fetchATSAndValidate(updatedSenderATS, false); // Boolean flag to decide, whether to check log entries or not.

    // validate receiver ATS
    await fetchATSAndValidate(updatedReceiverATS, false); // Boolean flag to decide, whether to check log entries or not.

    // validate token stats (TSLog validation skipped - TokenStatisticLog creation is deprecated)
    await fetchTokenStatsAndValidate(updatedTokenStats, true);
}

export async function validateUpdateFlowOperatorPermissions({
    event,
    expectedFlowOperator,
    isCreate,
}: {
    event: IEvent;
    expectedFlowOperator: IExpectedFlowOperatorData;
    isCreate: boolean;
}) {
    // fetch flow operator entity and validte it
    await fetchFlowOperatorAndValidate({
        event,
        expectedFlowOperator,
        isCreate,
    });
}

export async function validateModifyIDA(
    framework: Framework,
    updatedIndex: IIndex,
    updatedSubscription: IIndexSubscription,
    updatedPublisherATS: IAccountTokenSnapshot,
    updatedSubscriberATS: IAccountTokenSnapshot,
    updatedTokenStats: ITokenStatistic,
    subscriberAddress: string,
    eventType: IDAEventType,
    events: IIDAEvents,
    subscriptionExists: boolean
) {
    // We don't want to validate the subscriber for the IndexCreated/IndexUpdated
    // events
    if (subscriberAddress !== "") {
        await fetchSubscriptionAndValidate(
            framework,
            updatedSubscription,
            updatedIndex.indexValue,
            eventType,
            events,
            subscriptionExists
        );
        await fetchATSAndValidate(updatedSubscriberATS, true); // Boolean flag to decide, whether to check log entries or not.
    }
    await fetchIndexAndValidate(
        framework,
        updatedIndex,
        eventType,
        events,
        updatedSubscription.id,
        subscriptionExists
    );
    await fetchATSAndValidate(updatedPublisherATS, true); // Boolean flag to decide, whether to check log entries or not.
    await fetchTokenStatsAndValidate(updatedTokenStats, true);
}

export function validateReverseLookup(
    entity: ILightEntity,
    entities: ILightEntity[]
) {
    const entityToValidate = entities[entities.length - 1];
    expect(entity.id, "reverse lookup error").to.equal(entityToValidate.id);
}
