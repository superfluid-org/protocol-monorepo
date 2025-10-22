import {getFramework, getSubgraphClient} from '../../../../sdkReduxConfig';
import {MillisecondTimes} from '../../../../utils';
import {invalidateSpecificCacheTagsForEvents} from '../../cacheTags/invalidateSpecificCacheTagsForEvents';
import {CacheTime} from '../../cacheTime';
import {type SubgraphEndpointBuilder} from '../subgraphEndpointBuilder';

import {type CustomSubgraphQuery, type MonitorForEventsToInvalidateCacheMutation} from './baseArgs';

export const createBaseEndpoints = (builder: SubgraphEndpointBuilder) => ({
    custom: builder.query<unknown, CustomSubgraphQuery>({
        keepUnusedDataFor: CacheTime.None,
        queryFn: async (arg) => {
            const subgraphClient = await getSubgraphClient(arg.chainId);
            return {
                data: await subgraphClient.request<unknown>(arg.document, arg.variables),
            };
        },
    }),
    monitorForEventsToInvalidateCache: builder.mutation<true, MonitorForEventsToInvalidateCacheMutation>({
        queryFn: () => {
            // No-op
            return {
                data: true,
            };
        },
        onCacheEntryAdded: async (arg, {dispatch, cacheDataLoaded, cacheEntryRemoved}) => {
            const framework = await getFramework(arg.chainId);

            await cacheDataLoaded;

            const unsubscribe = framework.query.on(
                (events) => {
                    invalidateSpecificCacheTagsForEvents(arg.chainId, events, dispatch);
                },
                MillisecondTimes.TwentySeconds,
                arg.address
            );

            try {
                await cacheEntryRemoved;
            } finally {
                unsubscribe();
            }
        },
    }),
});
