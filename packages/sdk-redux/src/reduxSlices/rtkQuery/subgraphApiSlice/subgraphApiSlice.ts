import {type CreateApi} from '@reduxjs/toolkit/query';
import {coreModuleName} from '@reduxjs/toolkit/query';

import {typeGuard} from '../../../utils';
import {cacheTagTypes} from '../cacheTags/CacheTagTypes';
import {CacheTime} from '../cacheTime';
import {getSerializeQueryArgs} from '../getSerializeQueryArgs';

type ModuleName = typeof coreModuleName;

import {subgraphBaseQuery} from './subgraphBaseQuery';
import {SubgraphEndpointBuilder} from './subgraphEndpointBuilder';
import {SubgraphReducerPath} from './subgraphReducerPath';

export const createSubgraphApiSlice = <T extends ModuleName>(createRtkQueryApi: CreateApi<T>) =>
    createRtkQueryApi({
        keepUnusedDataFor: CacheTime.OneMinute,
        reducerPath: typeGuard<SubgraphReducerPath>('superfluid_subgraph'),
        baseQuery: subgraphBaseQuery(),
        tagTypes: cacheTagTypes,
        endpoints: (_builder: SubgraphEndpointBuilder) => ({}),
        serializeQueryArgs: getSerializeQueryArgs(),
    });

export type SubgraphApiSliceEmpty = ReturnType<typeof createSubgraphApiSlice>;
