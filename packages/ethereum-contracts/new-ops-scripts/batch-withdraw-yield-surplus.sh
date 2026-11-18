#!/usr/bin/env bash
# Collect one network's token-admin calls into one Safe transaction.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
(( ! RESUME )) || { echo 'Batch native resume is unsupported; resume a single saved token operation instead.' >&2; exit 1; }
[[ ${#OPS_ARGS[@]} -ge 2 ]] || { echo 'Usage: batch-withdraw-yield-surplus.sh NETWORK TOKEN [TOKEN...] [--broadcast]' >&2; exit 1; }
init_network "${OPS_ARGS[0]}"
prepare_safe_payloads batch-withdraw-yield-surplus
FLAGS=()
(( ! BROADCAST )) || FLAGS+=(--broadcast)
for token in "${OPS_ARGS[@]:1}"; do
    require_address TOKEN "$token"
    SKIP_SAFE_TX_PROPOSAL=1 "$SCRIPT_DIR/super-token-admin-action.sh" "$NETWORK" withdrawSurplusFromYieldBackend "$token" "${FLAGS[@]}"
done
npx ts-node "$SCRIPT_DIR/safe-ops.ts" propose-file --rpc-url "$RPC_URL" \
    --payload-file "$SAFE_PAYLOADS_FILE" --mode batch --require-single-safe \
    --origin "${SAFE_ORIGIN:-batchWithdrawYieldSurplus}" "${FLAGS[@]}"
