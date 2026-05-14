#!/usr/bin/env bash
#
# SuperToken admin actions (enableYieldBackend, disableYieldBackend, withdrawSurplusFromYieldBackend).
# When the admin is a Safe, writes transaction payload JSON to a file and optionally proposes via
# safe-ops.ts (requires SAFE_PROPOSER_PK in .env). SIMULATE=1 encodes only and prints captured payloads.
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
export SAFE_PROPOSER_PK="${SAFE_PROPOSER_PK:-}"
export SAFE_API_KEY="${SAFE_API_KEY:-}"
export SAFE_TX_SERVICE_URL="${SAFE_TX_SERVICE_URL:-}"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/lib/network-config.sh" ] && . "$SCRIPT_DIR/lib/network-config.sh"
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
    withdrawSurplusFromYieldBackend)
        if [ $# -lt 3 ]; then
            echo "Error: withdrawSurplusFromYieldBackend requires SUPER_TOKEN" >&2
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
        echo "Supported: enableYieldBackend, disableYieldBackend, withdrawSurplusFromYieldBackend" >&2
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

cleanup_payload_file=false
if [[ -z "${SAFE_PAYLOADS_FILE:-}" ]]; then
    SAFE_PAYLOADS_DIR="$PKG_ROOT/.tmp/safe-payloads"
    mkdir -p "$SAFE_PAYLOADS_DIR"
    SAFE_PAYLOADS_FILE=$(mktemp "$SAFE_PAYLOADS_DIR/payloads.XXXXXX.jsonl")
    export SAFE_PAYLOADS_FILE
    cleanup_payload_file=true
fi
if $cleanup_payload_file; then
    trap 'rm -f "$SAFE_PAYLOADS_FILE"' EXIT
fi

if ! forge "${forge_args[@]}"; then
    echo "Forge script failed"
    exit 1
fi

# When set, caller will collect payloads across several runs and invoke safe-ops.ts in batch mode later.
if [[ -z "${SKIP_SAFE_TX_PROPOSAL:-}" ]]; then
    safe_ops_args=(propose-file --rpc-url "$PROVIDER_URL" --payload-file "$SAFE_PAYLOADS_FILE" --mode single)
    if [[ -n "${SIMULATE:-}" ]]; then
        safe_ops_args+=(--dry-run)
    fi
    if [[ -n "${SAFE_ORIGIN:-}" ]]; then
        safe_ops_args+=(--origin "$SAFE_ORIGIN")
    fi

    npx ts-node "$SCRIPT_DIR/safe-ops.ts" "${safe_ops_args[@]}"
fi
