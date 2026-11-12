#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
NETWORK=${OPS_ARGS[0]:?Usage: framework.sh NETWORK ACTION [ARGS] [--broadcast [--resume]]}
ACTION=${OPS_ARGS[1]:?Operation required}
SCRIPT=foundry-scripts/Framework.s.sol:FrameworkScript
case "$ACTION" in
    fresh) SIGNATURE='fresh()'; COUNT=0 ;;
    upgrade) SIGNATURE='upgrade()'; COUNT=0 ;;
    upgrade-governance) SIGNATURE='upgradeGovernance()'; COUNT=0 ;;
    upgrade-tokens) SIGNATURE='upgradeTokens(address[])'; COUNT=1
        [[ "${OPS_ARGS[2]:-}" != ALL ]] || { echo 'ALL token discovery is not implemented; supply a reviewed explicit address array.' >&2; exit 1; } ;;
    handover-governance) SIGNATURE='handoverGovernance(address)'; COUNT=1 ;;
    handover-acl) SIGNATURE='handoverACL(address)'; COUNT=1 ;;
    grant-resolver-admin) SIGNATURE='grantResolverAdmin(address)'; COUNT=1 ;;
    revoke-resolver-admin) SIGNATURE='revokeResolverAdmin(address,address)'; COUNT=2 ;;
    provision-test-token) SCRIPT=foundry-scripts/ProvisionTestToken.s.sol:ProvisionTestToken
        SIGNATURE='run(string,string,uint8,uint256)'; COUNT=4 ;;
    *) echo 'Supported actions: fresh, upgrade, upgrade-governance, upgrade-tokens, handover-governance, handover-acl, grant-resolver-admin, revoke-resolver-admin, provision-test-token' >&2; exit 1 ;;
esac
require_args "$((COUNT + 2))" 'framework.sh NETWORK ACTION [ARGS]'
ARGS=("${OPS_ARGS[@]:2}")
if [[ "$ACTION" == fresh && -n "${RESOLVER_ADDRESS:-}" && "$RESOLVER_ADDRESS" != 0x0000000000000000000000000000000000000000 ]]; then
    echo 'Fresh creates a new resolver; use resolver-set-key for an existing resolver' >&2; exit 1
fi
init_network "$NETWORK"
if [[ "$ACTION" == fresh ]]; then
    EXISTING_HOST=$(get_host "$NETWORK")
    if [[ -n "$EXISTING_HOST" && "$EXISTING_HOST" != 0x0000000000000000000000000000000000000000 && "${ALLOW_EXISTING_FRAMEWORK:-0}" != 1 ]]; then
        echo 'Metadata already contains a host; intentional replacement requires ALLOW_EXISTING_FRAMEWORK=1' >&2; exit 1
    fi
    # Fresh always creates a resolver, not the metadata resolver.
    unset RESOLVER_ADDRESS
    if (( BROADCAST && ! RESUME )) && [[ -f "${FOUNDRY_BROADCAST:-broadcast}/Framework.s.sol/$CHAIN_ID/fresh-latest.json" ]]; then
        echo 'Fresh broadcast artifacts already exist. Use --broadcast --resume; archive artifacts before an intentional new deployment.' >&2; exit 1
    fi
fi
ADMIN=
if (( ! BROADCAST )); then
    case "$ACTION" in
        revoke-resolver-admin) ADMIN=${ARGS[0]} ;;
        grant-resolver-admin|provision-test-token) ADMIN=$(resolver_admin) ;;
        handover-acl)
            [[ -n "${DEPLOYER:-${SIMULATION_SENDER:-}}" ]] || { echo 'ACL simulation requires DEPLOYER or SIMULATION_SENDER with authority.' >&2; exit 1; } ;;
        fresh) ;;
        *) ADMIN=$(governance_admin) ;;
    esac
fi
build_forge_auth "$ADMIN"
export RELEASE_VERSION=${RELEASE_VERSION:-v1}
prepare_safe_payloads "framework-$ACTION"
with_keystore_password forge script "$SCRIPT" --rpc-url "$RPC_URL" --sig "$SIGNATURE" "${ARGS[@]}" "${AUTH[@]}"
submit_safe_payloads
