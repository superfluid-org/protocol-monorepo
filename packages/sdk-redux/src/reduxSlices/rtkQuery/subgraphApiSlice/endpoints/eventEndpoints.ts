import {
    type AllEvents,
    EventQueryHandler,
    type FlowUpdatedEvent,
    FlowUpdatedEventQueryHandler,
    type ILightEntity,
    type IndexUpdatedEvent,
    IndexUpdatedEventQueryHandler,
    type PagedResult,
    type RelevantAddressProviderFromFilter,
    type RelevantAddressProviderFromResult,
    type SubgraphGetQuery,
    SubgraphGetQueryHandler,
    type SubgraphListQuery,
    SubgraphListQueryHandler,
    type SubscriptionUnitsUpdatedEvent,
    SubscriptionUnitsUpdatedEventQueryHandler,
    type TransferEvent,
    TransferEventQueryHandler,
} from '@superfluid-finance/sdk-core';

import {getSubgraphClient} from '../../../../sdkReduxConfig';
import {createGeneralTags} from '../../cacheTags/CacheTagTypes';
import {CacheTime} from '../../cacheTime';
import {provideSpecificCacheTagsFromRelevantAddresses} from '../provideSpecificCacheTagsFromRelevantAddresses';
import {type SubgraphEndpointBuilder} from '../subgraphEndpointBuilder';

import type {
    EventQuery,
    EventsQuery,
    FlowUpdatedEventQuery,
    FlowUpdatedEventsQuery,
    IndexUpdatedEventQuery,
    IndexUpdatedEventsQuery,
    SubscriptionUnitsUpdatedEventQuery,
    SubscriptionUnitsUpdatedEventsQuery,
    TransferEventQuery,
    TransferEventsQuery,
} from './eventArgs';

export const createEventQueryEndpoints = (builder: SubgraphEndpointBuilder) => {
    // NOTE: Ignoring prettier because longer lines are more readable here.
    // prettier-ignore
    return {
        event: get<AllEvents, EventQuery>(builder, new EventQueryHandler()),
        events: list<AllEvents, EventsQuery>(builder, new EventQueryHandler()),
        flowUpdatedEvent: get<FlowUpdatedEvent, FlowUpdatedEventQuery>(builder, new FlowUpdatedEventQueryHandler()),
        flowUpdatedEvents: list<FlowUpdatedEvent, FlowUpdatedEventsQuery>(builder, new FlowUpdatedEventQueryHandler()),
        indexUpdatedEvent: get<IndexUpdatedEvent, IndexUpdatedEventQuery>(builder, new IndexUpdatedEventQueryHandler()),
        indexUpdatedEvents: list<IndexUpdatedEvent, IndexUpdatedEventsQuery>(builder, new IndexUpdatedEventQueryHandler()),
        subscriptionUnitsUpdatedEvent: get<SubscriptionUnitsUpdatedEvent, SubscriptionUnitsUpdatedEventQuery>(builder, new SubscriptionUnitsUpdatedEventQueryHandler()),
        subscriptionUnitsUpdatedEvents: list<SubscriptionUnitsUpdatedEvent, SubscriptionUnitsUpdatedEventsQuery>(builder, new SubscriptionUnitsUpdatedEventQueryHandler()),
        transferEvent: get<TransferEvent, TransferEventQuery>(builder, new TransferEventQueryHandler()),
        transferEvents: list<TransferEvent, TransferEventsQuery>(builder, new TransferEventQueryHandler())
    };
};

/**
 * Creates "get" endpoint.
 */
function get<TReturn extends ILightEntity, TQuery extends {chainId: number} & SubgraphGetQuery>(
    builder: SubgraphEndpointBuilder,
    queryHandler: SubgraphGetQueryHandler<TReturn> & RelevantAddressProviderFromResult<TReturn>
) {
    return builder.query<TReturn | null, TQuery>({
        queryFn: async (arg) => {
            const subgraphClient = await getSubgraphClient(arg.chainId);
            return {
                data: await queryHandler.get(subgraphClient, arg),
            };
        },
        keepUnusedDataFor: CacheTime.Forever, // Events don't change (unless re-org but that's handled by invalidating whole cache anyway).
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
    queryHandler: SubgraphListQueryHandler<TReturn, TQuery, TFilter> & RelevantAddressProviderFromFilter<TFilter>
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
    });
}
