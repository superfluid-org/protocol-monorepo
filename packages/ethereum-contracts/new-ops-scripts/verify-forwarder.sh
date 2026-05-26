#!/usr/bin/env bash
set -eu
set -o pipefail

# Step 2 (optional) — Etherscan-verify a deployed forwarder.
#
# Usage:
#   new-ops-scripts/verify-forwarder.sh <network> <contractName> <address>
#
# Env: ETHERSCAN_API_V2_KEY (required), RPC_URL / PROVIDER_URL_* (see network-config.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"

# shellcheck source=/dev/null
[[ -f "$PKG_ROOT/.env" ]] && source "$PKG_ROOT/.env"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/lib/network-config.sh" ]] && source "$SCRIPT_DIR/lib/network-config.sh"

network="${1:?Usage: $0 <network> <contractName> <address>}"
contract="${2:?Usage: $0 <network> <contractName> <address>}"
addr="${3:?Usage: $0 <network> <contractName> <address>}"

chain_id=$(get_chain_id "$network")
rpc=$(get_rpc_url "$network") || exit 1
host=$(get_host "$network")

echo "Verifying $contract at $addr on $network (chain $chain_id)"
sleep 5

# Scroll uses Scrollscan (blockscout-style), which is not included in Etherscan v2's chain allowlist.
# Route verification through Scrollscan when deploying on Scroll networks.
if [[ "$network" == "scroll-sepolia" ]]; then
    : "${SCROLLSCAN_API_KEY:?SCROLLSCAN_API_KEY is required for scroll-sepolia verification}"
    VERIFIER_CUSTOM_URL="https://sepolia.scrollscan.com/api"
    VERIFIER_ARGS=(
        --verifier custom
        --verifier-url "$VERIFIER_CUSTOM_URL"
        --verifier-api-key "$SCROLLSCAN_API_KEY"
    )
elif [[ "$network" == "scroll-mainnet" ]]; then
    : "${SCROLLSCAN_API_KEY:?SCROLLSCAN_API_KEY is required for scroll-mainnet verification}"
    VERIFIER_CUSTOM_URL="https://scrollscan.com/api"
    VERIFIER_ARGS=(
        --verifier custom
        --verifier-url "$VERIFIER_CUSTOM_URL"
        --verifier-api-key "$SCROLLSCAN_API_KEY"
    )
else
    if [[ -z "${ETHERSCAN_API_V2_KEY:-}" ]]; then
        echo "ETHERSCAN_API_V2_KEY is required" >&2
        exit 1
    fi
    VERIFIER_ARGS=(
        --verifier etherscan
        --etherscan-api-key "$ETHERSCAN_API_V2_KEY"
    )
fi

# Run from PKG_ROOT so forge picks up packages/ethereum-contracts/foundry.toml.
# From repo root there is no foundry.toml and source paths fail to resolve.
cd "$PKG_ROOT"
forge verify-contract \
    "$addr" \
    "packages/ethereum-contracts/contracts/utils/${contract}.sol:${contract}" \
    --constructor-args "$(cast abi-encode "constructor(address)" "$host")" \
    --rpc-url "$rpc" \
    "${VERIFIER_ARGS[@]}" \
    --chain-id "$chain_id"
