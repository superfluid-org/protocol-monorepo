#!/usr/bin/env bash
#
# Grant ACL_SUPERAPP_REGISTRATION_ROLE on one chain:
# metadata host -> host.getSimpleACL() -> SimpleACL.grantRole(role, grantee)
#
# Signs with Foundry cast + keystore account:
#   cast send ... --account <WALLET_NAME>
#
# Usage (from packages/ethereum-contracts):
#   ./new-ops-scripts/acl-grant-superapp-registration.sh <network> <grantee>
#
# Env (optional):
#   WALLET_NAME   - Foundry keystore account name (default: sf-ops)
#   SIMULATE=1    - cast call --trace only (no broadcast). Uses ETH_FROM if set, else resolves
#                   sender via cast wallet address --account <WALLET_NAME> (may prompt for password).
#   ETH_FROM      - explicit sender for SIMULATE mode
#   METADATA_JSON, RPC_URL, PROVIDER_URL_OVERRIDE, PROVIDER_URL_TEMPLATE
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
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/lib/network-config.sh" ] && . "$SCRIPT_DIR/lib/network-config.sh"

WALLET_NAME="${WALLET_NAME:-sf-ops}"
GRANT_SIG="grantRole(bytes32,address)"
ACL_SUPERAPP_REGISTRATION_ROLE="0x1fd2cd0659bdcac914c39b66359256350b866e92047951635b57d928f32d9e84"

usage() {
    echo "Usage: $0 <network> <grantee>" >&2
    echo "Env: WALLET_NAME=${WALLET_NAME}, SIMULATE=1 for cast call --trace only" >&2
}

normalize_address() {
    local value=$1
    local label=$2
    if [[ ! "$value" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "invalid $label: $value" >&2
        exit 1
    fi
    cast to-check-sum-address "$value"
}

has_true_result() {
    local out_trim out_lc
    out_trim=$(echo "$1" | tr -d '[:space:]')
    out_lc=$(echo "$out_trim" | tr '[:upper:]' '[:lower:]')
    [[ "$out_lc" == "true" ]] \
        || [[ "$out_lc" == *"true" ]] \
        || [[ "$out_trim" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]
}

resolve_simulate_from() {
    if [[ -n "${ETH_FROM:-}" ]]; then
        normalize_address "$ETH_FROM" "ETH_FROM"
        return
    fi

    local from
    from=$(cast wallet address --account "$WALLET_NAME")
    from=$(echo "$from" | tr -d '[:space:]')
    normalize_address "$from" "sender from cast wallet address --account $WALLET_NAME"
}

main() {
    local network="${1:-}"
    local grantee="${2:-}"

    if [[ -z "$network" || -z "$grantee" || -n "${3:-}" ]]; then
        usage
        exit 1
    fi
    grantee=$(normalize_address "$grantee" "grantee")

    if [[ ! -f "$METADATA_JSON" ]]; then
        echo "METADATA_JSON not found: $METADATA_JSON" >&2
        exit 1
    fi

    local rpc host simple_acl from
    rpc=$(get_rpc_url "$network") || exit 1
    host=$(get_host "$network")
    if [[ -z "$host" || "$host" == "null" ]]; then
        echo "missing/invalid contractsV1.host in metadata for $network" >&2
        exit 1
    fi
    host=$(normalize_address "$host" "contractsV1.host in metadata for $network")

    simple_acl=$(cast call "$host" "getSimpleACL()(address)" --rpc-url "$rpc")
    simple_acl=$(echo "$simple_acl" | tr -d '[:space:]')
    if [[ "$simple_acl" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "invalid SimpleACL from host $host on $network: $simple_acl" >&2
        exit 1
    fi
    simple_acl=$(normalize_address "$simple_acl" "SimpleACL from host $host on $network")

    if has_true_result "$(cast call "$simple_acl" "hasRole(bytes32,address)(bool)" "$ACL_SUPERAPP_REGISTRATION_ROLE" "$grantee" --rpc-url "$rpc")"; then
        echo "$grantee already has ACL_SUPERAPP_REGISTRATION_ROLE on $network"
        exit 0
    fi

    if [[ "${SIMULATE:-}" == "1" ]]; then
        from=$(resolve_simulate_from)

        echo "SIMULATE=1: cast call --trace $GRANT_SIG on $simple_acl (from $from, grantee $grantee)"
        cast call \
            "$simple_acl" \
            "$GRANT_SIG" \
            "$ACL_SUPERAPP_REGISTRATION_ROLE" \
            "$grantee" \
            --rpc-url "$rpc" \
            --trace \
            --from "$from"
        echo "cast call finished (no transaction broadcast)."
        exit 0
    fi

    echo "cast send ... --account $WALLET_NAME (network $network)"
    cast send \
        "$simple_acl" \
        "$GRANT_SIG" \
        "$ACL_SUPERAPP_REGISTRATION_ROLE" \
        "$grantee" \
        --rpc-url "$rpc" \
        --account "$WALLET_NAME"
}

main "$@"
