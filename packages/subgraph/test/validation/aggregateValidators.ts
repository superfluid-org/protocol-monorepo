import { expect } from "chai";
import {
    calculateMaybeCriticalAtTimestamp,
    fetchEntityAndEnsureExistence,
} from "../helpers/helpers";
import {
    IAccountTokenSnapshot,
    ITokenStatistic,
    ITokenStatisticLog,
} from "../interfaces";
import {
    getAccountTokenSnapshot,
    getTokenStatistic,
} from "../queries/aggregateQueries";

export const fetchATSAndValidate = async (
    expectedATSData: IAccountTokenSnapshot,
    _skipLogEntryValidation: boolean // retained for signature compatibility; ATSLog indexing is deprecated
) => {
    const graphATS = await fetchEntityAndEnsureExistence<IAccountTokenSnapshot>(
        getAccountTokenSnapshot,
        expectedATSData.id,
        "AccountTokenSnapshot"
    );
    validateATSEntity(graphATS, expectedATSData);
};

export const fetchTokenStatsAndValidate = async (
    expectedTokenStatsData: ITokenStatistic,
    skipLogEntryValidation: boolean
) => {
    const graphTokenStats =
        await fetchEntityAndEnsureExistence<ITokenStatistic>(
            getTokenStatistic,
            expectedTokenStatsData.id,
            "TokenStats"
        );
    validateTokenStatsEntity(graphTokenStats, expectedTokenStatsData);

    if (!skipLogEntryValidation) validateTSLogEntry(graphTokenStats);
};

/**
 * Validates the AccountTokenSnapshot entity.
 * @param graphATSData
 * @param expectedATSData
 */
export const validateATSEntity = (
    graphATSData: IAccountTokenSnapshot,
    expectedATSData: IAccountTokenSnapshot
) => {
    const {
        totalNumberOfActiveStreams: expectedTotalNumberOfActiveStreams,
        totalNumberOfClosedStreams: expectedTotalNumberOfClosedStreams,
        totalSubscriptionsWithUnits: expectedTotalSubscriptions,
        totalApprovedSubscriptions: expectedTotalApprovedSubscriptions,
        balanceUntilUpdatedAt: expectedBalanceUntilUpdatedAt,
        totalNetFlowRate: expectedTotalNetFlowRate,
        totalInflowRate: expectedTotalInflowRate,
        totalOutflowRate: expectedTotalOutflowRate,
        totalAmountStreamedUntilUpdatedAt:
            expectedTotalAmountStreamedUntilUpdatedAt,
        totalAmountStreamedInUntilUpdatedAt:
            expectedTotalAmountStreamedInUntilUpdatedAt,
        totalAmountStreamedOutUntilUpdatedAt:
            expectedTotalAmountStreamedOutUntilUpdatedAt,
        totalAmountTransferredUntilUpdatedAt:
            expectedTotalAmountTransferredUntilUpdatedAt,
        totalDeposit: expectedTotalDeposit,
    } = expectedATSData;

    const calculatedCriticalTimestamp = calculateMaybeCriticalAtTimestamp(
        expectedATSData.updatedAtTimestamp,
        expectedBalanceUntilUpdatedAt,
        expectedTotalNetFlowRate
    );
    expect(
        graphATSData.maybeCriticalAtTimestamp,
        "ATS: maybeCriticalAtTimestamp error"
    ).to.equal(calculatedCriticalTimestamp);
    expect(
        graphATSData.totalNumberOfActiveStreams,
        "ATS: totalNumberOfActiveStreams error"
    ).to.equal(expectedTotalNumberOfActiveStreams);
    expect(
        graphATSData.totalNumberOfClosedStreams,
        "ATS: totalNumberOfClosedStreams error"
    ).to.equal(expectedTotalNumberOfClosedStreams);
    expect(
        graphATSData.totalSubscriptionsWithUnits,
        "ATS: totalSubscriptionWithUnits error"
    ).to.equal(expectedTotalSubscriptions);
    expect(
        graphATSData.totalApprovedSubscriptions,
        "ATS: totalApprovedSubscriptions error"
    ).to.equal(expectedTotalApprovedSubscriptions);
    expect(
        graphATSData.balanceUntilUpdatedAt,
        "ATS: balanceUntilUpdatedAt error"
    ).to.equal(expectedBalanceUntilUpdatedAt);
    expect(
        graphATSData.totalNetFlowRate,
        "ATS: totalNetFlowRate error"
    ).to.equal(expectedTotalNetFlowRate);
    expect(graphATSData.totalInflowRate, "ATS: totalInflowRate error").to.equal(
        expectedTotalInflowRate
    );
    expect(graphATSData.totalDeposit, "ATS: totalDeposit error").to.equal(
        expectedTotalDeposit
    );
    expect(
        graphATSData.totalOutflowRate,
        "ATS: totalOutflowRate error"
    ).to.equal(expectedTotalOutflowRate);
    expect(
        graphATSData.totalAmountStreamedUntilUpdatedAt,
        "ATS: totalAmountStreamedUntilUpdatedAt error"
    ).to.equal(expectedTotalAmountStreamedUntilUpdatedAt);
    expect(
        graphATSData.totalAmountStreamedInUntilUpdatedAt,
        "ATS: totalAmountStreamedInUntilUpdatedAt error"
    ).to.equal(expectedTotalAmountStreamedInUntilUpdatedAt);
    expect(
        graphATSData.totalAmountStreamedOutUntilUpdatedAt,
        "ATS: totalAmountStreamedOutUntilUpdatedAt error"
    ).to.equal(expectedTotalAmountStreamedOutUntilUpdatedAt);
    expect(
        graphATSData.totalAmountTransferredUntilUpdatedAt,
        "ATS: totalAmountTransferredUntilUpdatedAt error"
    ).to.equal(expectedTotalAmountTransferredUntilUpdatedAt);
};

