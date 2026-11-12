#!/usr/bin/env bash
# Atomic deployment of native or preminted pure SuperTokens.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
[[ ${#OPS_ARGS[@]} == 4 || ${#OPS_ARGS[@]} == 5 ]] || { echo 'Usage: deploy-custom-super-token.sh NETWORK native|pure NAME SYMBOL [SUPPLY] [--broadcast]' >&2; exit 1; }
case "${OPS_ARGS[1]}" in native) export NATIVE_TOKEN=true ;; pure) export NATIVE_TOKEN=false ;; *) echo 'Expected native or pure' >&2; exit 1 ;; esac
export TOKEN_NAME=${OPS_ARGS[2]} TOKEN_SYMBOL=${OPS_ARGS[3]} INITIAL_SUPPLY=${OPS_ARGS[4]:-0}
init_network "${OPS_ARGS[0]}"
export FACTORY_ADDRESS=${FACTORY_ADDRESS:-$(cast call "$HOST_ADDRESS" 'getSuperTokenFactory()(address)' --rpc-url "$RPC_URL")}
build_forge_auth
with_keystore_password forge script foundry-scripts/DeployCustomSuperToken.s.sol:DeployCustomSuperToken --rpc-url "$RPC_URL" "${AUTH[@]}"
