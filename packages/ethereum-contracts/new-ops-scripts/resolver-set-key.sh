#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
require_args 3 'resolver-set-key.sh NETWORK KEY ADDRESS'
init_network "${OPS_ARGS[0]}"
require_address RESOLVER_ADDRESS "$RESOLVER_ADDRESS"
require_address VALUE "${OPS_ARGS[2]}"
ADMIN=
(( BROADCAST )) || ADMIN=$(resolver_admin)
build_forge_auth "$ADMIN"
prepare_safe_payloads resolver-set-key
ALLOW=false
[[ "${ALLOW_UPDATE:-0}" != 1 ]] || ALLOW=true
with_keystore_password forge script foundry-scripts/ResolverSetKey.s.sol:ResolverSetKey \
    --rpc-url "$RPC_URL" --sig 'run(address,string,address,bool)' \
    "$RESOLVER_ADDRESS" "${OPS_ARGS[1]}" "${OPS_ARGS[2]}" "$ALLOW" "${AUTH[@]}"
submit_safe_payloads
