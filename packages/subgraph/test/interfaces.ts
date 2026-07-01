/**************************************************************************
 * GraphQL Entity Types
 *************************************************************************/
import { BaseProvider } from "@ethersproject/providers";
import { BigNumber } from "@ethersproject/bignumber";
import { Framework, SuperToken } from "@superfluid-finance/sdk-core";
import { FlowActionType, IDAEventType } from "./helpers/constants";

/**
 * Event Entities
 */
export interface IEvent {
    readonly id: string;
    readonly transactionHash: string;
    readonly gasPrice: string;
    readonly blockNumber: string;
    readonly logIndex: string;
    readonly name: string;
    readonly addresses: string[];
    readonly timestamp: string;
    readonly order: string;
}

export interface ISubgraphError {
    locations: { line: number; column: number }[];
    message: string;
}

export interface ISubgraphErrors {
    errors?: ISubgraphError[];
}

export interface IMeta {
    readonly _meta: {
        readonly block: {
            readonly number: number;
        };
    };
}

// CFAV1
export interface IFlowUpdatedEvent extends IEvent {
    readonly token: string;
    readonly sender: string;
    readonly receiver: string;
    readonly flowOperator: string;
    readonly flowRate: string;
    readonly totalAmountStreamedUntilTimestamp: string;
    readonly totalReceiverFlowRate: string;
    readonly totalSenderFlowRate: string;
    readonly deposit: string;
    readonly oldFlowRate: string;
    readonly type: string;
}
export interface ITransferEvent extends IEvent {
    readonly from: string;
    readonly to: string;
    readonly value: string;
}

export interface IFlowOperatorUpdatedEvent extends IEvent {
    readonly token: string;
    readonly sender: string;
    readonly permissions: number;
    readonly flowRateAllowance: string;
    readonly flowOperator: ILightEntity;
    readonly order: string;
    readonly logIndex: string;
}

// IDAV1
export interface IIndexCreatedEvent extends IEvent {
    readonly token: string;
    readonly publisher: string;
    readonly indexId: string;
    readonly userData: string;
}

export interface IIndexUpdatedEvent extends IEvent {
    readonly token: string;
    readonly publisher: string;
    readonly indexId: string;
    readonly oldIndexValue: string;
    readonly newIndexValue: string;
    readonly totalUnitsPending: string;
    readonly totalUnitsApproved: string;
    readonly userData: string;
    readonly order: string;
    readonly logIndex: string;
}

export interface IIndexSubscribedEvent extends IEvent {
    readonly token: string;
    readonly publisher: string;
    readonly indexId: string;
    readonly subscriber: string;
    readonly userData: string;
}

export interface IIndexUnitsUpdatedEvent extends IEvent {
    readonly token: string;
    readonly publisher: string;
    readonly indexId: string;
    readonly subscriber: string;
    readonly units: string;
    readonly userData: string;
    readonly order: string;
    readonly logIndex: string;
}

export interface IIndexUnsubscribedEvent extends IEvent {
    readonly token: string;
    readonly publisher: string;
    readonly indexId: string;
    readonly subscriber: string;
    readonly userData: string;
}

export interface ISubscriptionApprovedEvent extends IEvent {
    readonly token: string;
    readonly subscriber: string;
    readonly subscription: ILightEntity;
    readonly publisher: string;
    readonly indexId: string;
    readonly userData: string;
}

export interface ISubscriptionRevokedEvent extends IEvent {
    readonly token: string;
    readonly subscriber: string;
    readonly subscription: ILightEntity;
    readonly publisher: string;
    readonly indexId: string;
    readonly order: string;
    readonly userData: string;
    readonly logIndex: string;
}

export interface ISubscriptionUnitsUpdatedEvent extends IEvent {
    readonly token: string;
    readonly subscriber: string;
    readonly subscription: ILightEntity;
    readonly publisher: string;
    readonly indexId: string;
    readonly units: string;
    readonly userData: string;
    readonly order: string;
    readonly logIndex: string;
}

// SuperToken
export interface ITokenUpgradedEvent extends IEvent {
    readonly id: string;
    readonly account: string;
    readonly transactionHash: string;
    readonly timestamp: string;
    readonly blockNumber: string;
    readonly token: string;
    readonly amount: string;
}

