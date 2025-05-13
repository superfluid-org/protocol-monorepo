import {type RpcEndpointBuilder} from '../rpcEndpointBuilder';

import {createFlowEndpoints} from './flowEndpoints';
import {createIndexEndpoints} from './indexEndpoints';
import {createSuperTokenEndpoints} from './superTokenEndpoints';

export const allRpcEndpoints = {
    endpoints: (builder: RpcEndpointBuilder) =>
        Object.assign(createFlowEndpoints(builder), createIndexEndpoints(builder), createSuperTokenEndpoints(builder)),
};
