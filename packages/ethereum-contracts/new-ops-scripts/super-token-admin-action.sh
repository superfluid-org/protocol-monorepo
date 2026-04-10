#!/usr/bin/env bash
#
# SuperToken admin actions (enableYieldBackend, disableYieldBackend). When the admin is a Safe,
# outputs transaction payload and optionally proposes via propose-safe-tx.ts (requires SAFE_PROPOSER_PK in .env).
# SIMULATE=1 to skip broadcast and Safe proposal (encode only).
#
# Env: SUPER_TOKEN_ADMIN_OVERRIDE — optional; use when on-chain admin not yet set (e.g. pending gov action).
#      Must be a valid Ethereum address. Wrappers enable-yield-backend.sh / disable-yield-backend.sh accept
#      it as optional trailing arg.
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
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/lib/network-config.sh" ] && . "$SCRIPT_DIR/lib/network-config.sh"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/lib/safe-tx.sh" ] && . "$SCRIPT_DIR/lib/safe-tx.sh"

NETWORK="${1:?Usage: $0 <network> <ACTION_TYPE> [args...] [SUPER_TOKEN_ADMIN_OVERRIDE]}"
ACTION_TYPE="${2:?Usage: $0 <network> <ACTION_TYPE> [args...] [SUPER_TOKEN_ADMIN_OVERRIDE]}"

if ! jq -e --arg n "$NETWORK" 'any(.[]; .name == $n)' "$METADATA_JSON" >/dev/null 2>&1; then
    echo "Network $NETWORK not found in networks.json" >&2
    exit 1
fi

PROVIDER_URL=$(get_rpc_url "$NETWORK") || exit 1
echo "Using RPC: $PROVIDER_URL"
echo "Using WALLET: ${WALLET_NAME:-sf-ops}"
echo "Using ACTION_TYPE: $ACTION_TYPE"

case "$ACTION_TYPE" in
    enableYieldBackend)
        if [ $# -lt 4 ]; then
            echo "Error: enableYieldBackend requires SUPER_TOKEN and YIELD_BACKEND" >&2
            exit 1
        fi
        SUPER_TOKEN=$3
        YIELD_BACKEND=$4
        if [[ ! "$SUPER_TOKEN" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: SUPER_TOKEN is not a valid Ethereum address" >&2
            exit 1
        fi
        if [[ ! "$YIELD_BACKEND" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: YIELD_BACKEND is not a valid Ethereum address" >&2
            exit 1
        fi
        export SUPER_TOKEN_ADDRESS="$SUPER_TOKEN"
        export YIELD_BACKEND_ADDRESS="$YIELD_BACKEND"
        echo "Using SUPER_TOKEN: $SUPER_TOKEN"
        echo "Using YIELD_BACKEND: $YIELD_BACKEND"
        ;;
    disableYieldBackend)
        if [ $# -lt 3 ]; then
            echo "Error: disableYieldBackend requires SUPER_TOKEN" >&2
            exit 1
        fi
        SUPER_TOKEN=$3
        if [[ ! "$SUPER_TOKEN" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: SUPER_TOKEN is not a valid Ethereum address" >&2
            exit 1
        fi
        export SUPER_TOKEN_ADDRESS="$SUPER_TOKEN"
        echo "Using SUPER_TOKEN: $SUPER_TOKEN"
        ;;
    *)
        echo "Error: Unknown action type: $ACTION_TYPE" >&2
        echo "Supported: enableYieldBackend, disableYieldBackend" >&2
        exit 1
        ;;
esac

export ACTION_TYPE
# Optional: use when on-chain admin is not yet set (e.g. pending gov action)
if [[ -n "${SUPER_TOKEN_ADMIN_OVERRIDE:-}" ]]; then
    if [[ ! "$SUPER_TOKEN_ADMIN_OVERRIDE" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Error: SUPER_TOKEN_ADMIN_OVERRIDE is not a valid Ethereum address: $SUPER_TOKEN_ADMIN_OVERRIDE" >&2
        exit 1
    fi
    export SUPER_TOKEN_ADMIN_OVERRIDE
    echo "Using SUPER_TOKEN_ADMIN_OVERRIDE: $SUPER_TOKEN_ADMIN_OVERRIDE"
fi
cd "$PKG_ROOT"

forge_args=(script foundry-scripts/SuperTokenAdminAction.s.sol:SuperTokenAdminAction --sig run --rpc-url "$PROVIDER_URL")
if [[ -n "${SIMULATE:-}" ]]; then
    forge_args+=(--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
else
    forge_args+=(--account "${WALLET_NAME:-sf-ops}" --broadcast)
fi

SCRIPT_LOG=$(mktemp)
trap 'rm -f "$SCRIPT_LOG"' EXIT

if ! forge "${forge_args[@]}" | tee "$SCRIPT_LOG"; then
    echo "Forge script failed"
    exit 1
fi

handle_safe_tx_payloads "$SCRIPT_LOG" "$SCRIPT_DIR" "$PROVIDER_URL"
