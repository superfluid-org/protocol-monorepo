#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/rollout-forwarder.sh"
parse_ops_args "$@"
(( ! RESUME )) || { echo 'Forwarder rollout resumes by rerunning a phase, not --resume.' >&2; exit 1; }
[[ ${#OPS_ARGS[@]} == 2 || ${#OPS_ARGS[@]} == 3 ]] || { echo 'Usage: deploy-forwarder.sh CONTRACT NETWORK [all|deploy|verify|activate|register] [--broadcast]' >&2; exit 1; }
CONTRACT=${OPS_ARGS[0]}
CONFIG=$(jq -ec --arg name "$CONTRACT" '.[$name] // empty' "$SCRIPT_DIR/lib/forwarders.json") || { echo "Unknown forwarder: $CONTRACT" >&2; exit 1; }
EXPECTED=${EXPECTED_ADDRESS:-$(jq -r .address <<< "$CONFIG")}
KEY_ENV=$(jq -r .deployerEnv <<< "$CONFIG")
if [[ $(jq -r .provider <<< "$CONFIG") != true ]]; then export SKIP_GRANT_PROVIDER=1; fi
rollout_forwarder "${OPS_ARGS[1]}" "$CONTRACT" "$CONTRACT" "$EXPECTED" "${!KEY_ENV:-}" "${OPS_ARGS[2]:-all}"
