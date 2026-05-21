/**************************************************************************
 * Entity Initializers
 *
 * This file contains all the getter functions for the different HOL and
 * Aggregate entities which we need to maintain a record of expected
 * values for testing. We initialize the entity when it doesn't exist and
 * retrieve it from the global object if it does.
 *************************************************************************/

import {
    IAccountTokenSnapshot,
    IFlowOperator,
    IFlowOperatorUpdatedInitTestData,
    IFlowUpdatedInitTestData,
    IIndex,
    IIndexSubscription,
    IInstantDistributionTestData,
    IStreamData,
    ITokenStatistic,
} from "../interfaces";
import {
    getATSId,
    getFlowOperatorId,
    getIndexId,
    getRevisionIndexId,
    getStreamId,
    getSubscriptionId,
} from "./helpers";

export const getOrInitRevisionIndex = (
    revisionIndexes: { [id: string]: number | undefined },
    revisionIndexId: string
): number => {
    return revisionIndexes[revisionIndexId] || 0;
};
export const getOrInitPeriodRevisionIndex = (
    periodRevisionIndexes: { [id: string]: number | undefined },
    revisionIndexId: string
): number => {
    return periodRevisionIndexes[revisionIndexId] || 0;
};

export const getOrInitStreamData = (
    streamData: { [id: string]: IStreamData | undefined },
    revisionIndex: string,
    periodRevisionIndex: string,
    streamId: string,
    updatedAtTimestamp: string
): IStreamData => {
    const existingStreamData = streamData[streamId];
    if (existingStreamData == null) {
        return {
            id: streamId,
            revisionIndex,
            periodRevisionIndex,
            oldFlowRate: "0",
            deposit: "0",
            streamedUntilUpdatedAt: "0",
            updatedAtTimestamp,
        };
    }
    return existingStreamData;
};

export const getOrInitFlowOperator = (
    flowOperators: {
        [id: string]: IFlowOperator | undefined;
    },
    flowOperatorId: string,
    updatedAtBlockNumber: string,
    updatedAtTimestamp: string
): IFlowOperator => {
    const existingFlowOperator = flowOperators[flowOperatorId];
    if (existingFlowOperator == null) {
        const [flowOperator, token, sender] = flowOperatorId.split("-");
        return {
            id: flowOperatorId,
            createdAtTimestamp: updatedAtTimestamp,
            createdAtBlockNumber: updatedAtBlockNumber,
            updatedAtTimestamp,
            updatedAtBlockNumber,
            permissions: 0,
            flowRateAllowanceGranted: "0",
            flowRateAllowanceRemaining: "0",
            flowOperatorUpdatedEvents: [],
            sender: { id: sender },
            token: { id: token },
            flowOperator,
            accountTokenSnapshot: { id: sender + "-" + token },
        };
    }
    return existingFlowOperator;
};

export const getOrInitIndex = (
    indexes: { [id: string]: IIndex | undefined },
    indexEntityId: string,
    updatedAtBlockNumber: string,
    updatedAtTimestamp: string
): IIndex => {
    const existingIndex = indexes[indexEntityId];
    if (existingIndex == null) {
        const [publisher, token, indexId] = indexEntityId.split("-");
        return {
            id: indexEntityId,
            createdAtTimestamp: updatedAtTimestamp,
            createdAtBlockNumber: updatedAtBlockNumber,
            updatedAtBlockNumber,
            updatedAtTimestamp,
            indexId,
            publisher: { id: publisher },
            token: { id: token },
            indexValue: "0",
            totalSubscriptionsWithUnits: 0,
            totalUnits: "0",
            totalUnitsApproved: "0",
            totalAmountDistributedUntilUpdatedAt: "0",
            totalUnitsPending: "0",
        };
    }
    return existingIndex;
};

