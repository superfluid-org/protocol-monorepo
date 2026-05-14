#!/usr/bin/env bash
#
# Run withdrawSurplusFromYieldBackend for several SuperTokens on one network, then propose
# ONE batched Safe transaction. All payloads must resolve to the same SuperToken admin Safe.
#
# Usage:
#   batch-withdraw-yield-surplus.sh <network> <superToken> [<superToken> ...]
#
# Env (optional):
#   SUPER_TOKEN_ADMIN_OVERRIDE — applied to every token (same as super-token-admin-action.sh)
#   SIMULATE=1 — forge simulate only + print batched calldata summary; no Safe proposal
#   SAFE_PROPOSER_PK, SAFE_API_KEY, SAFE_TX_SERVICE_URL, SAFE_ORIGIN — see safe-ops.ts
#
# Implementation: runs super-token-admin-action.sh once per token with SKIP_SAFE_TX_PROPOSAL=1,
# appends payload JSON lines to one temp file, then invokes safe-ops.ts in batch mode with a
# single-Safe requirement.
#
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
NETWORK="${1:?Usage: $0 <network> <superToken> [<superToken> ...]}"
shift

if [[ $# -lt 1 ]]; then
    echo "Error: provide at least one superToken address" >&2
    exit 1
fi

if ! jq -e --arg n "$NETWORK" 'any(.[]; .name == $n)' "$METADATA_JSON" >/dev/null 2>&1; then
    echo "Network $NETWORK not found in networks.json" >&2
    exit 1
fi

PROVIDER_URL=$(get_rpc_url "$NETWORK") || exit 1
echo "Using RPC: $PROVIDER_URL"
echo "Batch withdraw surplus for $# SuperToken(s) on $NETWORK"
if [[ -n "${SUPER_TOKEN_ADMIN_OVERRIDE:-}" ]]; then
    echo "Using SUPER_TOKEN_ADMIN_OVERRIDE: $SUPER_TOKEN_ADMIN_OVERRIDE"
fi

SAFE_PAYLOADS_DIR="$PKG_ROOT/.tmp/safe-payloads"
mkdir -p "$SAFE_PAYLOADS_DIR"
SAFE_PAYLOADS_FILE=$(mktemp "$SAFE_PAYLOADS_DIR/payloads.XXXXXX.jsonl")
trap 'rm -f "$SAFE_PAYLOADS_FILE"' EXIT
export SAFE_PAYLOADS_FILE

export SKIP_SAFE_TX_PROPOSAL=1

for token in "$@"; do
    if [[ ! "$token" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Error: invalid SuperToken address: $token" >&2
        exit 1
    fi
    echo ""
    echo "--- Encoding: $token ---"
    if ! "$SCRIPT_DIR/super-token-admin-action.sh" "$NETWORK" withdrawSurplusFromYieldBackend "$token"; then
        echo "Forge script failed for token $token" >&2
        exit 1
    fi
done

unset SKIP_SAFE_TX_PROPOSAL

safe_ops_args=(
    propose-file
    --rpc-url "$PROVIDER_URL"
    --payload-file "$SAFE_PAYLOADS_FILE"
    --mode batch
    --require-single-safe
)
if [[ -n "${SIMULATE:-}" ]]; then
    safe_ops_args+=(--dry-run)
fi
safe_ops_args+=(--origin "${SAFE_ORIGIN:-batchWithdrawYieldSurplus}")

npx ts-node "$SCRIPT_DIR/safe-ops.ts" "${safe_ops_args[@]}"