/**
 * Validates the TokenStatistic entity.
 * @param graphTokenStats
 * @param expectedTokenStats
 */
export const validateTokenStatsEntity = (
    graphTokenStats: ITokenStatistic,
    expectedTokenStats: ITokenStatistic
) => {
    const {
        totalNumberOfActiveStreams: expectedTotalNumberOfActiveStreams,
        totalNumberOfClosedStreams: expectedTotalNumberOfClosedStreams,
        totalNumberOfIndexes: expectedTotalNumberOfIndexes,
        totalNumberOfActiveIndexes: expectedTotalNumberOfActiveIndexes,
        totalSubscriptionsWithUnits: expectedTotalSubscriptions,
        totalApprovedSubscriptions: expectedTotalApprovedSubscriptions,
        totalOutflowRate: expectedTotalOutflowRate,
        totalAmountStreamedUntilUpdatedAt:
            expectedTotalAmountStreamedUntilUpdatedAt,
        totalAmountTransferredUntilUpdatedAt:
            expectedTotalAmountTransferredUntilUpdatedAt,
        totalAmountDistributedUntilUpdatedAt:
            expectedTotalAmountDistributedUntilUpdatedAt,
        totalSupply: expectedTotalSupply,
        totalDeposit: expectedTotalDeposit,
    } = expectedTokenStats;

    expect(
        graphTokenStats.totalNumberOfActiveStreams,
        "TokenStats: totalNumberOfActiveStreams error"
    ).to.equal(expectedTotalNumberOfActiveStreams);
    expect(
        graphTokenStats.totalNumberOfClosedStreams,
        "TokenStats: totalNumberOfClosedStreams error"
    ).to.equal(expectedTotalNumberOfClosedStreams);
    expect(graphTokenStats.totalNumberOfIndexes).to.equal(
        expectedTotalNumberOfIndexes
    );
    expect(
        graphTokenStats.totalNumberOfActiveIndexes,
        "TokenStats: totalNumberOfActiveIndexes error"
    ).to.equal(expectedTotalNumberOfActiveIndexes);
    expect(
        graphTokenStats.totalSubscriptionsWithUnits,
        "TokenStats: totalSubscriptionWithUnits error"
    ).to.equal(expectedTotalSubscriptions);
    expect(
        graphTokenStats.totalApprovedSubscriptions,
        "TokenStats: totalApprovedSubscriptions error"
    ).to.equal(expectedTotalApprovedSubscriptions);
    expect(
        graphTokenStats.totalOutflowRate,
        "TokenStats: totalOutflowRate error"
    ).to.equal(expectedTotalOutflowRate);
    expect(
        graphTokenStats.totalAmountStreamedUntilUpdatedAt,
        "TokenStats: totalAmountStreamedUntilUpdatedAt error"
    ).to.equal(expectedTotalAmountStreamedUntilUpdatedAt);
    expect(
        graphTokenStats.totalAmountDistributedUntilUpdatedAt,
        "TokenStats: totalAmountDistributedUntilUpdatedAt error"
    ).to.equal(expectedTotalAmountDistributedUntilUpdatedAt);
    expect(
        graphTokenStats.totalDeposit,
        "TokenStats: totalDeposit error"
    ).to.equal(expectedTotalDeposit);
};

