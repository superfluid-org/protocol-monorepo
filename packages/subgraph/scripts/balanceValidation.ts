import { ethers } from "ethers";
import { getAccountTokenSnapshots } from "./dataIntegrity/dataIntegrityQueries";
import {
    getMostRecentIndexedBlockNumber,
    QueryHelper,
} from "./dataIntegrity/helperFunctions";
import { DataIntegrityAccountTokenSnapshot } from "./dataIntegrity/interfaces";

/**
 * This function "validates" that balance data is correct - this is to be used
 * when removing the RPC calls on the subgraph piecemeal.
 * The assumption of this test is that the v1 balance is correct as it initially starts from
 * a place of only using RPC calls.
 */
async function main() {
    const endpointA =
        "https://api.thegraph.com/subgraphs/name/superfluid-finance/protocol-feature-matic";
    const endpointB =
        "https://api.thegraph.com/subgraphs/name/superfluid-finance/protocol-v1-matic";
    const endpointARecentBlock = await getMostRecentIndexedBlockNumber(
        endpointA
    );
    const endpointAQueryHelper = new QueryHelper(
        endpointA,
        endpointARecentBlock,
        1000
    );

    const endpointBRecentBlock = await getMostRecentIndexedBlockNumber(
        endpointB
    );
    const endpointBQueryHelper = new QueryHelper(
        endpointB,
        endpointBRecentBlock,
        1000
    );

    console.log("Retrieving Feature Endpoint data");
    const endpointAData =
        await endpointAQueryHelper.getAllResults<DataIntegrityAccountTokenSnapshot>(
            {
                query: getAccountTokenSnapshots,
                isUpdatedAt: true,
            }
        );

    console.log("Retrieving V1 Endpoint data");
    const endpointBData =
        await endpointBQueryHelper.getAllResults<DataIntegrityAccountTokenSnapshot>(
            {
                query: getAccountTokenSnapshots,
                isUpdatedAt: true,
            }
        );
    console.log("Validating Data");

    if (endpointAData.length !== endpointBData.length) {
        throw new Error("Different length results");
    }

    let errors = 0;
    for (let i = 0; i < endpointAData.length; i++) {
        if (
            endpointAData[i].balanceUntilUpdatedAt !==
            endpointBData[i].balanceUntilUpdatedAt
        ) {
            console.log("FEATURE:", JSON.stringify(endpointAData[i]));
            console.log("V1:", JSON.stringify(endpointBData[i]));
            errors++;
        }
    }

    if (errors === 0) console.log("Success");
}

main().then(() => {
    process.exit(0);
});
