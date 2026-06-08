#!/usr/bin/env bash
set -eu
set -o pipefail

# Step 1 — Deterministic forwarder deploy only (see deploy-deterministic-forwarder.ts).
# Full rollout: deploy-clearmacro-forwarder.sh or steps 2–4 individually.
#
# Usage:
#   new-ops-scripts/deploy-deterministic-forwarder.sh <network> <contractName>
#
# Env: DETERMINISTIC_DEPLOYER_PK, WALLET_NAME (default sf-ops), SIMULATE=1, etc.
# Prerequisite: forge build

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"

# shellcheck source=/dev/null
[[ -f "$PKG_ROOT/.env" ]] && source "$PKG_ROOT/.env"
# shellcheck source=/dev/null
[[ -f "$PKG_ROOT/../.env" ]] && source "$PKG_ROOT/../.env"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/lib/network-config.sh" ]] && source "$SCRIPT_DIR/lib/network-config.sh"

network="${1:?Usage: $0 <network> <contractName>}"
contract="${2:?Usage: $0 <network> <contractName>}"
rpc=$(get_rpc_url "$network") || exit 1
host=$(get_host "$network")
chain_id=$(get_chain_id "$network")

cd "$PKG_ROOT"
npx ts-node "$SCRIPT_DIR/deploy-deterministic-forwarder.ts" \
    "$network" \
    "$contract" \
    --rpc-url "$rpc" \
    --host "$host" \
    --chain-id "$chain_id"
