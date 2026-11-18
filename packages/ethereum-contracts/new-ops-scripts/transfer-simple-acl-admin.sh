#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
require_args 2 'transfer-simple-acl-admin.sh NETWORK RECIPIENT'
init_network "${OPS_ARGS[0]}"
if (( ! BROADCAST )) && [[ -z "${DEPLOYER:-${SIMULATION_SENDER:-}}" ]]; then
    echo 'ACL simulation requires DEPLOYER or SIMULATION_SENDER holding DEFAULT_ADMIN_ROLE.' >&2; exit 1
fi
build_forge_auth
ACL=$(cast call "$HOST_ADDRESS" 'getSimpleACL()(address)' --rpc-url "$RPC_URL")
with_keystore_password forge script foundry-scripts/ACLAction.s.sol:ACLAction --rpc-url "$RPC_URL" \
    --sig 'transferAdmin(address,address)' "$ACL" "${OPS_ARGS[1]}" "${AUTH[@]}"
