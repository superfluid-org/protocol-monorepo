import {type CreateApi} from '@reduxjs/toolkit/query';
import {coreModuleName} from '@reduxjs/toolkit/query';

import {typeGuard} from '../../../utils';
import {cacheTagTypes} from '../cacheTags/CacheTagTypes';
import {getSerializeQueryArgs} from '../getSerializeQueryArgs';

import {rpcBaseQuery} from './rpcBaseQuery';
import {RpcEndpointBuilder} from './rpcEndpointBuilder';
import {RpcReducerPath} from './rpcReducerPath';

type ModuleName = typeof coreModuleName;

export const createRpcApiSlice = <T extends ModuleName>(createRtkQueryApi: CreateApi<T>) =>
    createRtkQueryApi({
        reducerPath: typeGuard<RpcReducerPath>('superfluid_rpc'),
        baseQuery: rpcBaseQuery(),
        tagTypes: cacheTagTypes,
        endpoints: (_builder: RpcEndpointBuilder) => ({}),
        serializeQueryArgs: getSerializeQueryArgs(),
    });

export type RpcApiSliceEmpty = ReturnType<typeof createRpcApiSlice>;
