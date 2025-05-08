import {
    Address,
    BigNumber,
    BlockNumber,
    Timestamp,
} from "../../mappedSubgraphTypes";
import {
    FlowOperator_Filter,
    FlowOperator_OrderBy,
} from "../../schema.generated";
import {
    RelevantAddressesIntermediate,
    SubgraphListQuery,
    SubgraphQueryHandler,
} from "../../subgraphQueryHandler";

import {
    FlowOperatorsDocument,
    FlowOperatorsQuery,
    FlowOperatorsQueryVariables,
} from "./flowOperators.generated";

export interface FlowOperator {
    id: string;
    createdAtBlockNumber: BlockNumber;
    createdAtTimestamp: Timestamp;
    updatedAtBlockNumber: BlockNumber;
    updatedAtTimestamp: Timestamp;
    flowOperator: Address;
    sender: Address;
    token: Address;
    flowRateAllowanceRemaining: BigNumber;
    allowance: BigNumber;
    permissions: number;
}

export type FlowOperatorListQuery = SubgraphListQuery<
    FlowOperator_Filter,
    FlowOperator_OrderBy
>;

export class FlowOperatorQueryHandler extends SubgraphQueryHandler<
    FlowOperator,
    FlowOperatorListQuery,
    FlowOperatorsQuery,
    FlowOperatorsQueryVariables
> {
    getAddressFieldKeysFromFilter = (): {
        accountKeys: (keyof FlowOperator_Filter)[];
        tokenKeys: (keyof FlowOperator_Filter)[];
    } => ({
        accountKeys: ["sender", "flowOperator"],
        tokenKeys: ["token"],
    });

    getRelevantAddressesFromResultCore = (
        result: FlowOperator
    ): RelevantAddressesIntermediate => ({
        accounts: [result.sender, result.flowOperator],
        tokens: [result.token],
    });

    mapFromSubgraphResponse = (response: FlowOperatorsQuery): FlowOperator[] =>
        response.flowOperators.map((x) => ({
            ...x,
            sender: x.sender.id,
            token: x.token.id,
            createdAtTimestamp: Number(x.createdAtTimestamp),
            createdAtBlockNumber: Number(x.createdAtBlockNumber),
            updatedAtTimestamp: Number(x.updatedAtTimestamp),
            updatedAtBlockNumber: Number(x.updatedAtBlockNumber),
        }));
    requestDocument = FlowOperatorsDocument;
}
