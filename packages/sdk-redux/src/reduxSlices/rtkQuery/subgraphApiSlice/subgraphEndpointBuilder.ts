import {type EndpointBuilder} from '@reduxjs/toolkit/query';

import {CacheTagType} from '../cacheTags/CacheTagTypes';

import {SubgraphBaseQuery} from './subgraphBaseQuery';
import {SubgraphReducerPath} from './subgraphReducerPath';

export type SubgraphEndpointBuilder = EndpointBuilder<SubgraphBaseQuery, CacheTagType, SubgraphReducerPath>;
