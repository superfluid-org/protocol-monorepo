#!/usr/bin/env bash
# Semantic resolver operations; authorization and overwrite checks stay in ResolverSetKey.
# Usage: resolver-token.sh NETWORK {list TOKEN [SYMBOL]|unlist SYMBOL|register NAME TOKEN|reset RELEASE CONFIRM_RELEASE}
# RELEASE_VERSION is required for list/unlist; production examples use v1.
# ALLOW_UPDATE=1 deliberately replaces an occupied entry. SIMULATE=1 never broadcasts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"
_env=$(set -o posix; export -p); [[ ! -f "$PKG_ROOT/.env" ]] || source "$PKG_ROOT/.env"; [[ ! -f "$PKG_ROOT/../.env" ]] || source "$PKG_ROOT/../.env"; eval "$_env"
source "$SCRIPT_DIR/lib/network-config.sh"
NETWORK="${1:?network required}"
ACTION="${2:?list, unlist, register or reset required}"
shift 2
ZERO=0x0000000000000000000000000000000000000000
case "$ACTION" in
    list)
        : "${RELEASE_VERSION:?Set RELEASE_VERSION explicitly (e.g. v1)}"
        [[ $# -ge 1 && $# -le 2 ]] || { echo 'list requires TOKEN [SYMBOL_OVERRIDE]' >&2; exit 1; }
        TOKEN=$1
        [[ "$TOKEN" =~ ^0x[[:xdigit:]]{40}$ && "$TOKEN" != "$ZERO" ]] || { echo 'Invalid token address' >&2; exit 1; }
        RPC=$(get_rpc_url "$NETWORK")
        SYMBOL=${2:-$(cast call "$TOKEN" 'symbol()(string)' --rpc-url "$RPC" | jq -r .)}
        [[ -n "$SYMBOL" ]] || { echo 'Empty token symbol' >&2; exit 1; }
        exec bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "supertokens.${RELEASE_VERSION}.$SYMBOL" "$TOKEN"
        ;;
    unlist)
        : "${RELEASE_VERSION:?Set RELEASE_VERSION explicitly (e.g. v1)}"
        [[ $# == 1 ]] || { echo 'unlist requires SYMBOL' >&2; exit 1; }
        ALLOW_UPDATE=1 exec bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "supertokens.${RELEASE_VERSION}.$1" "$ZERO"
        ;;
    register)
        [[ $# == 2 ]] || { echo 'register requires NAME TOKEN' >&2; exit 1; }
        exec bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "tokens.$1" "$2"
        ;;
    reset)
        [[ $# == 2 && "$1" == "$2" ]] || { echo 'reset requires RELEASE CONFIRM_RELEASE (matching explicit confirmation)' >&2; exit 1; }
        ALLOW_UPDATE=1 bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "Superfluid.$1" "$ZERO"
        ALLOW_UPDATE=1 bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "TestGovernance.$1" "$ZERO"
        ;;
    *) echo "Unknown resolver operation: $ACTION" >&2; exit 1 ;;
esac
