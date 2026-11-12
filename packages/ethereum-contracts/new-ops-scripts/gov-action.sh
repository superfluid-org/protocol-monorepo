#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
NETWORK=${OPS_ARGS[0]:?Network required}
ACTION=${OPS_ARGS[1]:?Governance action required}
case "$ACTION" in
    setTokenMinimumDeposit) TYPES='address,uint256'; COUNT=2 ;;
    set3PsConfig) TYPES='address,uint256,uint256'; COUNT=3 ;;
    clear3PsConfig|clearRewardAddress|registerAgreementClass|replaceGovernance) TYPES=address; COUNT=1 ;;
    setRewardAddress|enableTrustedForwarder|disableTrustedForwarder|changeSuperTokenAdmin) TYPES='address,address'; COUNT=2 ;;
    batchChangeSuperTokenAdmin) TYPES='address[],address[]'; COUNT=2 ;;
    setAppRegistrationKey)
        TYPES='address,uint256,string'; COUNT=3
        [[ ${#OPS_ARGS[@]} -ge 3 && ${#OPS_ARGS[@]} -le 5 ]] || { echo 'setAppRegistrationKey DEPLOYER [EXPIRATION_TS] [KEY]' >&2; exit 1; }
        OPS_ARGS[3]=${OPS_ARGS[3]:-18446744073709551615}
        OPS_ARGS[4]=${OPS_ARGS[4]:-k1} ;;
    *) echo "Unknown governance action: $ACTION" >&2; exit 1 ;;
esac
require_args "$((COUNT + 2))" 'gov-action.sh NETWORK ACTION ARGS'
init_network "$NETWORK"
require_address HOST_ADDRESS "$HOST_ADDRESS"
ADMIN=
(( BROADCAST )) || ADMIN=$(governance_admin)
build_forge_auth "$ADMIN"
prepare_safe_payloads "gov-$ACTION"
with_keystore_password forge script foundry-scripts/GovAction.s.sol:GovAction \
    --rpc-url "$RPC_URL" --sig "$ACTION($TYPES)" "${OPS_ARGS[@]:2}" "${AUTH[@]}"
submit_safe_payloads
