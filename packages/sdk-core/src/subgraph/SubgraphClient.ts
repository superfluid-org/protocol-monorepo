import { TypedDocumentNode } from "@graphql-typed-document-node/core";
import { DocumentNode } from "graphql";
import { request, RequestExtendedOptions, Variables } from "graphql-request";

type RequestDocument = string | DocumentNode;

export declare type BatchRequestDocument<V = Variables> = {
    document: RequestDocument;
    variables?: V;
};

export class SubgraphClient {
    constructor(readonly subgraphUrl: string) {}

    async request<T, V extends Variables = Variables>(
        document: RequestDocument | TypedDocumentNode<T, V>,
        variables?: V
    ): Promise<T> {
        return await request<T, V>({
            url: this.subgraphUrl,
            document,
            variables: variables ? cleanVariables<V>(variables) : undefined,
            // TODO: explicit casting is semi-dirty and not recommended
            // but I am not sure how to fix this right now
        } as unknown as RequestExtendedOptions<V, T>);
    }
}

// Inspired by: https://stackoverflow.com/a/38340730
// Remove properties with null, undefined, empty string values.
function cleanVariables<V extends Variables = Variables>(variables: V): V {
    return Object.fromEntries(
        Object.entries(variables)
            .filter(
                ([, value]) =>
                    value !== "" && value !== null && value !== undefined
            )
            .map(([key, value]) => [
                key,
                value === Object(value) && !Array.isArray(value)
                    ? cleanVariables(value as Variables)
                    : value,
            ])
    ) as V;
}
