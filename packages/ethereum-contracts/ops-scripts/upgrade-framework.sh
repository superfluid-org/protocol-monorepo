#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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
    # Get the latest tag starting with "ethereum-contracts@"
    LATEST_TAG=$(git tag -l "ethereum-contracts@*" --sort=-version:refname | head -n1)
    if [ -z "$LATEST_TAG" ]; then
        echo "Error: No tag found starting with 'ethereum-contracts@'"
        exit 1
    fi
    
    # Extract version from tag (part after @)
    TAG_VERSION=${LATEST_TAG#ethereum-contracts@}
    # Strip leading 'v' if present
    TAG_VERSION=${TAG_VERSION#v}
    
    # Get version from package.json
    PACKAGE_VERSION=$(cat ../ethereum-contracts/package.json | jq -r '.version')
    
    # Verify versions match
    if [ "$TAG_VERSION" != "$PACKAGE_VERSION" ]; then
        echo "Error: Tag version ($TAG_VERSION) does not match package.json version ($PACKAGE_VERSION)"
        exit 1
    fi
    
    # Get commit hash from the tag
    TAGGED_COMMIT=$(git rev-list -n 1 "$LATEST_TAG")
    GIT_REVISION=$(echo "$TAGGED_COMMIT" | cut -c1-16)
    
    # Sanity check: verify the latest change in contracts/ matches the tagged commit
    LATEST_CONTRACTS_COMMIT=$(git log -1 --format=%H -- contracts/)
    if [ "$TAGGED_COMMIT" != "$LATEST_CONTRACTS_COMMIT" ]; then
        echo "Warning: Latest commit modifying contracts/ ($LATEST_CONTRACTS_COMMIT) does not match tagged commit ($TAGGED_COMMIT)"
        echo "The tag may not contain the latest contract changes."
        exit 1
    fi
    
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

SCRIPT_LOG=$(mktemp)
if ! eval $FORGE_CMD | tee "$SCRIPT_LOG"; then
    rm -f "$SCRIPT_LOG"
    echo "Forge script failed"
    exit 1
fi

SAFE_TX_LINES=$(grep "<<<SAFE_TX:v1>>>" "$SCRIPT_LOG" || true)
if [ -n "$SAFE_TX_LINES" ]; then
    echo "Captured Safe transaction payloads:"
    while IFS= read -r safe_line; do
        payload=${safe_line#*<<<SAFE_TX:v1>>>}
        safe_address=$(printf '%s' "$payload" | jq -r '.safeAddress')
        to_address=$(printf '%s' "$payload" | jq -r '.to')
        value_hex=$(printf '%s' "$payload" | jq -r '.value')
        data_hex=$(printf '%s' "$payload" | jq -r '.data')
        action_type=$(printf '%s' "$payload" | jq -r '.actionType')
        echo "  Action Type: $action_type"
        echo "    Safe: $safe_address"
        echo "    To: $to_address"
        echo "    Value: $value_hex"
        echo "    Data: $data_hex"
        if [ -z "$DRY_RUN" ]; then
            origin_env="${SAFE_ORIGIN:-$action_type}"
            echo "    Proposing Safe transaction via propose-safe-tx.ts"
            SAFE_ADDRESS="$safe_address" SAFE_TX_PAYLOAD="$payload" SAFE_ORIGIN="$origin_env" npx ts-node "$SCRIPT_DIR/propose-safe-tx.ts"
        fi
    done <<< "$SAFE_TX_LINES"
fi

rm -f "$SCRIPT_LOG"
