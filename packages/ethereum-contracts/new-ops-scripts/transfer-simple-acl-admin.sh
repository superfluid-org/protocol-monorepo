#!/usr/bin/env bash
#
# Hand SimpleACL admin from the Foundry keystore account to an explicit recipient.
#
# Usage (from packages/ethereum-contracts):
#   ./new-ops-scripts/transfer-simple-acl-admin.sh <network> <recipient>
#
# Example:
#   ./new-ops-scripts/transfer-simple-acl-admin.sh base-mainnet 0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015
#
# Addresses are read from chain:
#   host            — metadata contractsV1.host
#   SimpleACL       — host.getSimpleACL()
#   signer          — cast wallet address --account $WALLET_NAME
#
# The signer must hold DEFAULT_ADMIN_ROLE. ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN
# is moved too when the signer holds it. Both grants happen before either revoke.
# The pool-connect admin role (held by GDA) is left unchanged.
#
# Env (optional), same as the other cast ops scripts:
#   WALLET_NAME              — Foundry keystore account (default: sf-ops)
#   KEYSTORE_PASSWORD        — password in .env (empty string is valid)
#   KEYSTORE_PASSWORD_FILE   — or path to a password file
#   SIMULATE=1               — cast call --trace only (no broadcast)
#   METADATA_JSON, RPC_URL, PROVIDER_URL_OVERRIDE, PROVIDER_URL_TEMPLATE
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

WALLET_NAME="${WALLET_NAME:-sf-ops}"
DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"

usage() {
    echo "Usage: $0 <network> <recipient>" >&2
    echo "Env: WALLET_NAME=${WALLET_NAME}, SIMULATE=1 for cast call --trace only" >&2
}

normalize_address() {
    local value=$1
    local label=$2
    value=$(echo "$value" | tr -d '[:space:]')
    if [[ ! "$value" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "invalid $label: $value" >&2
        exit 1
    fi
    cast to-check-sum-address "$value"
}

has_role() {
    local role=$1
    local account=$2
    local out
    out=$(cast call "$SIMPLE_ACL" "hasRole(bytes32,address)(bool)" "$role" "$account" --rpc-url "$RPC" | tr -d '[:space:]')
    [[ "$out" == "true" || "$out" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]
}

send_role_call() {
    local action=$1
    local role=$2
    local account=$3
    echo "$action $role → $account"
    if [[ "${SIMULATE:-}" == "1" ]]; then
        cast call \
            "$SIMPLE_ACL" \
            "${action}(bytes32,address)" \
            "$role" \
            "$account" \
            --rpc-url "$RPC" \
            --trace \
            --from "$SIGNER"
        return
    fi
    cast_send_account "$WALLET_NAME" \
        "$SIMPLE_ACL" \
        "${action}(bytes32,address)" \
        "$role" \
        "$account" \
        --rpc-url "$RPC"
}

main() {
    local network="${1:-}"
    local recipient_arg="${2:-}"
    if [[ -z "$network" || -z "$recipient_arg" || -n "${3:-}" ]]; then
        usage
        exit 1
    fi

    RPC=$(get_rpc_url "$network") || exit 1
    local host
    host=$(get_host "$network")
    host=$(normalize_address "$host" "contractsV1.host for $network")

    SIMPLE_ACL=$(cast call "$host" "getSimpleACL()(address)" --rpc-url "$RPC")
    SIMPLE_ACL=$(normalize_address "$SIMPLE_ACL" "SimpleACL")

    local new_admin
    new_admin=$(normalize_address "$recipient_arg" "recipient")
    if [[ "$new_admin" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "recipient is the zero address" >&2
        exit 1
    fi

    SIGNER=$(cast_wallet_address_account "$WALLET_NAME")
    SIGNER=$(normalize_address "$SIGNER" "cast wallet address --account $WALLET_NAME")

    local superapp_admin
    superapp_admin=$(cast keccak "ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN")

    echo "Network:    $network"
    echo "SimpleACL:  $SIMPLE_ACL"
    echo "Signer:     $SIGNER ($WALLET_NAME)"
    echo "Recipient:  $new_admin"

    if [[ "$(echo "$SIGNER" | tr '[:upper:]' '[:lower:]')" == "$(echo "$new_admin" | tr '[:upper:]' '[:lower:]')" ]]; then
        echo "Signer is already the recipient. Nothing to transfer."
        exit 0
    fi

    if ! has_role "$DEFAULT_ADMIN_ROLE" "$SIGNER"; then
        echo "$WALLET_NAME ($SIGNER) does not have DEFAULT_ADMIN_ROLE on $SIMPLE_ACL" >&2
        exit 1
    fi

    local move_superapp=0
    if has_role "$superapp_admin" "$SIGNER"; then
        move_superapp=1
    fi

    if ! has_role "$DEFAULT_ADMIN_ROLE" "$new_admin"; then
        send_role_call grantRole "$DEFAULT_ADMIN_ROLE" "$new_admin"
    else
        echo "recipient already has DEFAULT_ADMIN_ROLE"
    fi
    if [[ "$move_superapp" -eq 1 ]]; then
        if ! has_role "$superapp_admin" "$new_admin"; then
            send_role_call grantRole "$superapp_admin" "$new_admin"
        else
            echo "recipient already has ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN"
        fi
    fi

    if [[ "$move_superapp" -eq 1 ]] && has_role "$superapp_admin" "$SIGNER"; then
        send_role_call revokeRole "$superapp_admin" "$SIGNER"
    fi
    if has_role "$DEFAULT_ADMIN_ROLE" "$SIGNER"; then
        send_role_call revokeRole "$DEFAULT_ADMIN_ROLE" "$SIGNER"
    fi

    echo "SimpleACL admin transferred to $new_admin"
}

main "$@"
