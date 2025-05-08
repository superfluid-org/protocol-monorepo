import * as events from "./events";
import { EventsQuery } from "./subgraph/events/events.generated";
import { typeGuard } from "./utils";

export const mapGetAllEventsQueryEvents = (
    queryEvents: EventsQuery["events"]
): events.AllEvents[] => {
    return queryEvents.map((x) => {
        switch (x.__typename) {
            case "AppRegisteredEvent":
                return typeGuard<events.AppRegisteredEvent>({
                    name: "AppRegistered",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    app: x.app,
                });
            case "AgreementClassRegisteredEvent":
                return typeGuard<events.AgreementClassRegisteredEvent>({
                    name: "AgreementClassRegistered",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    agreementType: x.agreementType,
                    code: x.code,
                });
            case "AgreementClassUpdatedEvent":
                return typeGuard<events.AgreementClassUpdatedEvent>({
                    name: "AgreementClassUpdated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    agreementType: x.agreementType,
                    code: x.code,
                });
            case "AgreementLiquidatedByEvent":
                return typeGuard<events.AgreementLiquidatedByEvent>({
                    name: "AgreementLiquidatedBy",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    agreementClass: x.agreementClass,
                    agreementId: x.agreementId,
                    bailoutAmount: x.bailoutAmount,
                    bondAccount: x.bondAccount,
                    liquidatorAccount: x.liquidatorAccount,
                    penaltyAccount: x.penaltyAccount,
                    rewardAmount: x.rewardAmount,
                    token: x.token,
                });
            case "AgreementLiquidatedV2Event":
                return typeGuard<events.AgreementLiquidatedV2Event>({
                    name: "AgreementLiquidatedV2",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    liquidatorAccount: x.liquidatorAccount,
                    agreementClass: x.agreementClass,
                    agreementId: x.agreementId,
                    targetAccount: x.targetAccount,
                    rewardAmountReceiver: x.rewardAmountReceiver,
                    rewardAmount: x.rewardAmount,
                    targetAccountBalanceDelta: x.targetAccountBalanceDelta,
                    version: x.version,
                    liquidationType: x.liquidationType,

                    // TO BE DEPRECATED in v2 endpoint - use rewardAmountReceiver instead
                    rewardAccount: x.rewardAccount,
                });
            case "BurnedEvent":
                return typeGuard<events.BurnedEvent>({
                    name: "Burned",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    amount: x.amount,
                    data: x.data,
                    from: x.from,
                    operator: x.operator,
                    token: x.token,
                    operatorData: x.operatorData,
                });
            case "CFAv1LiquidationPeriodChangedEvent":
                return typeGuard<events.CFAv1LiquidationPeriodChangedEvent>({
                    name: "CFAv1LiquidationPeriodChanged",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    host: x.host,
                    governanceAddress: x.governanceAddress,
                    isKeySet: x.isKeySet,
                    liquidationPeriod: Number(x.liquidationPeriod),
                    superToken: x.superToken,
                }) as events.CFAv1LiquidationPeriodChangedEvent;
            case "ConfigChangedEvent":
                return typeGuard<events.ConfigChangedEvent>({
                    name: "ConfigChanged",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    host: x.host,
                    governanceAddress: x.governanceAddress,
                    isKeySet: x.isKeySet,
                    key: x.key,
                    superToken: x.superToken,
                    value: x.value,
                }) as events.ConfigChangedEvent;
            case "CustomSuperTokenCreatedEvent":
                return typeGuard<events.CustomSuperTokenCreatedEvent>({
                    name: "CustomSuperTokenCreated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                }) as events.CustomSuperTokenCreatedEvent;
            case "FlowUpdatedEvent":
                return typeGuard<events.FlowUpdatedEvent>({
                    name: "FlowUpdated",
                    type: mapNumberToFlowUpdateType(x.type),
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    flowRate: x.flowRate,
                    receiver: x.receiver,
                    sender: x.sender,
                    flowOperator: x.flowOperator,
                    deposit: x.deposit,
                    streamId: x.stream.id,
                });
            case "FlowOperatorUpdatedEvent":
                return typeGuard<events.FlowOperatorUpdatedEvent>({
                    name: "FlowOperatorUpdated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    sender: x.sender,
                    permissions: x.permissions,
                    flowRateAllowance: x.flowRateAllowance,
                });
            case "GovernanceReplacedEvent":
                return typeGuard<events.GovernanceReplacedEvent>({
                    name: "GovernanceReplaced",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    oldGovernance: x.oldGovernance,
                    newGovernance: x.newGovernance,
                });
            case "IndexCreatedEvent":
                return typeGuard<events.IndexCreatedEvent>({
                    name: "IndexCreated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    index: x.index.id,
                    indexId: x.indexId,
                    publisher: x.publisher,
                    userData: x.userData,
                });
            case "IndexDistributionClaimedEvent":
                return typeGuard<events.IndexDistributionClaimedEvent>({
                    name: "IndexDistributionClaimed",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    amount: x.amount,
                    index: x.index.id,
                    indexId: x.indexId,
                    publisher: x.publisher,
                    subscriber: x.subscriber,
                });
            case "IndexSubscribedEvent":
                return typeGuard<events.IndexSubscribedEvent>({
                    name: "IndexSubscribed",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    index: x.index.id,
                    indexId: x.indexId,
                    publisher: x.publisher,
                    subscriber: x.subscriber,
                });
            case "IndexUnitsUpdatedEvent":
                return typeGuard<events.IndexUnitsUpdatedEvent>({
                    name: "IndexUnitsUpdated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    index: x.index.id,
                    indexId: x.indexId,
                    publisher: x.publisher,
                    subscriber: x.subscriber,
                    units: x.units,
                    oldUnits: x.oldUnits,
                    userData: x.userData,
                });
            case "IndexUnsubscribedEvent":
                return typeGuard<events.IndexUnsubscribedEvent>({
                    name: "IndexUnsubscribed",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    index: x.index.id,
                    indexId: x.indexId,
                    publisher: x.publisher,
                    subscriber: x.subscriber,
                    userData: x.userData,
                });
            case "IndexUpdatedEvent":
                return typeGuard<events.IndexUpdatedEvent>({
                    name: "IndexUpdated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    index: x.index.id,
                    indexId: x.indexId,
                    newIndexValue: x.newIndexValue,
                    oldIndexValue: x.oldIndexValue,
                    publisher: x.publisher,
                    totalUnitsApproved: x.totalUnitsApproved,
                    totalUnitsPending: x.totalUnitsPending,
                    userData: x.userData,
                });
            case "JailEvent":
                return typeGuard<events.JailEvent>({
                    name: "Jail",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    app: x.app,
                    reason: x.reason,
                });
            case "MintedEvent":
                return typeGuard<events.MintedEvent>({
                    name: "Minted",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    operator: x.operator,
                    to: x.to,
                    amount: x.amount,
                    data: x.data,
                    token: x.token,
                    operatorData: x.operatorData,
                });
            case "RewardAddressChangedEvent":
                return typeGuard<events.RewardAddressChangedEvent>({
                    name: "RewardAddressChanged",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    host: x.host,
                    governanceAddress: x.governanceAddress,
                    superToken: x.superToken,
                    isKeySet: x.isKeySet,
                    rewardAddress: x.rewardAddress,
                });
            case "RoleAdminChangedEvent":
                return typeGuard<events.RoleAdminChangedEvent>({
                    name: "RoleAdminChanged",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    role: x.role,
                    previousAdminRole: x.previousAdminRole,
                    newAdminRole: x.newAdminRole,
                });
            case "RoleGrantedEvent":
                return typeGuard<events.RoleGrantedEvent>({
                    name: "RoleGranted",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    role: x.role,
                    account: x.account,
                    sender: x.sender,
                });
            case "RoleRevokedEvent":
                return typeGuard<events.RoleRevokedEvent>({
                    name: "RoleRevoked",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    role: x.role,
                    account: x.account,
                    sender: x.sender,
                });
            case "SetEvent":
                return typeGuard<events.SetEvent>({
                    name: "Set",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    hashedName: x.hashedName,
                    targetAddress: x.target,
                    resolverEntry: x.resolverEntry.id,
                });
            case "SentEvent":
                return typeGuard<events.SentEvent>({
                    name: "Sent",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    operator: x.operator,
                    to: x.to,
                    amount: x.amount,
                    data: x.data,
                    token: x.token,
                    operatorData: x.operatorData,
                });
            case "SubscriptionApprovedEvent":
                return typeGuard<events.SubscriptionApprovedEvent>({
                    name: "SubscriptionApproved",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    subscriber: x.subscriber,
                    publisher: x.publisher,
                    indexId: x.indexId,
                    userData: x.userData,
                    subscription: x.subscription.id,
                });
            case "SubscriptionDistributionClaimedEvent":
                return typeGuard<events.SubscriptionDistributionClaimedEvent>({
                    name: "SubscriptionDistributionClaimed",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    subscriber: x.subscriber,
                    publisher: x.publisher,
                    indexId: x.indexId,
                    amount: x.amount,
                    subscription: x.subscription.id,
                });
            case "SubscriptionRevokedEvent":
                return typeGuard<events.SubscriptionRevokedEvent>({
                    name: "SubscriptionRevoked",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    subscriber: x.subscriber,
                    publisher: x.publisher,
                    indexId: x.indexId,
                    userData: x.userData,
                    subscription: x.subscription.id,
                });
            case "SubscriptionUnitsUpdatedEvent":
                return typeGuard<events.SubscriptionUnitsUpdatedEvent>({
                    name: "SubscriptionUnitsUpdated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    subscriber: x.subscriber,
                    publisher: x.publisher,
                    indexId: x.indexId,
                    units: x.units,
                    userData: x.userData,
                    subscription: x.subscription.id,
                });
            case "SuperTokenCreatedEvent":
                return typeGuard<events.SuperTokenCreatedEvent>({
                    name: "SuperTokenCreated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                });
            case "SuperTokenFactoryUpdatedEvent":
                return typeGuard<events.SuperTokenFactoryUpdatedEvent>({
                    name: "SuperTokenFactoryUpdated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    newFactory: x.newFactory,
                });
            case "SuperTokenLogicCreatedEvent":
                return typeGuard<events.SuperTokenLogicCreatedEvent>({
                    name: "SuperTokenLogicCreated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    tokenLogic: x.tokenLogic,
                });
            case "SuperTokenLogicUpdatedEvent":
                return typeGuard<events.SuperTokenLogicUpdatedEvent>({
                    name: "SuperTokenLogicUpdated",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    code: x.code,
                }) as events.SuperTokenLogicUpdatedEvent;
            case "PPPConfigurationChangedEvent":
                return typeGuard<events.PPPConfigurationChangedEvent>({
                    name: "PPPConfigurationChanged",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    host: x.host,
                    governanceAddress: x.governanceAddress,
                    superToken: x.superToken,
                    isKeySet: x.isKeySet,
                    liquidationPeriod: x.liquidationPeriod,
                    patricianPeriod: x.patricianPeriod,
                });
            case "TokenDowngradedEvent":
                return typeGuard<events.TokenDowngradedEvent>({
                    name: "TokenDowngraded",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    amount: x.amount,
                    token: x.token,
                    account: x.account.id,
                });
            case "TokenUpgradedEvent":
                return typeGuard<events.TokenUpgradedEvent>({
                    name: "TokenUpgraded",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    amount: x.amount,
                    token: x.token,
                    account: x.account.id,
                });
            case "TransferEvent":
                return typeGuard<events.TransferEvent>({
                    name: "Transfer",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    from: x.from.id,
                    to: x.to.id,
                    token: x.token,
                    value: x.value,
                });
            case "TrustedForwarderChangedEvent":
                return typeGuard<events.TrustedForwarderChangedEvent>({
                    name: "TrustedForwarderChanged",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    host: x.host,
                    governanceAddress: x.governanceAddress,
                    superToken: x.superToken,
                    isKeySet: x.isKeySet,
                    forwarder: x.forwarder,
                    enabled: x.enabled,
                });
            case "SuperTokenMinimumDepositChangedEvent":
                return typeGuard<events.SuperTokenMinimumDepositChangedEvent>({
                    name: "SuperTokenMinimumDepositChanged",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    host: x.host,
                    governanceAddress: x.governanceAddress,
                    superToken: x.superToken,
                    isKeySet: x.isKeySet,
                    minimumDeposit: x.minimumDeposit,
                });
            case "NewPICEvent":
                return typeGuard<events.NewPICEvent>({
                    name: "NewPIC",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    pic: x.pic,
                    bond: x.bond,
                    exitRate: x.exitRate,
                });
            case "ExitRateChangedEvent":
                return typeGuard<events.ExitRateChangedEvent>({
                    name: "ExitRateChanged",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    exitRate: x.exitRate,
                });
            case "BondIncreasedEvent":
                return typeGuard<events.BondIncreasedEvent>({
                    name: "BondIncreased",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                    token: x.token,
                    additionalBond: x.additionalBond,
                });
            case "PoolCreatedEvent":
                return typeGuard<events.PoolCreatedEvent>({
                    name: "PoolCreatedEvent",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                });
            case "PoolConnectionUpdatedEvent":
                return typeGuard<events.PoolConnectionUpdatedEvent>({
                    name: "PoolConnectionUpdatedEvent",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                });
            case "BufferAdjustedEvent":
                return typeGuard<events.BufferAdjustedEvent>({
                    name: "BufferAdjustedEvent",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                });
            case "InstantDistributionUpdatedEvent":
                return typeGuard<events.InstantDistributionUpdatedEvent>({
                    name: "InstantDistributionUpdatedEvent",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                });
            case "FlowDistributionUpdatedEvent":
                return typeGuard<events.FlowDistributionUpdatedEvent>({
                    name: "FlowDistributionUpdatedEvent",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                });
            case "DistributionClaimedEvent":
                return typeGuard<events.DistributionClaimedEvent>({
                    name: "DistributionClaimedEvent",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                });
            case "MemberUnitsUpdatedEvent":
                return typeGuard<events.MemberUnitsUpdatedEvent>({
                    name: "MemberUnitsUpdatedEvent",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                });
            case "ApprovalEvent":
                return typeGuard<events.ApprovalEvent>({
                    name: "ApprovalEvent",
                    id: x.id,
                    blockNumber: Number(x.blockNumber),
                    transactionHash: x.transactionHash,
                    gasPrice: x.gasPrice,
                    order: Number(x.order),
                    timestamp: Number(x.timestamp),
                    logIndex: Number(x.logIndex),
                });
            default:
                // eslint-disable-next-line no-case-declarations
                const eventBase = x as events.EventBase;
                return typeGuard<events.UnknownEvent>({
                    // force casted as empty string for the type system
                    name: eventBase.name as "",
                    id: eventBase.id,
                    blockNumber: eventBase.blockNumber,
                    transactionHash: eventBase.transactionHash,
                    gasPrice: eventBase.gasPrice,
                    order: eventBase.order,
                    timestamp: eventBase.timestamp,
                    logIndex: eventBase.logIndex,
                });
        }
    });
};

const mapNumberToFlowUpdateType = (type: number): events.FlowUpdateType => {
    if (type === 0) {
        return events.FlowUpdateType.Create;
    } else if (type === 1) {
        return events.FlowUpdateType.Update;
    } else if (type === 2) {
        return events.FlowUpdateType.Terminate;
    } else {
        throw Error(`Mapping error: unknown flow update type ([${type}]).`);
    }
};
