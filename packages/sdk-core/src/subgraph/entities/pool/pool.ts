import {
    Address,
    BigNumber,
    BlockNumber,
    Timestamp,
} from "../../mappedSubgraphTypes";
import { Pool_Filter, Pool_OrderBy } from "../../schema.generated";
import {
    RelevantAddressesIntermediate,
    SubgraphListQuery,
    SubgraphQueryHandler,
} from "../../subgraphQueryHandler";

import {
    GetPoolQuery,
    PoolsDocument,
    PoolsQuery,
    PoolsQueryVariables,
} from "./pools.generated";

export type PoolListQuery = SubgraphListQuery<Pool_Filter, Pool_OrderBy>;

export interface Pool {
    id: Address;
    createdAtTimestamp: Timestamp;
    createdAtBlockNumber: BlockNumber;
    updatedAtTimestamp: Timestamp;
    updatedAtBlockNumber: BlockNumber;
    totalAmountInstantlyDistributedUntilUpdatedAt: BigNumber;
    totalAmountFlowedDistributedUntilUpdatedAt: BigNumber;
    totalAmountDistributedUntilUpdatedAt: BigNumber;
    totalFlowAdjustmentAmountDistributedUntilUpdatedAt: BigNumber;
    totalUnits: BigNumber;
    totalConnectedUnits: BigNumber;
    totalDisconnectedUnits: BigNumber;
    perUnitSettledValue: BigNumber;
    perUnitFlowRate: BigNumber;
    /**
     * A member is any account which has more than 0 units in the pool.
     */
    totalMembers: number;
    /**
     * A connected member is any account which has more than 0 units in the pool and is connected.
     */
    totalConnectedMembers: number;
    /**
     * A disconnected member is any account which has more than 0 units in the pool and is not connected.
     */
    totalDisconnectedMembers: number;
    adjustmentFlowRate: BigNumber;
    flowRate: BigNumber;
    totalBuffer: BigNumber;
    token: Address;
    admin: Address;
}

export type SubgraphPool = NonNullable<Required<GetPoolQuery>["pool"]>;

export const mapSubgraphGDAPool = (x: SubgraphPool): Pool => {
    const mappedPool = {
        ...x,
        createdAtTimestamp: Number(x.createdAtTimestamp),
        createdAtBlockNumber: Number(x.createdAtBlockNumber),
        updatedAtTimestamp: Number(x.updatedAtTimestamp),
        updatedAtBlockNumber: Number(x.updatedAtBlockNumber),
        totalAmountInstantlyDistributedUntilUpdatedAt:
            x.totalAmountInstantlyDistributedUntilUpdatedAt,
        totalAmountFlowedDistributedUntilUpdatedAt:
            x.totalAmountFlowedDistributedUntilUpdatedAt,
        totalAmountDistributedUntilUpdatedAt:
            x.totalAmountDistributedUntilUpdatedAt,
        admin: x.admin.id,
        token: x.token.id,
    };

    return mappedPool;
};

export class PoolQueryHandler extends SubgraphQueryHandler<
    Pool,
    PoolListQuery,
    PoolsQuery,
    PoolsQueryVariables
> {
    getAddressFieldKeysFromFilter = (): {
        accountKeys: (keyof Pool_Filter)[];
        tokenKeys: (keyof Pool_Filter)[];
    } => ({
        accountKeys: ["admin", "id"],
        tokenKeys: ["token"],
    });

    getRelevantAddressesFromResultCore = (
        result: Pool
    ): RelevantAddressesIntermediate => ({
        tokens: [result.token],
        accounts: [result.admin, result.id],
    });

    mapFromSubgraphResponse = (response: PoolsQuery): Pool[] =>
        response.pools.map((x) => ({
            ...x,
            createdAtTimestamp: Number(x.createdAtTimestamp),
            createdAtBlockNumber: Number(x.createdAtBlockNumber),
            updatedAtTimestamp: Number(x.updatedAtTimestamp),
            updatedAtBlockNumber: Number(x.updatedAtBlockNumber),
            totalAmountInstantlyDistributedUntilUpdatedAt:
                x.totalAmountInstantlyDistributedUntilUpdatedAt,
            totalAmountFlowedDistributedUntilUpdatedAt:
                x.totalAmountFlowedDistributedUntilUpdatedAt,
            totalAmountDistributedUntilUpdatedAt:
                x.totalAmountDistributedUntilUpdatedAt,
            totalFlowAdjustmentAmountDistributedUntilUpdatedAt:
                x.totalFlowAdjustmentAmountDistributedUntilUpdatedAt,
            perUnitFlowRate: x.perUnitFlowRate,
            perUnitSettledValue: x.perUnitSettledValue,
            admin: x.admin.id,
            token: x.token.id,
        }));

    requestDocument = PoolsDocument;
}
