import { chainIdToResolverDataMap, NetworkData, Query } from "../src";
import {
    getChainId,
    getSubgraphEndpoint,
    testExpectListenerThrow,
    testGetAllEventsQuery,
    testListenerInitialization,
    testQueryClassFunctions,
} from "../previous-versions-testing/queryTests";

describe("Subgraph Tests", () => {
    let query: Query;

    const chainIdToUse = getChainId();

    // we will either test a singular subgraph_endpoint
    // or we test all of the subgraph endpoints
    const customSubgraphQueriesEndpoint =
        process.env.SUBGRAPH_ENDPOINT || getSubgraphEndpoint(chainIdToUse);

    before(() => {
        query = new Query({
            customSubgraphQueriesEndpoint,
        });
    });

    describe("Query Class Tests", () => {
        it("Should be able to execute all of the query class", async () => {
            await testQueryClassFunctions(query);
        });

        it("Should be able to make the getAllEvents query", async () => {
            await testGetAllEventsQuery(query);
        });

        it("Should throw if listener ms < 1000", async () => {
            await testExpectListenerThrow(query);
        });

        it("Should be able to use the listener", async () => {
            await testListenerInitialization(query);
        });

        it("Should have same schema entity as deployed subgraph endpoints", async () => {
            const resolverDataArray = Array.from(
                chainIdToResolverDataMap.values()
            ) as NetworkData[];
            if (process.env.SUBGRAPH_ENDPOINT === "") {
                await Promise.all(
                    resolverDataArray.map(async (x) => {
                        // @note skip networks without subgraph endpoints
                        if (x.subgraphAPIEndpoint !== "") {
                            const query = new Query({
                                customSubgraphQueriesEndpoint:
                                    x.subgraphAPIEndpoint,
                            });
                            await testGetAllEventsQuery(query);
                        }
                    })
                );
            } else {
                await testGetAllEventsQuery(query);
            }
        });
    });
});
