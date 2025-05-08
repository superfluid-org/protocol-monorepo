import {
    Address,
    BigNumber,
    BlockNumber,
    SubgraphId,
    Timestamp,
} from "../../mappedSubgraphTypes";
import { PoolMember_Filter, PoolMember_OrderBy } from "../../schema.generated";
import {
    RelevantAddressesIntermediate,
    SubgraphListQuery,
    SubgraphQueryHandler,
} from "../../subgraphQueryHandler";

import {
    PoolMembersDocument,
    PoolMembersQuery,
    PoolMembersQueryVariables,
} from "./poolMembers.generated";

export interface PoolMember {
    id: SubgraphId;
    createdAtBlockNumber: BlockNumber;
    createdAtTimestamp: Timestamp;
    updatedAtTimestamp: Timestamp;
    updatedAtBlockNumber: BlockNumber;
    units: BigNumber;
    account: Address;
    isConnected: boolean;
    totalAmountClaimed: BigNumber;
    token: Address;
    totalAmountReceivedUntilUpdatedAt: BigNumber;
    poolTotalAmountDistributedUntilUpdatedAt: BigNumber;
    pool: Address;
    syncedPerUnitFlowRate: BigNumber;
    syncedPerUnitSettledValue: BigNumber;
}

export type PoolMembersListQuery = SubgraphListQuery<
    PoolMember_Filter,
    PoolMember_OrderBy
>;

export class PoolMemberQueryHandler extends SubgraphQueryHandler<
    PoolMember,
    PoolMembersListQuery,
    PoolMembersQuery,
    PoolMembersQueryVariables
> {
    getAddressFieldKeysFromFilter = (): {
        accountKeys: (keyof PoolMember_Filter)[];
        tokenKeys: (keyof PoolMember_Filter)[];
    } => ({
        accountKeys: ["account", "pool"],
        tokenKeys: [],
    });

    getRelevantAddressesFromResultCore = (
        result: PoolMember
    ): RelevantAddressesIntermediate => ({
        tokens: [result.token],
        accounts: [result.account, result.pool],
    });

    mapFromSubgraphResponse = (response: PoolMembersQuery): PoolMember[] =>
        response.poolMembers.map((x) => ({
            ...x,
            account: x.account.id,
            createdAtTimestamp: Number(x.createdAtTimestamp),
            createdAtBlockNumber: Number(x.createdAtBlockNumber),
            updatedAtTimestamp: Number(x.updatedAtTimestamp),
            updatedAtBlockNumber: Number(x.updatedAtBlockNumber),
            pool: x.pool.id,
            token: x.pool.token.id,
            syncedPerUnitFlowRate: x.syncedPerUnitFlowRate,
            syncedPerUnitSettledValue: x.syncedPerUnitSettledValue,
        }));

    requestDocument = PoolMembersDocument;
}
