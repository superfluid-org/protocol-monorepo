#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# read the network name and action type from the command line
NETWORK=$1
ACTION_TYPE=$2

# name of the foundry wallet account to be used
WALLET_NAME=${WALLET_NAME:-sf-ops}

# Validate arguments
if [ -z "$NETWORK" ]; then
    echo "Error: Network name is required"
    echo "Usage: $0 <NETWORK> <ACTION_TYPE> [ACTION_ARGS...]"
    echo ""
    echo "Supported action types:"
    echo "  setTokenMinimumDeposit <TOKEN_ADDRESS> <MINIMUM_DEPOSIT>"
    echo "  set3PsConfig <TOKEN_ADDRESS> <LIQUIDATION_PERIOD> <PATRICIAN_PERIOD>"
    echo "  clear3PsConfig <TOKEN_ADDRESS>"
    echo "  setRewardAddress <TOKEN_ADDRESS> <REWARD_ADDRESS>"
    echo "  clearRewardAddress <TOKEN_ADDRESS>"
    echo "  enableTrustedForwarder <TOKEN_ADDRESS> <FORWARDER_ADDRESS>"
    echo "  disableTrustedForwarder <TOKEN_ADDRESS> <FORWARDER_ADDRESS>"
    echo "  changeSuperTokenAdmin <TOKEN_ADDRESS> <NEW_ADMIN>"
    echo "  batchChangeSuperTokenAdmin <TOKEN_ADDRESSES_JSON> <NEW_ADMINS_JSON>"
    echo "  registerAgreementClass <AGREEMENT_CLASS>"
    echo "  replaceGovernance <NEW_GOVERNANCE>"
    exit 1
fi

if [ -z "$ACTION_TYPE" ]; then
    echo "Error: Action type is required"
    echo "Usage: $0 <NETWORK> <ACTION_TYPE> [ACTION_ARGS...]"
    exit 1
fi

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
echo "Using ACTION_TYPE: $ACTION_TYPE"

