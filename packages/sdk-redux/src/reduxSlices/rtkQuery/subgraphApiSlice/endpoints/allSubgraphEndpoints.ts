import {type SubgraphEndpointBuilder} from '../subgraphEndpointBuilder';

import {createBaseEndpoints} from './baseEndpoints';
import {createEntityEndpoints} from './entityEndpoints';
import {createEventQueryEndpoints} from './eventEndpoints';

export const allSubgraphEndpoints = {
    endpoints: (builder: SubgraphEndpointBuilder) =>
        Object.assign(createBaseEndpoints(builder), createEntityEndpoints(builder), createEventQueryEndpoints(builder)),
};
