import {
    Account,
    AccountQueryHandler,
    AccountTokenSnapshot,
    AccountTokenSnapshotLog,
    AccountTokenSnapshotLogQueryHandler,
    AccountTokenSnapshotQueryHandler,
    FlowOperator,
    FlowOperatorQueryHandler,
    ILightEntity,
    Index,
    IndexQueryHandler,
    IndexSubscription,
    IndexSubscriptionQueryHandler,
    PagedResult,
    Pool,
    PoolDistributor,
    PoolDistributorQueryHandler,
    PoolMember,
    PoolMemberQueryHandler,
    PoolQueryHandler,
    RelevantAddressProviderFromFilter,
    RelevantAddressProviderFromResult,
    Stream,
    StreamPeriod,
    StreamPeriodQueryHandler,
    StreamQueryHandler,
    SubgraphGetQuery,
    SubgraphGetQueryHandler,
    SubgraphListQuery,
    SubgraphListQueryHandler,
    Token,
    TokenQueryHandler,
    TokenStatistic,
    TokenStatisticLog,
    TokenStatisticLogQueryHandler,
    TokenStatisticQueryHandler,
} from '@superfluid-finance/sdk-core';

import {getSubgraphClient} from '../../../../sdkReduxConfig';
import {createGeneralTags} from '../../cacheTags/CacheTagTypes';
import {CacheTime} from '../../cacheTime';
import {provideSpecificCacheTagsFromRelevantAddresses} from '../provideSpecificCacheTagsFromRelevantAddresses';
import {SubgraphEndpointBuilder} from '../subgraphEndpointBuilder';

import {
    AccountQuery,
    AccountsQuery,
    AccountTokenSnapshotLogQuery,
    AccountTokenSnapshotLogsQuery,
    AccountTokenSnapshotQuery,
    AccountTokenSnapshotsQuery,
    FlowOperatorQuery,
    FlowOperatorsQuery,
    IndexesQuery,
    IndexQuery,
    IndexSubscriptionQuery,
    IndexSubscriptionsQuery,
    PoolDistributorQuery,
    PoolDistributorsQuery,
    PoolMemberQuery,
    PoolMembersQuery,
    PoolQuery,
    PoolsQuery,
    StreamPeriodQuery,
    StreamPeriodsQuery,
    StreamQuery,
    StreamsQuery,
    TokenQuery,
    TokensQuery,
    TokenStatisticLogQuery,
    TokenStatisticLogsQuery,
    TokenStatisticQuery,
    TokenStatisticsQuery,
} from './entityArgs';

