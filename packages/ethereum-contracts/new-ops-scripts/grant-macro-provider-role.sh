#!/usr/bin/env bash
#
# Grant ClearMacro provider role on SimpleACL for one chain:
# metadata host -> host.getSimpleACL() -> SimpleACL.grantRole(keccak256(provider), grantee)
#
# The grantee is the relay executor (OZ relayer signer), not the forwarder contract.
# Signs with Foundry cast + keystore account (SimpleACL admin EOA):
#   cast send ... --account <WALLET_NAME>
#
# Usage (from packages/ethereum-contracts):
#   ./new-ops-scripts/grant-macro-provider-role.sh <network> <grantee> [provider]
#
# Env (optional):
#   WALLET_NAME                   — Foundry keystore account (default: sf-ops), same as other ops scripts
#   MACRO_PROVIDER_ADMIN_WALLET   — override WALLET_NAME when ACL admin uses a different keystore
#   CLEARMACRO_PROVIDER_GRANTEE — grantee if omitted as arg (rollout sets this)
#   CLEARMACRO_PROVIDER_NAME    — provider string (default: macros.superfluid.eth)
#   SIMULATE=1                  — cast call --trace only (no broadcast)
#   ETH_FROM                    — explicit sender for SIMULATE mode
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
ADMIN_WALLET="${MACRO_PROVIDER_ADMIN_WALLET:-$WALLET_NAME}"
DEFAULT_PROVIDER="${CLEARMACRO_PROVIDER_NAME:-macros.superfluid.eth}"
GRANT_SIG="grantRole(bytes32,address)"

usage() {
    echo "Usage: $0 <network> <grantee> [provider]" >&2
    echo "Env: WALLET_NAME=${WALLET_NAME}, CLEARMACRO_PROVIDER_NAME=${DEFAULT_PROVIDER}" >&2
    echo "     SIMULATE=1 for cast call --trace only" >&2
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
    from=$(cast_wallet_address_account "$ADMIN_WALLET")
    from=$(echo "$from" | tr -d '[:space:]')
    normalize_address "$from" "sender from cast wallet address --account $ADMIN_WALLET"
}

main() {
    local network="${1:-}"
    local grantee="${2:-${CLEARMACRO_PROVIDER_GRANTEE:-}}"
    local provider="${3:-$DEFAULT_PROVIDER}"

    if [[ -z "$network" || -z "$grantee" ]]; then
        usage
        exit 1
    fi
    if [[ -n "${4:-}" ]]; then
        usage
        exit 1
    fi
    if [[ -z "$provider" ]]; then
        echo "provider name is required" >&2
        exit 1
    fi

    grantee=$(normalize_address "$grantee" "grantee")

    if [[ ! -f "$METADATA_JSON" ]]; then
        echo "METADATA_JSON not found: $METADATA_JSON" >&2
        exit 1
    fi

    local rpc host simple_acl provider_role from
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

    provider_role=$(cast keccak "$provider")

    echo "Network:  $network"
    echo "Provider: $provider"
    echo "Role:     $provider_role"
    echo "Grantee:  $grantee"
    echo "SimpleACL: $simple_acl"

    if has_true_result "$(cast call "$simple_acl" "hasRole(bytes32,address)(bool)" "$provider_role" "$grantee" --rpc-url "$rpc")"; then
        echo "$grantee already has provider role for \"$provider\" on $network"
        exit 0
    fi

    if [[ "${SIMULATE:-}" == "1" ]]; then
        from=$(resolve_simulate_from)

        echo "SIMULATE=1: cast call --trace $GRANT_SIG on $simple_acl (from $from, grantee $grantee)"
        cast call \
            "$simple_acl" \
            "$GRANT_SIG" \
            "$provider_role" \
            "$grantee" \
            --rpc-url "$rpc" \
            --trace \
            --from "$from"
        echo "cast call finished (no transaction broadcast)."
        exit 0
    fi

    echo "cast send ... --account $ADMIN_WALLET (network $network)"
    cast_send_account "$ADMIN_WALLET" \
        "$simple_acl" \
        "$GRANT_SIG" \
        "$provider_role" \
        "$grantee" \
        --rpc-url "$rpc"
}

main "$@"
