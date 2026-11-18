#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
require_args 2 'deploy-deterministic-forwarder.sh NETWORK CONTRACT'
(( ! RESUME )) || { echo 'Deterministic deployment resumes by rerunning the rollout after checking deployed code, not --resume.' >&2; exit 1; }
init_network "${OPS_ARGS[0]}"
FLAGS=()
(( ! BROADCAST )) || FLAGS+=(--broadcast)
if (( BROADCAST )) && [[ -z "${PRIVATE_KEY:-}" ]]; then apply_keystore_password_env; fi
npx ts-node "$SCRIPT_DIR/deploy-deterministic-forwarder.ts" "${OPS_ARGS[@]}" \
    --rpc-url "$RPC_URL" --host "$HOST_ADDRESS" --chain-id "$CHAIN_ID" "${FLAGS[@]}"
