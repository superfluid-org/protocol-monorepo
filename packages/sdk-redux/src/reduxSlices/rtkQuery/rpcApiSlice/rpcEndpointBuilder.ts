import {type EndpointBuilder} from '@reduxjs/toolkit/query';

import {type CacheTagType} from '../cacheTags/CacheTagTypes';

import {type RpcBaseQuery} from './rpcBaseQuery';
import {type RpcReducerPath} from './rpcReducerPath';

export type RpcEndpointBuilder = EndpointBuilder<RpcBaseQuery, CacheTagType, RpcReducerPath>;