export const createEntityEndpoints = (builder: SubgraphEndpointBuilder) => {
    // NOTE: Ignoring prettier because longer lines are more readable here.
    // prettier-ignore
    return {
        account: get<Account, AccountQuery>(builder, new AccountQueryHandler()),
        accounts: list<Account, AccountsQuery>(builder, new AccountQueryHandler()),
        accountTokenSnapshot: get<AccountTokenSnapshot, AccountTokenSnapshotQuery>(builder, new AccountTokenSnapshotQueryHandler()),
        accountTokenSnapshots: list<AccountTokenSnapshot, AccountTokenSnapshotsQuery>(builder, new AccountTokenSnapshotQueryHandler()),
        accountTokenSnapshotLog: get<AccountTokenSnapshotLog, AccountTokenSnapshotLogQuery>(builder, new AccountTokenSnapshotLogQueryHandler()),
        accountTokenSnapshotLogs: list<AccountTokenSnapshotLog, AccountTokenSnapshotLogsQuery>(builder, new AccountTokenSnapshotLogQueryHandler()),
        index: get<Index, IndexQuery>(builder, new IndexQueryHandler()),
        indexes: list<Index, IndexesQuery>(builder, new IndexQueryHandler()),
        indexSubscription: get<IndexSubscription, IndexSubscriptionQuery>(builder, new IndexSubscriptionQueryHandler()),
        indexSubscriptions: list<IndexSubscription, IndexSubscriptionsQuery>(builder, new IndexSubscriptionQueryHandler()),
        stream: get<Stream, StreamQuery>(builder, new StreamQueryHandler()),
        streams: list<Stream, StreamsQuery>(builder, new StreamQueryHandler()),
        streamPeriod: get<StreamPeriod, StreamPeriodQuery>(builder, new StreamPeriodQueryHandler()),
        streamPeriods: list<StreamPeriod, StreamPeriodsQuery>(builder, new StreamPeriodQueryHandler()),
        token: get<Token, TokenQuery>(builder, new TokenQueryHandler(), CacheTime.ThreeMinutes),
        tokens: list<Token, TokensQuery>(builder, new TokenQueryHandler()),
        tokenStatistic: get<TokenStatistic, TokenStatisticQuery>(builder, new TokenStatisticQueryHandler()),
        tokenStatistics: list<TokenStatistic, TokenStatisticsQuery>(builder, new TokenStatisticQueryHandler()),
        tokenStatisticLog: get<TokenStatisticLog, TokenStatisticLogQuery>(builder, new TokenStatisticLogQueryHandler()),
        tokenStatisticLogs: list<TokenStatisticLog, TokenStatisticLogsQuery>(builder, new TokenStatisticLogQueryHandler()),
        flowOperator: get<FlowOperator, FlowOperatorQuery>(builder, new FlowOperatorQueryHandler()),
        flowOperators: list<FlowOperator, FlowOperatorsQuery>(builder, new FlowOperatorQueryHandler()),
        pool: get<Pool, PoolQuery>(builder, new PoolQueryHandler()),
        pools: list<Pool, PoolsQuery>(builder, new PoolQueryHandler()),
        poolMember: get<PoolMember, PoolMemberQuery>(builder, new PoolMemberQueryHandler()),
        poolMembers: list<PoolMember, PoolMembersQuery>(builder, new PoolMemberQueryHandler()),
        poolDistributor: get<PoolDistributor, PoolDistributorQuery>(builder, new PoolDistributorQueryHandler()),
        poolDistributors: list<PoolDistributor, PoolDistributorsQuery>(builder, new PoolDistributorQueryHandler()),
    };
};

/**
 * Creates "get" endpoint.
 */
function get<TReturn extends ILightEntity, TQuery extends {chainId: number} & SubgraphGetQuery>(
    builder: SubgraphEndpointBuilder,
    queryHandler: SubgraphGetQueryHandler<TReturn> & RelevantAddressProviderFromResult<TReturn>,
    cacheTime?: CacheTime
) {
    return builder.query<TReturn | null, TQuery>({
        queryFn: async (arg) => {
            const subgraphClient = await getSubgraphClient(arg.chainId);
            return {
                data: await queryHandler.get(subgraphClient, arg),
            };
        },
        providesTags: (result, _error, arg) => [
            ...createGeneralTags({chainId: arg.chainId}),
            ...provideSpecificCacheTagsFromRelevantAddresses(
                arg.chainId,
                queryHandler.getRelevantAddressesFromResult(result)
            ),
        ],
        keepUnusedDataFor: cacheTime ?? CacheTime.OneMinute,
    });
}

/**
 * Creates "list" endpoint.
 */
function list<
    TReturn extends ILightEntity,
    TQuery extends {chainId: number} & SubgraphListQuery<TFilter, TOrderBy>,
    TFilter extends {[key: string]: unknown} = NonNullable<TQuery['filter']>,
    TOrderBy extends string = NonNullable<TQuery['order']>['orderBy'],
>(
    builder: SubgraphEndpointBuilder,
    queryHandler: SubgraphListQueryHandler<TReturn, TQuery, TFilter> & RelevantAddressProviderFromFilter<TFilter>,
    cacheTime?: CacheTime
) {
    return builder.query<PagedResult<TReturn>, TQuery>({
        queryFn: async (arg) => {
            const subgraphClient = await getSubgraphClient(arg.chainId);
            return {
                data: await queryHandler.list(subgraphClient, arg),
            };
        },
        providesTags: (_result, _error, arg) => [
            ...createGeneralTags({chainId: arg.chainId}),
            ...provideSpecificCacheTagsFromRelevantAddresses(
                arg.chainId,
                queryHandler.getRelevantAddressesFromFilter(arg.filter)
            ),
        ],
        keepUnusedDataFor: cacheTime ?? CacheTime.OneMinute,
    });
}