export interface ITokenDowngradedEvent extends IEvent {
    readonly id: string;
    readonly account: string;
    readonly transactionHash: string;
    readonly timestamp: string;
    readonly blockNumber: string;
    readonly token: string;
    readonly amount: string;
}

export interface ITransferEvent extends IEvent {
    readonly id: string;
    readonly transactionHash: string;
    readonly timestamp: string;
    readonly blockNumber: string;
    readonly from: string;
    readonly to: string;
    readonly value: string;
    readonly token: string;
}

/**
 * HOL Entities
 */
interface IBaseEntity {
    readonly id: string;
    readonly createdAtTimestamp: string;
    readonly createdAtBlockNumber: string;
    readonly updatedAtTimestamp: string;
    readonly updatedAtBlockNumber: string;
}

export interface IAccount extends IBaseEntity {
    readonly isSuperApp: boolean;
    readonly inflows: ILightEntity[];
    readonly outflows: ILightEntity[];
    readonly subscriptions: ILightEntity[];
    readonly publishedIndexes: ILightEntity[];
}

export interface IToken extends IBaseEntity {
    readonly decimals: number;
    readonly name: string;
    readonly symbol: string;
    readonly underlyingAddress: string;
    readonly isNativeAssetSuperToken: boolean;
    readonly isListed: boolean;
    readonly underlyingToken: ILightEntity | null;
}

export interface IStream extends IBaseEntity {
    readonly currentFlowRate: string;
    readonly streamedUntilUpdatedAt: string;
    readonly deposit: string;
    readonly token: ILightEntity;
    readonly sender: ILightEntity;
    readonly receiver: ILightEntity;
    readonly flowUpdatedEvents: ILightEntity[];
    readonly streamPeriods: ILightEntity[];
}

export interface IStreamPeriod extends IBaseEntity {
    readonly id: string;
    readonly deposit: string;
    readonly stream: ILightEntity;
    readonly sender: ILightEntity;
    readonly receiver: ILightEntity;
    readonly token: ILightEntity;
    readonly flowRate: string;
    readonly startedAtTimestamp: string;
    readonly startedAtBlockNumber: string;
    readonly startedAtEvent: ILightEntity;
    readonly stoppedAtTimestamp: string;
    readonly stoppedAtBlockNumber: string;
    readonly stoppedAtEvent: ILightEntity;
    readonly totalAmountStreamed: string;
}

export interface IFlowOperator extends IBaseEntity {
    readonly permissions: number;
    readonly flowRateAllowanceGranted: string;
    readonly flowRateAllowanceRemaining: string;
    readonly flowOperator: string;
    readonly sender: ILightEntity;
    readonly token: ILightEntity;
    readonly accountTokenSnapshot: ILightEntity;

    readonly flowOperatorUpdatedEvents: ILightEntity[];
}

export interface IIndexSubscription extends IBaseEntity {
    readonly subscriber: ILightEntity;
    readonly approved: boolean;
    readonly units: string;
    readonly totalAmountReceivedUntilUpdatedAt: string;
    readonly indexValueUntilUpdatedAt: string;
    readonly index: ILightIndex;

    readonly subscriptionApprovedEvents?: ILightEntity[];
    readonly subscriptionDistributionClaimedEvents?: ILightEntity[];
    readonly subscriptionRevokedEvents?: ILightEntity[];
    readonly subscriptionUnitsUpdatedEvents?: ILightEntity[];
}

interface ILightIndex extends ILightEntity {
    readonly indexId: string;
    readonly token: ILightEntity;
    readonly publisher: ILightEntity;
}

export interface IIndex extends IBaseEntity {
    readonly indexId: string;
    readonly indexValue: string;
    readonly totalSubscriptionsWithUnits: number;
    readonly totalUnitsPending: string;
    readonly totalUnitsApproved: string;
    readonly totalUnits: string;
    readonly totalAmountDistributedUntilUpdatedAt: string;
    readonly token: ILightEntity;
    readonly publisher: ILightEntity;

    readonly subscriptions?: ILightEntity[];
    readonly indexCreatedEvent?: ILightEntity;
    readonly indexDistributionClaimedEvents?: ILightEntity[];
    readonly indexUpdatedEvents?: ILightEntity[];
    readonly indexSubscribedEvents?: ILightEntity[];
    readonly indexUnitsUpdatedEvents?: ILightEntity[];
    readonly indexUnsubscribedEvents?: ILightEntity[];
}