export const getOrInitSubscription = (
    subscription: { [id: string]: IIndexSubscription | undefined },
    subscriptionId: string,
    updatedAtBlockNumber: string,
    updatedAtTimestamp: string
): IIndexSubscription => {
    const existingSubscription = subscription[subscriptionId];
    if (existingSubscription == null) {
        const [subscriber, publisher, token, indexId] =
            subscriptionId.split("-");
        const indexEntityId = getIndexId(publisher, token, indexId);
        return {
            id: subscriptionId,
            createdAtTimestamp: updatedAtTimestamp,
            createdAtBlockNumber: updatedAtBlockNumber,
            updatedAtBlockNumber,
            updatedAtTimestamp: updatedAtTimestamp,
            subscriber: { id: subscriber },
            approved: false,
            units: "0",
            totalAmountReceivedUntilUpdatedAt: "0",
            indexValueUntilUpdatedAt: "0",
            index: {
                id: indexEntityId,
                publisher: { id: publisher },
                indexId,
                token: { id: token },
            },
        };
    }
    return existingSubscription;
};

export const getOrInitAccountTokenSnapshot = (
    accountTokenSnapshots: {
        [id: string]: IAccountTokenSnapshot | undefined;
    },
    accountId: string,
    tokenId: string,
    updatedAtBlockNumber: string,
    updatedAtTimestamp: string
): IAccountTokenSnapshot => {
    const atsId = getATSId(accountId, tokenId);
    const existingATS = accountTokenSnapshots[atsId];
    if (existingATS == null) {
        return {
            id: atsId,
            updatedAtBlockNumber,
            updatedAtTimestamp,
            totalNumberOfActiveStreams: 0,
            totalNumberOfClosedStreams: 0,
            totalSubscriptionsWithUnits: 0,
            totalApprovedSubscriptions: 0,
            balanceUntilUpdatedAt: "0",
            totalAmountStreamedUntilUpdatedAt: "0",
            totalAmountStreamedInUntilUpdatedAt: "0",
            totalAmountStreamedOutUntilUpdatedAt: "0",
            totalAmountTransferredUntilUpdatedAt: "0",
            totalDeposit: "0",
            maybeCriticalAtTimestamp: "0",
            totalNetFlowRate: "0",
            totalInflowRate: "0",
            totalOutflowRate: "0",
            account: { id: accountId },
            token: { id: tokenId },
            flowOperators: [],
        };
    }
    return existingATS;
};

export const getOrInitTokenStatistics = (
    tokenStatistics: { [id: string]: ITokenStatistic | undefined },
    tokenId: string,
    updatedAtBlockNumber: string,
    updatedAtTimestamp: string,
    totalSupply?: string
): ITokenStatistic => {
    const existingTokenStats = tokenStatistics[tokenId];
    if (existingTokenStats == null) {
        return {
            id: tokenId,
            updatedAtBlockNumber,
            updatedAtTimestamp,
            totalNumberOfActiveStreams: 0,
            totalNumberOfClosedStreams: 0,
            totalNumberOfIndexes: 0,
            totalNumberOfActiveIndexes: 0,
            totalSubscriptionsWithUnits: 0,
            totalApprovedSubscriptions: 0,
            totalOutflowRate: "0",
            totalAmountStreamedUntilUpdatedAt: "0",
            totalAmountTransferredUntilUpdatedAt: "0",
            totalAmountDistributedUntilUpdatedAt: "0",
            totalDeposit: "0",
            totalSupply: totalSupply || "0",
            token: { id: tokenId },
            tokenStatisticLogs: [],
        };
    }
    return existingTokenStats;
};

/**
 * Gets/Initializes all data for the FlowUpdated event
 * @param initTestData
 * @returns
 */
