#!/usr/bin/env bash
# Atomic deployment for native and preminted pure SuperTokens. Permissionless; no admin route.
# Wrapper ERC20s use cast send createERC20Wrapper; listed tokens add resolver-token.sh list.
# Usage: deploy-custom-super-token.sh NETWORK native|pure NAME SYMBOL [INITIAL_SUPPLY_BASE_UNITS]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"
_env=$(set -o posix; export -p); [[ ! -f "$PKG_ROOT/.env" ]] || source "$PKG_ROOT/.env"; [[ ! -f "$PKG_ROOT/../.env" ]] || source "$PKG_ROOT/../.env"; eval "$_env"
source "$SCRIPT_DIR/lib/network-config.sh"
NETWORK="${1:?network required}"
case "${2:-}" in native) export NATIVE_TOKEN=true ;; pure) export NATIVE_TOKEN=false ;; *) echo 'Expected native or pure' >&2; exit 1 ;; esac
export TOKEN_NAME="${3:?name required}" TOKEN_SYMBOL="${4:?symbol required}" INITIAL_SUPPLY="${5:-0}"
RPC=$(get_rpc_url "$NETWORK")
HOST_ADDRESS=${HOST_ADDRESS:-$(get_host "$NETWORK")}
export FACTORY_ADDRESS=${FACTORY_ADDRESS:-$(cast call "$HOST_ADDRESS" 'getSuperTokenFactory()(address)' --rpc-url "$RPC")}
args=(script foundry-scripts/DeployCustomSuperToken.s.sol:DeployCustomSuperToken --rpc-url "$RPC")
if [[ -n "${SIMULATE:-}" ]]; then args+=(--sender "${SIMULATION_SENDER:-0x0000000000000000000000000000000000000001}"); else args+=(--account "${WALLET_NAME:-sf-ops}" --broadcast); fi
cd "$PKG_ROOT"
with_keystore_password forge "${args[@]}"
