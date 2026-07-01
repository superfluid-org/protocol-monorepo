import { Query } from "@superfluid-finance/sdk-core/src";
import { chainIdToResolverDataMap } from "@superfluid-finance/sdk-core/src/constants";
import { expect } from "chai";
import metadata from "@superfluid-finance/metadata";

/**
 * We only use matic network endpoints for v1 release tests
 * otherwise, we use avalanche fuji
 * @returns chainId
 */
export const getChainId = () => {
    // null coalesce, but this should NEVER return null for either
    return process.env.SUBGRAPH_RELEASE_TAG == "v1"
        ? metadata.getNetworkByShortName("matic")?.chainId ?? 0
        : metadata.getNetworkByShortName("fuji")?.chainId ?? 0;
};

const isLocalSubgraphEndpoint = (url: string) =>
    url.includes("localhost") || url.includes("127.0.0.1");

const SUBGRAPH_REORG_ERROR = "chain was reorganized while executing the query";

const withSubgraphReorgRetry = async <T>(
    fn: () => Promise<T>,
    maxAttempts = 5
): Promise<T> => {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
            return await fn();
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            if (
                !message.includes(SUBGRAPH_REORG_ERROR) ||
                attempt === maxAttempts
            ) {
                throw err;
            }
            await new Promise((resolve) => setTimeout(resolve, 200 * attempt));
        }
    }
    throw new Error("unreachable");
};

export const testQueryClassFunctions = async (query: Query) => {
    await withSubgraphReorgRetry(async () => {
        console.log("query listAllSuperTokens...");
        await query.listAllSuperTokens({}, { take: 10 });
        console.log("query listIndexes...");
        await query.listIndexes({}, { take: 10 });
        console.log("query listIndexSubscriptions...");
        await query.listIndexSubscriptions({}, { take: 10 });
        console.log("query listStreams...");
        await query.listStreams({}, { take: 10 });
        console.log("query listUserInteractedSuperTokens...");
        await query.listUserInteractedSuperTokens({}, { take: 10 });
    });
};

export const testGetAllEventsQuery = async (query: Query) => {
    // NOTE: when testing a live endpoint, we just want to make sure that
    // this version of SDK-Core will be able to handle the deployed subgraph endpoint
    // However, when we test the locally deployed endpoint, we want to test
    // as many of the mapGetAllEventsQueryEvents cases.
    await withSubgraphReorgRetry(() => query.listEvents({}, { take: 100 }));
};

export const testExpectListenerThrow = async (query: Query) => {
    try {
        query.on((e, u) => {
            console.log(e);
            u();
        }, 999);
    } catch (err: any) {
        expect(err.message).to.equal("Let's not go crazy with the queries...");
    }
};

export const testListenerInitialization = async (query: Query) => {
    query.on((e, u) => {
        console.log(e);
        u();
    }, 1000);
};

export const getSubgraphEndpoint = (chainId: number) => {
    const resolverData = chainIdToResolverDataMap.get(chainId);
    if (!resolverData) throw new Error("Resolver data is undefined");
    return resolverData.subgraphAPIEndpoint;
};

const resolveSubgraphQueriesEndpoint = () => {
    const chainIdToUse = getChainId();
    let customSubgraphQueriesEndpoint = getSubgraphEndpoint(chainIdToUse);

    if (process.env.SUBGRAPH_RELEASE_TAG) {
        customSubgraphQueriesEndpoint = customSubgraphQueriesEndpoint.replace(
            "v1",
            process.env.SUBGRAPH_RELEASE_TAG
        );
    }

    if (process.env.SUBGRAPH_ENDPOINT) {
        customSubgraphQueriesEndpoint = process.env.SUBGRAPH_ENDPOINT;
    }

    return customSubgraphQueriesEndpoint;
};

// Subgraph Tests (5_subgraph.test.ts) covers the same cases against the local graph node.
const queryTestsSuite = isLocalSubgraphEndpoint(resolveSubgraphQueriesEndpoint())
    ? describe.skip
    : describe;

queryTestsSuite("Query Tests", () => {
    let query: Query;
    before(async () => {
        const customSubgraphQueriesEndpoint = resolveSubgraphQueriesEndpoint();

        query = new Query({
            customSubgraphQueriesEndpoint,
        });
        console.log("Testing with endpoint:", customSubgraphQueriesEndpoint);
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
    });
});
