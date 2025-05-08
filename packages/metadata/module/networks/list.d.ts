interface AutowrapAddresses {
    readonly manager: string;
    readonly wrapStrategy: string;
}
interface ContractAddresses {
    readonly resolver: string;
    readonly host: string;
    readonly governance?: string;
    readonly cfaV1: string;
    readonly cfaV1Forwarder: string;
    readonly idaV1: string;
    readonly gdaV1?: string;
    readonly gdaV1Forwarder?: string;
    readonly superTokenFactory: string;
    readonly superfluidLoader: string;
    readonly toga?: string;
    readonly vestingScheduler?: string;
    readonly vestingSchedulerV2?: string;
    readonly vestingSchedulerV3?: string;
    readonly flowScheduler?: string;
    readonly batchLiquidator?: string;
    readonly superSpreader?: string;
    readonly autowrap?: AutowrapAddresses;
    readonly existentialNFTCloneFactory: string;
    readonly macroForwarder?: string;
}
interface SubgraphData {
    readonly name: string;
    readonly cliName?: string;
    readonly hostedEndpoint?: string;
    readonly satsumaEndpoint?: string;
}
export interface NetworkMetaData {
    readonly name: string; // Superfluid canonical network name
    readonly isDeprecated: boolean;
    readonly isTestnet: boolean;
    readonly networkId: number;
    readonly chainId: number;
    readonly sfId: number; // Superfluid canonical network id
    readonly shortName: string;
    readonly uppercaseName: string;
    readonly humanReadableName: string;
    readonly nativeTokenSymbol: string;
    readonly nativeTokenWrapper: string;
    readonly contractsV1: ContractAddresses;
    readonly startBlockV1: number;
    readonly logsQueryRange: number;
    readonly explorer: string;
    readonly subgraphV1: SubgraphData;
    readonly publicRPCs?: string[];
    readonly coinGeckoId?: string;
    readonly trustedForwarders?: string[]; // list of additional trusted forwarders
    readonly subgraphVesting?: { name: string, hostedEndpoint: string }
    readonly subgraphFlowScheduler?: { name: string, hostedEndpoint: string }
    readonly subgraphAutoWrap?: { name: string, hostedEndpoint: string },
}
declare const _default: NetworkMetaData[];
export default _default;
