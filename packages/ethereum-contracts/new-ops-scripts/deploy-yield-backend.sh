#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
require_args 5 'deploy-yield-backend.sh NETWORK aave UNDERLYING POOL RECEIVER | NETWORK spark VAULT RECEIVER REFERRAL'
init_network "${OPS_ARGS[0]}"
ARGS=("${OPS_ARGS[@]:2}")
case "${OPS_ARGS[1]}" in
    aave)
        SIG='runAave(address,address,address)'
        if [[ "${OPS_ARGS[2]}" == 0x0000000000000000000000000000000000000000 ]]; then
            SIG='runAaveETH(address,address)'; ARGS=("${OPS_ARGS[@]:3}")
        fi ;;
    spark) SIG='runSpark(address,address,uint16)' ;;
    *) echo 'Expected aave or spark' >&2; exit 1 ;;
esac
build_forge_auth
VERIFY=()
if (( BROADCAST )) && [[ -n "${ETHERSCAN_API_V2_KEY:-}" ]]; then
    VERIFY=(--verify --verifier etherscan --etherscan-api-key "$ETHERSCAN_API_V2_KEY" --chain-id "$CHAIN_ID" --delay 10 --retries 15)
fi
with_keystore_password forge script foundry-scripts/DeployYieldBackend.s.sol:DeployYieldBackend \
    --rpc-url "$RPC_URL" --sig "$SIG" "${ARGS[@]}" "${AUTH[@]}" "${VERIFY[@]}"