/**
 * Aggregate Entities
 */
export interface IBaseAggregateEntity {
    readonly id: string;
    readonly updatedAtTimestamp: string;
    readonly updatedAtBlockNumber: string;
}

export interface IAccountTokenSnapshot extends IBaseAggregateEntity {
    readonly totalNumberOfActiveStreams: number;
    readonly totalNumberOfClosedStreams: number;
    readonly totalSubscriptionsWithUnits: number;
    readonly totalApprovedSubscriptions: number;
    readonly balanceUntilUpdatedAt: string;
    readonly totalAmountStreamedUntilUpdatedAt: string;
    readonly totalAmountStreamedInUntilUpdatedAt: string;
    readonly totalAmountStreamedOutUntilUpdatedAt: string;
    readonly totalAmountTransferredUntilUpdatedAt: string;
    readonly totalDeposit: string;
    readonly maybeCriticalAtTimestamp: string;
    readonly totalInflowRate: string;
    readonly totalNetFlowRate: string;
    readonly totalOutflowRate: string;
    readonly account: ILightEntity;
    readonly token: ILightEntity;
    readonly flowOperators: ILightEntity[];
}

export interface ITokenStatistic extends IBaseAggregateEntity {
    readonly totalNumberOfActiveStreams: number;
    readonly totalNumberOfClosedStreams: number;
    readonly totalNumberOfIndexes: number;
    readonly totalNumberOfActiveIndexes: number;
    readonly totalSubscriptionsWithUnits: number;
    readonly totalApprovedSubscriptions: number;
    readonly totalOutflowRate: string;
    readonly totalAmountStreamedUntilUpdatedAt: string;
    readonly totalAmountTransferredUntilUpdatedAt: string;
    readonly totalAmountDistributedUntilUpdatedAt: string;
    readonly totalDeposit: string;
    readonly totalSupply: string;
    readonly token: ILightEntity;
    readonly tokenStatisticLogs: ITokenStatisticLog[];
}

export interface ITokenStatisticLog {
    readonly transactionHash: string;
    readonly blockNumber: string;
    readonly logIndex: string;
    readonly timestamp: string;
    readonly order: string;
    readonly triggeredByEventName: string;
    readonly totalNumberOfActiveStreams: number;
    readonly totalNumberOfClosedStreams: number;
    readonly totalNumberOfIndexes: number;
    readonly totalNumberOfActiveIndexes: number;
    readonly totalSubscriptionsWithUnits: number;
    readonly totalApprovedSubscriptions: number;
    readonly totalOutflowRate: string;
    readonly totalAmountStreamed: string;
    readonly totalAmountTransferred: string;
    readonly totalAmountDistributed: string;
    readonly totalDeposit: string;
    readonly totalSupply: string;
}

/** Sub-entity Entities */
export interface ILightEntity {
    readonly id: string;
}

/**************************************************************************
 * Internal Interfaces
 *************************************************************************/
export interface IStreamData {
    id: string;
    revisionIndex: string;
    periodRevisionIndex: string;
    oldFlowRate: string;
    deposit: string;
    streamedUntilUpdatedAt: string;
    updatedAtTimestamp: string;
}

export interface IStreamTestParams {
    readonly actionType: FlowActionType;
    readonly flowRate: number;
    readonly streamHistory: IStreamData;
}

export interface IExpectedFlowOperatorData {
    readonly id: string;
    readonly permissions: number;
    readonly flowRateAllowanceGranted: string;
    readonly flowRateAllowanceRemaining: string;
}

export interface IExpectedATSData {
    readonly totalNumberOfActiveStreams: number;
    readonly totalNumberOfClosedStreams: number;
    readonly balanceUntilUpdatedAt: string;
    readonly totalInflowRate: string;
    readonly totalOutflowRate: string;
    readonly totalNetFlowRate: string;
    readonly totalAmountStreamedUntilUpdatedAt: string;
}

export interface IExpectedTokenStats {
    readonly totalNumberOfActiveStreams: number;
    readonly totalNumberOfClosedStreams: number;
    readonly totalOutflowRate: string;
    readonly totalAmountStreamedUntilUpdatedAt: string;
}

