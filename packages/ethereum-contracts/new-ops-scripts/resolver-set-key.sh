#!/usr/bin/env bash
#
# Set a resolver key via Foundry + DeployUtils (Safe payloads → safe-ops.ts when applicable).
#
# Usage:
#   new-ops-scripts/resolver-set-key.sh <network> <resolverKey> <address>
#
# Env: WALLET_NAME, ALLOW_UPDATE=1, SIMULATE=1, SAFE_* (see gov-action.sh)
#
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"

# shellcheck source=/dev/null
_env=$(set -o posix; export -p); [[ -f "$PKG_ROOT/.env" ]] && source "$PKG_ROOT/.env"; [[ -f "$PKG_ROOT/../.env" ]] && source "$PKG_ROOT/../.env"; eval "$_env"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/lib/network-config.sh" ] && . "$SCRIPT_DIR/lib/network-config.sh"

NETWORK="${1:?Usage: $0 <network> <resolverKey> <address>}"
RESOLVER_KEY="${2:?Usage: $0 <network> <resolverKey> <address>}"
VALUE="${3:?Usage: $0 <network> <resolverKey> <address>}"

WALLET_NAME="${WALLET_NAME:-sf-ops}"

if [[ ! "$VALUE" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "invalid address: $VALUE" >&2
    exit 1
fi

PROVIDER_URL=$(get_rpc_url "$NETWORK") || exit 1
RESOLVER_ADDRESS=${RESOLVER_ADDRESS:-$(jq -r '.[] | select(.name == "'"$NETWORK"'") | .contractsV1.resolver' "$METADATA_JSON")}
if [[ -z "$RESOLVER_ADDRESS" || "$RESOLVER_ADDRESS" == "null" ]]; then
    echo "No resolver in metadata for $NETWORK" >&2
    exit 1
fi

export RESOLVER_ADDRESS
export RESOLVER_KEY
export RESOLVER_VALUE="$VALUE"
export ALLOW_UPDATE="${ALLOW_UPDATE:-}"

cd "$PKG_ROOT"

forge_args=(script foundry-scripts/ResolverSetKey.s.sol:ResolverSetKey --rpc-url "$PROVIDER_URL")
if [[ -n "${SIMULATE:-}" ]]; then
    export SAFE_PAYLOAD_SIMULATED=true
    source "$SCRIPT_DIR/lib/simulation-sender.sh"
    if [[ -n "${RESOLVER_ADMIN:-}" ]]; then
        admin=$RESOLVER_ADMIN
    else
        role=0x0000000000000000000000000000000000000000000000000000000000000000
        count=$(cast call "$RESOLVER_ADDRESS" 'getRoleMemberCount(bytes32)(uint256)' "$role" --rpc-url "$PROVIDER_URL" --json | jq -er '.[0] | tonumber')
        [[ "$count" -eq 1 ]] || { echo 'Set RESOLVER_ADMIN explicitly when resolver does not have exactly one admin' >&2; exit 1; }
        admin=$(cast call "$RESOLVER_ADDRESS" 'getRoleMember(bytes32,uint256)(address)' "$role" 0 --rpc-url "$PROVIDER_URL")
    fi
    forge_args+=(--sender "$(get_simulation_sender "$admin" "$PROVIDER_URL")")
else
    export SAFE_PAYLOAD_SIMULATED=false
    forge_args+=(--account "$WALLET_NAME" --broadcast)
fi

SAFE_PAYLOADS_DIR="$PKG_ROOT/.tmp/safe-payloads"
mkdir -p "$SAFE_PAYLOADS_DIR"
SAFE_PAYLOADS_FILE=$(mktemp "$SAFE_PAYLOADS_DIR/payloads.XXXXXX.jsonl")
trap 'rm -f "$SAFE_PAYLOADS_FILE"' EXIT
export SAFE_PAYLOADS_FILE

if ! with_keystore_password forge "${forge_args[@]}"; then
    echo "ResolverSetKey forge script failed" >&2
    exit 1
fi

if [[ ! -s "$SAFE_PAYLOADS_FILE" ]]; then
    exit 0
fi

safe_ops_args=(propose-file --rpc-url "$PROVIDER_URL" --payload-file "$SAFE_PAYLOADS_FILE" --mode single)
if [[ -n "${SIMULATE:-}" ]]; then
    safe_ops_args+=(--dry-run)
fi
if [[ -n "${SAFE_ORIGIN:-}" ]]; then
    safe_ops_args+=(--origin "$SAFE_ORIGIN")
fi

npx ts-node "$SCRIPT_DIR/safe-ops.ts" "${safe_ops_args[@]}"