# Parse action-specific arguments based on action type
case "$ACTION_TYPE" in
    setTokenMinimumDeposit)
        if [ $# -lt 4 ]; then
            echo "Error: setTokenMinimumDeposit requires TOKEN_ADDRESS and MINIMUM_DEPOSIT"
            exit 1
        fi
        TOKEN_ADDRESS=$3
        MINIMUM_DEPOSIT=$4
        if [[ ! "$TOKEN_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: TOKEN_ADDRESS is not a valid Ethereum address"
            exit 1
        fi
        export TOKEN_ADDRESS
        export MINIMUM_DEPOSIT
        echo "Using TOKEN_ADDRESS: $TOKEN_ADDRESS"
        echo "Using MINIMUM_DEPOSIT: $MINIMUM_DEPOSIT"
        ;;
    set3PsConfig)
        if [ $# -lt 5 ]; then
            echo "Error: set3PsConfig requires TOKEN_ADDRESS, LIQUIDATION_PERIOD, and PATRICIAN_PERIOD"
            exit 1
        fi
        TOKEN_ADDRESS=$3
        LIQUIDATION_PERIOD=$4
        PATRICIAN_PERIOD=$5
        if [[ ! "$TOKEN_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: TOKEN_ADDRESS is not a valid Ethereum address"
            exit 1
        fi
        export TOKEN_ADDRESS
        export LIQUIDATION_PERIOD
        export PATRICIAN_PERIOD
        echo "Using TOKEN_ADDRESS: $TOKEN_ADDRESS"
        echo "Using LIQUIDATION_PERIOD: $LIQUIDATION_PERIOD"
        echo "Using PATRICIAN_PERIOD: $PATRICIAN_PERIOD"
        ;;
    clear3PsConfig|clearRewardAddress)
        if [ $# -lt 3 ]; then
            echo "Error: $ACTION_TYPE requires TOKEN_ADDRESS"
            exit 1
        fi
        TOKEN_ADDRESS=$3
        if [[ ! "$TOKEN_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: TOKEN_ADDRESS is not a valid Ethereum address"
            exit 1
        fi
        export TOKEN_ADDRESS
        echo "Using TOKEN_ADDRESS: $TOKEN_ADDRESS"
        ;;
    setRewardAddress|enableTrustedForwarder|disableTrustedForwarder)
        if [ $# -lt 4 ]; then
            echo "Error: $ACTION_TYPE requires TOKEN_ADDRESS and ADDRESS"
            exit 1
        fi
        TOKEN_ADDRESS=$3
        ADDRESS=$4
        if [[ ! "$TOKEN_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: TOKEN_ADDRESS is not a valid Ethereum address"
            exit 1
        fi
        if [[ ! "$ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: ADDRESS is not a valid Ethereum address"
            exit 1
        fi
        export TOKEN_ADDRESS
        if [ "$ACTION_TYPE" = "setRewardAddress" ]; then
            export REWARD_ADDRESS=$ADDRESS
            echo "Using TOKEN_ADDRESS: $TOKEN_ADDRESS"
            echo "Using REWARD_ADDRESS: $ADDRESS"
        else
            export FORWARDER_ADDRESS=$ADDRESS
            echo "Using TOKEN_ADDRESS: $TOKEN_ADDRESS"
            echo "Using FORWARDER_ADDRESS: $ADDRESS"
        fi
        ;;
    changeSuperTokenAdmin)
        if [ $# -lt 4 ]; then
            echo "Error: changeSuperTokenAdmin requires TOKEN_ADDRESS and NEW_ADMIN"
            exit 1
        fi
        TOKEN_ADDRESS=$3
        NEW_ADMIN=$4
        if [[ ! "$TOKEN_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: TOKEN_ADDRESS is not a valid Ethereum address"
            exit 1
        fi
        if [[ ! "$NEW_ADMIN" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: NEW_ADMIN is not a valid Ethereum address"
            exit 1
        fi
        export TOKEN_ADDRESS
        export NEW_ADMIN
        echo "Using TOKEN_ADDRESS: $TOKEN_ADDRESS"
        echo "Using NEW_ADMIN: $NEW_ADMIN"
        ;;
    batchChangeSuperTokenAdmin)
        if [ $# -lt 4 ]; then
            echo "Error: batchChangeSuperTokenAdmin requires TOKEN_ADDRESSES_JSON and NEW_ADMINS_JSON"
            exit 1
        fi
        TOKEN_ADDRESSES_JSON=$3
        NEW_ADMINS_JSON=$4
        export TOKEN_ADDRESSES_JSON
        export NEW_ADMINS_JSON
        echo "Using TOKEN_ADDRESSES_JSON: $TOKEN_ADDRESSES_JSON"
        echo "Using NEW_ADMINS_JSON: $NEW_ADMINS_JSON"
        ;;
    registerAgreementClass|replaceGovernance)
        if [ $# -lt 3 ]; then
            echo "Error: $ACTION_TYPE requires ADDRESS"
            exit 1
        fi
        ADDRESS=$3
        if [[ ! "$ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: ADDRESS is not a valid Ethereum address"
            exit 1
        fi
        if [ "$ACTION_TYPE" = "registerAgreementClass" ]; then
            export AGREEMENT_CLASS=$ADDRESS
            echo "Using AGREEMENT_CLASS: $ADDRESS"
        else
            export NEW_GOVERNANCE=$ADDRESS
            echo "Using NEW_GOVERNANCE: $ADDRESS"
        fi
        ;;
    *)
        echo "Error: Unknown action type: $ACTION_TYPE"
        exit 1
        ;;
esac

# Run the Forge script
export HOST_ADDRESS
export ACTION_TYPE

# Build forge command with conditional flags
FORGE_CMD="forge script scripts/GovAction.s.sol:GovAction"
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
            # Pass through environment variables needed by propose-safe-tx.ts
            # SAFE_PROPOSER_PK should be set as an environment variable before running this script
            SAFE_ADDRESS="$safe_address" \
            SAFE_TX_PAYLOAD="$payload" \
            SAFE_ORIGIN="$origin_env" \
            RPC_URL="$PROVIDER_URL" \
            npx ts-node "$SCRIPT_DIR/propose-safe-tx.ts"
        fi
    done <<< "$SAFE_TX_LINES"
fi

rm -f "$SCRIPT_LOG"

