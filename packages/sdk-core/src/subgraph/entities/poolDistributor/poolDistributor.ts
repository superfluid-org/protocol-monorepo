import {
    Address,
    BigNumber,
    BlockNumber,
    SubgraphId,
    Timestamp,
} from "../../mappedSubgraphTypes";
import {
    PoolDistributor_Filter,
    PoolDistributor_OrderBy,
} from "../../schema.generated";
import {
    RelevantAddressesIntermediate,
    SubgraphListQuery,
    SubgraphQueryHandler,
} from "../../subgraphQueryHandler";

import {
    PoolDistributorsDocument,
    PoolDistributorsQuery,
    PoolDistributorsQueryVariables,
} from "./poolDistributors.generated";

export interface PoolDistributor {
    id: SubgraphId;
    createdAtTimestamp: Timestamp;
    createdAtBlockNumber: BlockNumber;
    updatedAtTimestamp: Timestamp;
    updatedAtBlockNumber: BlockNumber;
    totalBuffer: BigNumber;
    totalAmountInstantlyDistributedUntilUpdatedAt: BigNumber;
    totalAmountFlowedDistributedUntilUpdatedAt: BigNumber;
    totalAmountDistributedUntilUpdatedAt: BigNumber;
    flowRate: BigNumber;
    account: Address;
    pool: Address;
    token: Address;
}

export type PoolDistributorsListQuery = SubgraphListQuery<
    PoolDistributor_Filter,
    PoolDistributor_OrderBy
>;

export class PoolDistributorQueryHandler extends SubgraphQueryHandler<
    PoolDistributor,
    PoolDistributorsListQuery,
    PoolDistributorsQuery,
    PoolDistributorsQueryVariables
> {
    getAddressFieldKeysFromFilter = (): {
        accountKeys: (keyof PoolDistributor_Filter)[];
        tokenKeys: (keyof PoolDistributor_Filter)[];
    } => ({
        accountKeys: ["account", "pool"],
        tokenKeys: [],
    });

    getRelevantAddressesFromResultCore = (
        result: PoolDistributor
    ): RelevantAddressesIntermediate => ({
        tokens: [result.token],
        accounts: [result.account, result.pool],
    });

    mapFromSubgraphResponse = (
        response: PoolDistributorsQuery
    ): PoolDistributor[] =>
        response.poolDistributors.map((x) => ({
            ...x,
            createdAtTimestamp: Number(x.createdAtTimestamp),
            createdAtBlockNumber: Number(x.createdAtBlockNumber),
            updatedAtTimestamp: Number(x.updatedAtTimestamp),
            updatedAtBlockNumber: Number(x.updatedAtBlockNumber),
            pool: x.pool.id,
            token: x.pool.token.id,
            account: x.account.id,
        }));

    requestDocument = PoolDistributorsDocument;
}