export interface IUpdateGlobalObjects {
    readonly revisionIndexId?: string;
    readonly updatedStreamData?: IStreamData;
    readonly updatedFlowOperator?: IFlowOperator;
    readonly updatedSenderATS?: IAccountTokenSnapshot;
    readonly updatedReceiverATS?: IAccountTokenSnapshot;
    readonly updatedPublisherATS?: IAccountTokenSnapshot;
    readonly updatedSubscriberATS?: IAccountTokenSnapshot;
    readonly updatedIndex?: IIndex;
    readonly updatedSubscription?: IIndexSubscription;
    readonly updatedTokenStats?: ITokenStatistic;
}

export interface IAggregateLocalData {
    readonly accountTokenSnapshots: {
        [id: string]: IAccountTokenSnapshot | undefined;
    };
    readonly tokenStatistics: { [id: string]: ITokenStatistic | undefined };
}

export interface IBaseTestData {
    readonly updatedAtTimestamp: string;
    readonly updatedAtBlockNumber: string;
    readonly token: string;
}

export interface IStreamLocalData extends IAggregateLocalData {
    readonly flowOperators: { [id: string]: IFlowOperator | undefined };
    readonly revisionIndexes: { [id: string]: number | undefined };
    readonly periodRevisionIndexes: { [id: string]: number | undefined };
    readonly streamData: { [id: string]: IStreamData | undefined };
}
export interface IDistributionLocalData extends IAggregateLocalData {
    readonly indexes: { [id: string]: IIndex | undefined };
    readonly subscriptions: { [id: string]: IIndexSubscription | undefined };
}

export interface IFlowUpdatedInitTestData {
    readonly updatedAtTimestamp: string;
    readonly updatedAtBlockNumber: string;
    readonly data: ITestModifyFlowData;
}

export interface IFlowOperatorUpdatedInitTestData extends IBaseTestData {
    readonly flowOperators: { [id: string]: IFlowOperator | undefined };
    readonly accountTokenSnapshots: {
        [id: string]: IAccountTokenSnapshot | undefined;
    };
    readonly flowOperatorId: string;
    readonly senderId: string;
}

export interface IBaseDistributionTesterParams {
    readonly token: string;
    readonly publisher: string;
    readonly indexId: number;
    readonly userData: string;
}

export interface ISubscriberDistributionTesterParams
    extends IBaseDistributionTesterParams {
    readonly subscriber: string;
}

export interface IExistingFlowUpdatedData {
    currentFlowOperator: IFlowOperator;
    currentReceiverATS: IAccountTokenSnapshot;
    currentSenderATS: IAccountTokenSnapshot;
    currentTokenStats: ITokenStatistic;
    pastStreamData: IStreamData;
    revisionIndexId: string;
}

export interface IFlowUpdatedUpdateTestData {
    readonly existingData: IExistingFlowUpdatedData;
    readonly data: ITestModifyFlowData;
    readonly lastUpdatedBlockNumber: string;
    readonly lastUpdatedAtTimestamp: string;
    readonly flowRate: BigNumber;
    readonly depositDelta: BigNumber;
}

// TODO: there needs to be a better name for this
export interface ITestModifyFlowData {
    readonly framework: Framework;
    readonly superToken: SuperToken;
    readonly localData: IStreamLocalData;
    readonly provider: BaseProvider;
    readonly actionType: FlowActionType;
    readonly atsArray: IAccountTokenSnapshot[];
    readonly newFlowRate: number;
    readonly sender: string;
    readonly receiver: string;
    readonly flowOperator: string;
    readonly tokenAddress: string;
    readonly totalSupply?: string;
    readonly liquidator?: string;
}

export interface ITestUpdateFlowOperatorData {
    readonly isCreate: boolean;
    readonly framework: Framework;
    readonly provider: BaseProvider;
    readonly superToken: SuperToken;
    readonly isFullControlRevoke: boolean;
    readonly isFullControl: boolean;
    readonly sender: string;
    readonly permissions: number;
    readonly flowOperator: string;
    readonly flowRateAllowance: string;
    readonly accountTokenSnapshots: {
        [id: string]: IAccountTokenSnapshot | undefined;
    };
    readonly flowOperators: { [id: string]: IFlowOperator | undefined };
}

