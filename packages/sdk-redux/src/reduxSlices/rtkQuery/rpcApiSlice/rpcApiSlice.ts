import {type CreateApi} from '@reduxjs/toolkit/query';

import {typeGuard} from '../../../utils';
import {type ModuleName} from '../ModuleName';
import {cacheTagTypes} from '../cacheTags/CacheTagTypes';
import {getSerializeQueryArgs} from '../getSerializeQueryArgs';

import {rpcBaseQuery} from './rpcBaseQuery';
import {type RpcEndpointBuilder} from './rpcEndpointBuilder';
import {type RpcReducerPath} from './rpcReducerPath';

export const createRpcApiSlice = <T extends ModuleName>(createRtkQueryApi: CreateApi<T>) =>
    createRtkQueryApi({
        reducerPath: typeGuard<RpcReducerPath>('superfluid_rpc'),
        baseQuery: rpcBaseQuery(),
        tagTypes: cacheTagTypes,
        endpoints: (_builder: RpcEndpointBuilder) => ({}),
        serializeQueryArgs: getSerializeQueryArgs(),
    });

export type RpcApiSliceEmpty = ReturnType<typeof createRpcApiSlice>;