export const validateTSLogEntry = (graphTSData: ITokenStatistic) => {
    const tokenStatisticLog: ITokenStatisticLog =
        graphTSData.tokenStatisticLogs[0];
    expect(
        graphTSData.updatedAtTimestamp,
        "TSLog: updatedAtTimestamp error"
    ).to.equal(tokenStatisticLog.timestamp);
    expect(
        graphTSData.updatedAtBlockNumber,
        "TSLog: updatedAtBlockNumber error"
    ).to.equal(tokenStatisticLog.blockNumber);
    expect(
        graphTSData.totalNumberOfActiveStreams,
        "TSLog: totalNumberOfActiveStreams error"
    ).to.equal(tokenStatisticLog.totalNumberOfActiveStreams);
    expect(
        graphTSData.totalNumberOfClosedStreams,
        "TSLog: totalNumberOfClosedStreams error"
    ).to.equal(tokenStatisticLog.totalNumberOfClosedStreams);
    expect(
        graphTSData.totalSubscriptionsWithUnits,
        "TSLog: totalSubscriptionWithUnits error"
    ).to.equal(tokenStatisticLog.totalSubscriptionsWithUnits);
    expect(
        graphTSData.totalApprovedSubscriptions,
        "TSLog: totalApprovedSubscriptions error"
    ).to.equal(tokenStatisticLog.totalApprovedSubscriptions);
    expect(graphTSData.totalDeposit, "TSLog: totalDeposit error").to.equal(
        tokenStatisticLog.totalDeposit
    );
    expect(
        graphTSData.totalOutflowRate,
        "TSLog: totalOutflowRate error"
    ).to.equal(tokenStatisticLog.totalOutflowRate);
    expect(
        graphTSData.totalAmountStreamedUntilUpdatedAt,
        "TSLog: totalAmountStreamed error"
    ).to.equal(tokenStatisticLog.totalAmountStreamed);
    expect(
        graphTSData.totalAmountTransferredUntilUpdatedAt,
        "TSLog: totalAmountTransferred error"
    ).to.equal(tokenStatisticLog.totalAmountTransferred);
    expect(
        graphTSData.totalAmountDistributedUntilUpdatedAt,
        "TSLog: totalAmountDistributed error"
    ).to.equal(tokenStatisticLog.totalAmountDistributed);
    expect(graphTSData.totalDeposit, "TSLog: totalDeposit error").to.equal(
        tokenStatisticLog.totalDeposit
    );
    expect(graphTSData.totalSupply, "TSLog: totalSupply error").to.equal(
        tokenStatisticLog.totalSupply
    );
};
