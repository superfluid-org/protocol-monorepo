#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
ACTION=${OPS_ARGS[1]:?Action required}
case "$ACTION" in
    enableYieldBackend) COUNT=4; SIG='enableYieldBackend(address,address,address)' ;;
    disableYieldBackend|withdrawSurplusFromYieldBackend) COUNT=3; SIG="$ACTION(address,address)" ;;
    *) echo "Unknown token admin action: $ACTION" >&2; exit 1 ;;
esac
require_args "$COUNT" 'super-token-admin-action.sh NETWORK ACTION TOKEN [BACKEND]'
init_network "${OPS_ARGS[0]}"
OVERRIDE=${SUPER_TOKEN_ADMIN_OVERRIDE:-0x0000000000000000000000000000000000000000}
ADMIN=$OVERRIDE
if (( ! BROADCAST )) && [[ "$ADMIN" == 0x0000000000000000000000000000000000000000 ]]; then
    ADMIN=$(cast call "${OPS_ARGS[2]}" 'getAdmin()(address)' --rpc-url "$RPC_URL")
fi
build_forge_auth "$ADMIN"
# Batch callers own the shared collection and must not have it truncated per token.
if [[ -z "${SKIP_SAFE_TX_PROPOSAL:-}" ]]; then prepare_safe_payloads "token-$ACTION"; fi
with_keystore_password forge script foundry-scripts/SuperTokenAdminAction.s.sol:SuperTokenAdminAction \
    --rpc-url "$RPC_URL" --sig "$SIG" "${OPS_ARGS[@]:2}" "$OVERRIDE" "${AUTH[@]}"
if [[ -z "${SKIP_SAFE_TX_PROPOSAL:-}" ]]; then submit_safe_payloads; fi
