import { Address } from "@graphprotocol/graph-ts";

// This file is a template file which is used for getting the address
// based on the network we set in the set-network package.json file.
// We add a bit of complexity to the package.json, but remove much
// more as a result.
export function getHostAddress(): Address {
    return Address.fromString("{{hostAddress}}");
}

export function getResolverAddress(): Address {
    return Address.fromString("{{resolverV1Address}}");
}

export function getNativeAssetSuperTokenAddress(): Address {
    return Address.fromString("{{nativeAssetSuperTokenAddress}}");
}

export function getIsLocalIntegrationTesting(): boolean {
    return "{{testNetwork}}".length > 0;
}