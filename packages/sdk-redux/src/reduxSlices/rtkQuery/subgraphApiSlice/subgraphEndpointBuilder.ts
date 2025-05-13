import {type EndpointBuilder} from '@reduxjs/toolkit/query';

import {type CacheTagType} from '../cacheTags/CacheTagTypes';

import {type SubgraphBaseQuery} from './subgraphBaseQuery';
import {type SubgraphReducerPath} from './subgraphReducerPath';

export type SubgraphEndpointBuilder = EndpointBuilder<SubgraphBaseQuery, CacheTagType, SubgraphReducerPath>;
