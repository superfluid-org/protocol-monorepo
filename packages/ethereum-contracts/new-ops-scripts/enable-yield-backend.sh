#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
[[ ${#OPS_ARGS[@]} == 3 || ${#OPS_ARGS[@]} == 4 ]] || { echo 'Usage: enable-yield-backend.sh NETWORK TOKEN BACKEND [ADMIN_OVERRIDE] [--broadcast]' >&2; exit 1; }
if [[ ${#OPS_ARGS[@]} == 4 ]]; then export SUPER_TOKEN_ADMIN_OVERRIDE=${OPS_ARGS[3]}; fi
FLAGS=()
(( ! BROADCAST )) || FLAGS+=(--broadcast)
(( ! RESUME )) || FLAGS+=(--resume)
exec "$SCRIPT_DIR/super-token-admin-action.sh" "${OPS_ARGS[0]}" enableYieldBackend "${OPS_ARGS[@]:1:2}" "${FLAGS[@]}"
