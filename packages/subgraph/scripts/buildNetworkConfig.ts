import fs from "fs";
import { join } from 'path';
import metadata from "@superfluid-finance/metadata";

interface SubgraphConfig {
    readonly network: string;
    readonly hostStartBlock: number;
    readonly hostAddress: string;
    readonly cfaAddress: string;
    readonly idaAddress: string;
    readonly gdaAddress: string;
    readonly superTokenFactoryAddress: string;
    readonly resolverV1Address: string;
    readonly nativeAssetSuperTokenAddress: string;
    readonly indexerHints_prune: string;
}

const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

const vendorCliNameExceptions: Record<string, Record<string, string>> = {
    "goldsky": {
        "xdai-mainnet": "xdai",
        "avalanche-fuji": "avalanche-testnet"
    }
}

const vendorHistoryPruning: Record<string, string> = {
    "goldsky": "auto"
};

// script usage: npx ts-node ./scripts/buildNetworkConfig.ts <NETWORK_NAME> <VENDOR_NAME?>
function main() {
    const networkName = process.argv[2];
    const vendorName = process.argv[3];

    const networkMetadata = metadata.getNetworkByName(networkName);

    if (!networkMetadata) {
        throw new Error("No metadata found");
    }

    const subgraphConfig: SubgraphConfig = {
        network: vendorCliNameExceptions[vendorName]?.[networkMetadata.name] || networkMetadata.subgraphV1.cliName || networkMetadata.shortName,
        hostStartBlock: networkMetadata.startBlockV1,
        hostAddress: networkMetadata.contractsV1.host,
        cfaAddress: networkMetadata.contractsV1.cfaV1,
        idaAddress: networkMetadata.contractsV1.idaV1,
        gdaAddress: networkMetadata.contractsV1.gdaV1 || ADDRESS_ZERO,
        superTokenFactoryAddress: networkMetadata.contractsV1.superTokenFactory,
        resolverV1Address: networkMetadata.contractsV1.resolver,
        nativeAssetSuperTokenAddress: networkMetadata.nativeTokenWrapper,
        indexerHints_prune: vendorHistoryPruning[vendorName] || "never",
    };

    const writeToDir = join(__dirname, '..', `config/${networkName}.json`);

    fs.writeFile(writeToDir, JSON.stringify(subgraphConfig), (err) => {
        if (err) {
            console.log(err);
            process.exit(1);
        } else {
            process.exit(0);
        }
    });
}

main();
