#!/usr/bin/env bash
# ROLE is a name hashed with keccak256 (e.g. ACL_SUPERAPP_REGISTRATION_ROLE or macros.superfluid.eth).
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
require_args 3 'acl-grant-role.sh NETWORK ROLE GRANTEE'
init_network "${OPS_ARGS[0]}"
require_address GRANTEE "${OPS_ARGS[2]}"
ACL=$(cast call "$HOST_ADDRESS" 'getSimpleACL()(address)' --rpc-url "$RPC_URL")
ROLE=$(cast keccak "${OPS_ARGS[1]}")
ADMIN=
if (( ! BROADCAST )) && [[ -z "${DEPLOYER:-${SIMULATION_SENDER:-}}" ]]; then
    echo 'ACL simulation requires DEPLOYER or SIMULATION_SENDER holding the role admin; SimpleACL is not enumerable.' >&2
    exit 1
fi
build_forge_auth "$ADMIN"
with_keystore_password forge script foundry-scripts/ACLAction.s.sol:ACLAction --rpc-url "$RPC_URL" \
    --sig 'grant(address,bytes32,address)' "$ACL" "$ROLE" "${OPS_ARGS[2]}" "${AUTH[@]}"
