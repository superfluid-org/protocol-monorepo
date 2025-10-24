#!/bin/bash

set -e

# read the network name from the command line
NETWORK=$1

# name of the foundry wallet account to be used
WALLET_NAME=${WALLET_NAME:-sf-ops}

if ! cat ../metadata/networks.json | jq ".[].name" | grep -q "$NETWORK"; then
    echo "Network $NETWORK not found in networks.json"
    exit 1
fi

# Function to get provider URL by template
get_provider_url_by_template() {
    local network_name=$1
    
    if [ ! -z "$PROVIDER_URL_OVERRIDE" ]; then
        echo "$PROVIDER_URL_OVERRIDE"
        return
    fi
    
    if [ ! -z "$PROVIDER_URL_TEMPLATE" ]; then
        if [[ "$PROVIDER_URL_TEMPLATE" != *"{{NETWORK}}"* ]]; then
            echo "Error: env var PROVIDER_URL_TEMPLATE has invalid value" >&2
            exit 1
        fi
        echo "$PROVIDER_URL_TEMPLATE" | sed "s/{{NETWORK}}/$network_name/"
        return
    fi
    
    echo "No provider URL found for network $network_name" >&2
    return 1
}

# Get provider URL
PROVIDER_URL=$(get_provider_url_by_template "$NETWORK")
echo "Using RPC: $PROVIDER_URL"

echo "Using WALLET: $WALLET_NAME"

# get the host address from networks.json
HOST_ADDRESS=$(cat ../metadata/networks.json | jq -r ".[] | select(.name == \"$NETWORK\") | .contractsV1.host")
# make sure it's a valid address
if [[ ! "$HOST_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "HOST_ADDRESS is not a valid Ethereum address"
    exit 1
fi

echo "Using HOST_ADDRESS: $HOST_ADDRESS"

# get the resolver address from networks.json
RESOLVER_ADDRESS=$(cat ../metadata/networks.json | jq -r ".[] | select(.name == \"$NETWORK\") | .contractsV1.resolver")
# make sure it's a valid address
if [[ ! "$RESOLVER_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "RESOLVER_ADDRESS is not a valid Ethereum address"
    exit 1
fi

echo "Using RESOLVER_ADDRESS: $RESOLVER_ADDRESS"

# Set VERSION_STRING if not already set
if [ -z "$VERSION_STRING" ]; then
    GIT_REVISION=$(git rev-parse HEAD | cut -c1-16)
    PACKAGE_VERSION=$(cat ../ethereum-contracts/package.json | jq -r '.version')
    VERSION_STRING="${PACKAGE_VERSION}-${GIT_REVISION}"
fi

echo "Using VERSION_STRING: $VERSION_STRING"

# Run the Forge script
export HOST_ADDRESS
export RESOLVER_ADDRESS
export VERSION_STRING

# Build forge command with conditional flags
FORGE_CMD="forge script scripts/UpgradeFramework.s.sol:UpgradeFramework"
if [ -z "$DRY_RUN" ]; then
    FORGE_CMD="$FORGE_CMD --broadcast --verify"
    if [ ! -z "$ETHERSCAN_API_KEY" ]; then
        echo "ETHERSCAN_API_KEY is set"
        FORGE_CMD="$FORGE_CMD --etherscan-api-key \"$ETHERSCAN_API_KEY\""
    else
        echo "ETHERSCAN_API_KEY is not set"
    fi
fi
FORGE_CMD="$FORGE_CMD --rpc-url \"$PROVIDER_URL\" --account \"$WALLET_NAME\""

eval $FORGE_CMD || { echo "Forge script failed"; exit 1; }
