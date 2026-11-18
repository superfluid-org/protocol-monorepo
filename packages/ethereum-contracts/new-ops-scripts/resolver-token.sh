#!/usr/bin/env bash
# Semantic resolver operations; authorization and overwrite checks stay in ResolverSetKey.
# Usage: resolver-token.sh NETWORK {list TOKEN [SYMBOL]|unlist SYMBOL|register NAME TOKEN|reset RELEASE CONFIRM_RELEASE}
# RELEASE_VERSION is required for list/unlist; production examples use v1.
# ALLOW_UPDATE=1 deliberately replaces an occupied entry; --broadcast enables side effects.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
FLAGS=()
(( ! BROADCAST )) || FLAGS+=(--broadcast)
(( ! RESUME )) || FLAGS+=(--resume)
set -- "${OPS_ARGS[@]}"
NETWORK="${1:?network required}"
ACTION="${2:?list, unlist, register or reset required}"
shift 2
ZERO=0x0000000000000000000000000000000000000000
case "$ACTION" in
    list)
        : "${RELEASE_VERSION:?Set RELEASE_VERSION explicitly (e.g. v1)}"
        [[ $# -ge 1 && $# -le 2 ]] || { echo 'list requires TOKEN [SYMBOL_OVERRIDE]' >&2; exit 1; }
        TOKEN=$1
        require_address TOKEN "$TOKEN"
        [[ "$TOKEN" != "$ZERO" ]] || { echo 'Invalid zero token address' >&2; exit 1; }
        RPC=$(get_rpc_url "$NETWORK")
        SYMBOL=${2:-$(cast call "$TOKEN" 'symbol()(string)' --rpc-url "$RPC" | jq -r .)}
        [[ -n "$SYMBOL" ]] || { echo 'Empty token symbol' >&2; exit 1; }
        exec bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "supertokens.${RELEASE_VERSION}.$SYMBOL" "$TOKEN" "${FLAGS[@]}"
        ;;
    unlist)
        : "${RELEASE_VERSION:?Set RELEASE_VERSION explicitly (e.g. v1)}"
        [[ $# == 1 ]] || { echo 'unlist requires SYMBOL' >&2; exit 1; }
        ALLOW_UPDATE=1 exec bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "supertokens.${RELEASE_VERSION}.$1" "$ZERO" "${FLAGS[@]}"
        ;;
    register)
        [[ $# == 2 ]] || { echo 'register requires NAME TOKEN' >&2; exit 1; }
        exec bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "tokens.$1" "$2" "${FLAGS[@]}"
        ;;
    reset)
        [[ $# == 2 && "$1" == "$2" ]] || { echo 'reset requires RELEASE CONFIRM_RELEASE (matching explicit confirmation)' >&2; exit 1; }
        ALLOW_UPDATE=1 bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "Superfluid.$1" "$ZERO" "${FLAGS[@]}"
        ALLOW_UPDATE=1 bash "$SCRIPT_DIR/resolver-set-key.sh" "$NETWORK" "TestGovernance.$1" "$ZERO" "${FLAGS[@]}"
        ;;
    *) echo "Unknown resolver operation: $ACTION" >&2; exit 1 ;;
esac