export interface ITestModifyIDAData {
    readonly framework: Framework;
    readonly superToken: SuperToken;
    readonly provider: BaseProvider;
    readonly atsArray: IAccountTokenSnapshot[];
    readonly localData: IDistributionLocalData;
    readonly baseParams: ISubscriberDistributionTesterParams;
    readonly eventType: IDAEventType;
    readonly units?: BigNumber;
    readonly isRevoke?: boolean;
    readonly sender?: string;
    readonly isDistribute?: boolean;
    readonly amountOrIndexValue?: BigNumber;
}

export interface IEventQueryData {
    readonly query: string;
    readonly queryName: string;
}

export interface IExtraEventData {
    readonly units?: BigNumber;
    readonly oldIndexValue?: string;
    readonly newIndexValue?: BigNumber;
    readonly totalUnitsApproved?: BigNumber;
    readonly totalUnitsPending?: BigNumber;
    readonly distributionDelta?: BigNumber;
    readonly logIndex?: number;
    readonly order?: number;
}

export interface IExtraExpectedData extends IExtraEventData {
    readonly isRevoke?: boolean;
    readonly totalUnits?: BigNumber;
}

export interface IInstantDistributionLocalData extends IAggregateLocalData {
    readonly indexes: { [id: string]: IIndex | undefined };
    readonly subscriptions: { [id: string]: IIndexSubscription | undefined };
}

export interface IInstantDistributionTestData
    extends IInstantDistributionLocalData,
        IBaseTestData {
    readonly publisher: string;
    readonly subscriber?: string;
    readonly indexId: string;
}

export interface IIDAEvents {
    readonly IndexCreatedEvent?: IEvent;
    readonly IndexDistributionClaimedEvent?: IEvent;
    readonly IndexUpdatedEvent?: IEvent;
    readonly IndexSubscribedEvent?: IEvent;
    readonly IndexUnitsUpdatedEvent?: IEvent;
    readonly IndexUnsubscribedEvent?: IEvent;
    readonly SubscriptionApprovedEvent?: IEvent;
    readonly SubscriptionDistributionClaimedEvent?: IEvent;
    readonly SubscriptionRevokedEvent?: IEvent;
    readonly SubscriptionUnitsUpdatedEvent?: IEvent;
}

export interface IBaseIDAEvent {
    readonly token: string;
    readonly publisher: string;
    readonly indexId: string;
    readonly userData: string;
}

export interface IExpectedIndexUpdatedEvent extends IBaseIDAEvent {
    readonly oldIndexValue: string;
    readonly newIndexValue: string;
    readonly totalUnitsPending: string;
    readonly totalUnitsApproved: string;
}

export interface IExpectedSubscriberEvent extends IBaseIDAEvent {
    readonly subscriber: ILightEntity;
}

export interface IExpectedSubscriptionUnitsUpdatedEvent
    extends IExpectedSubscriberEvent {
    readonly units: string;
}

export interface IExpectedFlowUpdateEvent {
    readonly addresses: string[];
    readonly token: string;
    readonly sender: string;
    readonly receiver: string;
    readonly flowOperator: string;
    readonly flowRate: string;
    readonly totalAmountStreamedUntilTimestamp: string;
    readonly totalReceiverFlowRate: string;
    readonly totalSenderFlowRate: string;
    readonly deposit: string;
    readonly oldFlowRate: string;
    readonly type: FlowActionType;
    readonly logIndex?: number;
    readonly order?: number;
}

export interface IExpectedFlowOperatorUpdatedEvent {
    readonly addresses: string[];
    readonly token: string;
    readonly sender: string;
    readonly permissions: number;
    readonly flowRateAllowance: string;
    readonly logIndex?: number;
    readonly order?: number;
}

export interface IGetExpectedIDADataParams {
    readonly token: SuperToken;
    readonly atsArray: IAccountTokenSnapshot[];
    readonly currentIndex: IIndex;
    readonly currentPublisherATS: IAccountTokenSnapshot;
    readonly currentSubscription: IIndexSubscription;
    readonly currentSubscriberATS: IAccountTokenSnapshot;
    readonly currentTokenStats: ITokenStatistic;
    readonly updatedAtBlockNumber: string;
    readonly timestamp: string;
    readonly provider: BaseProvider;
    readonly isEventEmitted: boolean;
}
