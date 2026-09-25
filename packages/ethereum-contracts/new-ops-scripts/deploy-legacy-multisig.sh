#!/usr/bin/env bash
#
# Deploy the legacy Gnosis MultiSigWallet used as the resolver admin on recent mainnets.
# Init code is the Base/Scroll creation bytecode with constructor arguments removed.
# A local deploy of that code reproduces runtime hash
# 0x4f2d2a000021b45b6faa718a04464eed65365b687475ffbf5fa2d846717f346f
# which matches Optimism, Arbitrum, Base, Scroll, Avalanche, BNB, and Celo.
# Ethereum mainnet is an older build and is not what this script deploys.
#
# 0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015 is an owner EOA of those wallets, not the wallet itself.
#
# Usage (from packages/ethereum-contracts):
#   WALLET_NAME=handover_acc ./new-ops-scripts/deploy-legacy-multisig.sh <network> <required> <owner> [owner...]
#
# Example for arc-mainnet with typical configuration (1 required signer and the usual 3 signers set):
#   WALLET_NAME=handover_acc ./new-ops-scripts/deploy-legacy-multisig.sh arc-mainnet 1 \
#     0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015 \
#     0x568658Dd13A880fF8418Efe194004019A675955F \
#     0x2b61101447829abC7a92Ce34A366A582FE0d5096
#
# Constructor arguments are appended in the legacy layout this bytecode expects:
#   required, 0, ownerCount, owners...
# Modern ABI encoding does not match and the constructor reverts.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"
EXPECTED_RUNTIME="0x4f2d2a000021b45b6faa718a04464eed65365b687475ffbf5fa2d846717f346f"

# shellcheck source=/dev/null
_env=$(set -o posix; export -p); [[ -f "$PKG_ROOT/.env" ]] && source "$PKG_ROOT/.env"; [[ -f "$PKG_ROOT/../.env" ]] && source "$PKG_ROOT/../.env"; eval "$_env"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/lib/network-config.sh" ] && . "$SCRIPT_DIR/lib/network-config.sh"

WALLET_NAME="${WALLET_NAME:-sf-ops}"

usage() {
    echo "Usage: WALLET_NAME=<keystore> $0 <network> <required> <owner> [owner...]" >&2
}

# Legacy constructor suffix. Not standard ABI.
encode_legacy_constructor() {
    local required=$1
    shift
    local out
    out=$(cast to-uint256 "$required")
    out+=$(cast to-uint256 0 | sed 's/^0x//')
    out+=$(cast to-uint256 "$#" | sed 's/^0x//')
    local owner
    for owner in "$@"; do
        out+=$(cast abi-encode "f(address)" "$owner" | sed 's/^0x//')
    done
    echo "$out"
}

main() {
    local network="${1:-}"
    local required="${2:-}"
    shift 2 || true
    local -a owners=("$@")

    if [[ -z "$network" || -z "$required" || ${#owners[@]} -eq 0 ]]; then
        usage
        exit 1
    fi
    if [[ ! "$required" =~ ^[0-9]+$ || "$required" -lt 1 || "$required" -gt ${#owners[@]} ]]; then
        echo "required must be between 1 and the number of owners" >&2
        exit 1
    fi

    local rpc owner
    rpc=$(get_rpc_url "$network") || exit 1
    local -a checksummed=()
    for owner in "${owners[@]}"; do
        checksummed+=("$(cast to-check-sum-address "$owner")")
    done

    local init args data
    init=$(tr -d '[:space:]' < "$SCRIPT_DIR/lib/legacy-multisig-init.hex")
    [[ "$init" == 0x* ]] || init="0x$init"
    args=$(encode_legacy_constructor "$required" "${checksummed[@]}")
    data="${init}${args#0x}"

    echo "Network:  $network"
    echo "Signer:   $WALLET_NAME"
    echo "Required: $required"
    echo "Owners:"
    for owner in "${checksummed[@]}"; do
        echo "  $owner"
    done

    local out addr got
    out=$(cast_send_account "$WALLET_NAME" --rpc-url "$rpc" --json --create "$data")
    addr=$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])')
    addr=$(cast to-check-sum-address "$addr")

    got=$(cast keccak "$(cast code "$addr" --rpc-url "$rpc")")
    if [[ "${got,,}" != "${EXPECTED_RUNTIME,,}" ]]; then
        echo "deployed $addr but runtime hash $got != $EXPECTED_RUNTIME" >&2
        exit 1
    fi

    echo "MultiSigWallet: $addr"
    echo "required() $(cast call "$addr" "required()(uint256)" --rpc-url "$rpc")"
    echo "getOwners() $(cast call "$addr" "getOwners()(address[])" --rpc-url "$rpc")"
}

main "$@"
