#!/bin/bash
#
# Governance actions via Foundry. When the governance admin is a Safe, writes Safe payload JSON
# to a temp file and optionally proposes it via safe-ops.ts (requires SAFE_PROPOSER_PK in .env).
# Optional: SAFE_API_KEY for higher rate limits, SAFE_TX_SERVICE_URL for custom service, SAFE_ORIGIN
# for proposal label. SIMULATE=1 encodes only and prints captured Safe payloads.
#
set -e
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"

# shellcheck source=/dev/null
[ -f "$PKG_ROOT/.env" ] && . "$PKG_ROOT/.env"
# shellcheck source=/dev/null
[ -f "$PKG_ROOT/../.env" ] && . "$PKG_ROOT/../.env"
export SAFE_PROPOSER_PK="${SAFE_PROPOSER_PK:-}"
export SAFE_API_KEY="${SAFE_API_KEY:-}"
export SAFE_TX_SERVICE_URL="${SAFE_TX_SERVICE_URL:-}"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/lib/network-config.sh" ] && . "$SCRIPT_DIR/lib/network-config.sh"
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

if ! jq -e --arg n "$NETWORK" 'any(.[]; .name == $n)' "$METADATA_JSON" >/dev/null 2>&1; then
    echo "Network $NETWORK not found in networks.json" >&2
    exit 1
fi

PROVIDER_URL=$(get_rpc_url "$NETWORK") || exit 1
echo "Using RPC: $PROVIDER_URL"

echo "Using WALLET: $WALLET_NAME"

HOST_ADDRESS=$(get_host "$NETWORK")
if [[ -z "$HOST_ADDRESS" || "$HOST_ADDRESS" == "null" || ! "$HOST_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "HOST_ADDRESS is not a valid Ethereum address" >&2
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

cd "$PKG_ROOT"

# Build forge command with conditional flags
forge_args=(script foundry-scripts/GovAction.s.sol:GovAction --rpc-url "$PROVIDER_URL")
if [[ -n "${SIMULATE:-}" ]]; then
    forge_args+=(--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
else
    forge_args+=(--account "$WALLET_NAME" --broadcast --verify)
    if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
        echo "ETHERSCAN_API_KEY is set"
        forge_args+=(--etherscan-api-key "$ETHERSCAN_API_KEY")
    else
        echo "ETHERSCAN_API_KEY is not set"
    fi
fi

SAFE_PAYLOADS_DIR="$PKG_ROOT/.tmp/safe-payloads"
mkdir -p "$SAFE_PAYLOADS_DIR"
SAFE_PAYLOADS_FILE=$(mktemp "$SAFE_PAYLOADS_DIR/payloads.XXXXXX.jsonl")
trap 'rm -f "$SAFE_PAYLOADS_FILE"' EXIT
export SAFE_PAYLOADS_FILE

if ! with_keystore_password forge "${forge_args[@]}"; then
    echo "Forge script failed"
    exit 1
fi

safe_ops_args=(propose-file --rpc-url "$PROVIDER_URL" --payload-file "$SAFE_PAYLOADS_FILE" --mode single)
if [[ -n "${SIMULATE:-}" ]]; then
    safe_ops_args+=(--dry-run)
fi
if [[ -n "${SAFE_ORIGIN:-}" ]]; then
    safe_ops_args+=(--origin "$SAFE_ORIGIN")
fi

npx ts-node "$SCRIPT_DIR/safe-ops.ts" "${safe_ops_args[@]}"