export function getOrInitializeDataForFlowUpdated(
    initTestData: IFlowUpdatedInitTestData
) {
    const data = initTestData.data;
    const localData = initTestData.data.localData;
    const tokenAddress = data.superToken.address;

    const revisionIndexId = getRevisionIndexId(
        data.sender,
        data.receiver,
        tokenAddress
    );
    const flowOperatorId = getFlowOperatorId({
        flowOperator: data.flowOperator,
        token: tokenAddress,
        sender: data.sender,
    });
    const tokenId = tokenAddress.toLowerCase();
    const currentRevisionIndex = getOrInitRevisionIndex(
        localData.revisionIndexes,
        revisionIndexId
    );
    const currentPeriodRevisionIndex = getOrInitPeriodRevisionIndex(
        localData.periodRevisionIndexes,
        revisionIndexId
    );
    const streamId = getStreamId(
        data.sender,
        data.receiver,
        tokenAddress,
        currentRevisionIndex.toString()
    );
    const pastStreamData = getOrInitStreamData(
        localData.streamData,
        currentRevisionIndex.toString(),
        currentPeriodRevisionIndex.toString(),
        streamId,
        initTestData.updatedAtTimestamp
    );
    const currentSenderATS = getOrInitAccountTokenSnapshot(
        localData.accountTokenSnapshots,
        data.sender.toLowerCase(),
        tokenId,
        initTestData.updatedAtBlockNumber,
        initTestData.updatedAtTimestamp
    );
    const currentReceiverATS = getOrInitAccountTokenSnapshot(
        localData.accountTokenSnapshots,
        data.receiver.toLowerCase(),
        tokenId,
        initTestData.updatedAtBlockNumber,
        initTestData.updatedAtTimestamp
    );
    const currentTokenStats = getOrInitTokenStatistics(
        localData.tokenStatistics,
        tokenId,
        initTestData.updatedAtBlockNumber,
        initTestData.updatedAtTimestamp,
        data.totalSupply
    );
    const currentFlowOperator = getOrInitFlowOperator(
        localData.flowOperators,
        flowOperatorId,
        initTestData.updatedAtBlockNumber,
        initTestData.updatedAtTimestamp
    );

    return {
        currentFlowOperator,
        currentReceiverATS,
        currentSenderATS,
        currentTokenStats,
        pastStreamData,
        revisionIndexId,
    };
}

export function getOrInitializeDataForFlowOperatorUpdated(
    testData: IFlowOperatorUpdatedInitTestData
) {
    const flowOperator = getOrInitFlowOperator(
        testData.flowOperators,
        testData.flowOperatorId,
        testData.updatedAtBlockNumber,
        testData.updatedAtTimestamp
    );

    const senderATS = getOrInitAccountTokenSnapshot(
        testData.accountTokenSnapshots,
        flowOperator.sender.id,
        testData.token,
        testData.updatedAtBlockNumber,
        testData.updatedAtTimestamp
    );

    return {
        flowOperator,
        senderATS,
    };
}

/**
 * Gets/Initializes all data for the different IDA events
 * @param testData
 * @returns
 */
export function getOrInitializeDataForIDA(
    testData: IInstantDistributionTestData
) {
    const {
        accountTokenSnapshots,
        indexes,
        indexId,
        updatedAtTimestamp,
        updatedAtBlockNumber,
        publisher,
        subscriber,
        subscriptions,
        token,
        tokenStatistics,
    } = testData;
    let subscriberAddress = subscriber || "";
    const subscriptionId = getSubscriptionId(
        subscriberAddress,
        publisher,
        token,
        indexId
    );
    const indexEntityId = getIndexId(publisher, token, indexId);
    const currentIndex = getOrInitIndex(
        indexes,
        indexEntityId,
        updatedAtBlockNumber,
        updatedAtTimestamp
    );

    const currentSubscription = getOrInitSubscription(
        subscriptions,
        subscriptionId,
        updatedAtBlockNumber,
        updatedAtTimestamp
    );

    const currentPublisherATS = getOrInitAccountTokenSnapshot(
        accountTokenSnapshots,
        publisher.toLowerCase(),
        token.toLowerCase(),
        updatedAtBlockNumber,
        updatedAtTimestamp
    );
    const currentSubscriberATS = getOrInitAccountTokenSnapshot(
        accountTokenSnapshots,
        subscriberAddress.toLowerCase(),
        token.toLowerCase(),
        updatedAtBlockNumber,
        updatedAtTimestamp
    );

    const currentTokenStats = getOrInitTokenStatistics(
        tokenStatistics,
        token.toLowerCase(),
        updatedAtBlockNumber,
        updatedAtTimestamp
    );
    return {
        subscriptionId,
        indexEntityId,
        currentIndex,
        currentSubscription,
        currentPublisherATS,
        currentSubscriberATS,
        currentTokenStats,
    };
}
