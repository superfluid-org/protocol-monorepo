#!/usr/bin/env bash
# Explicit production operations. Default is Foundry simulation; never submits proposals.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PKG_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# Preserve caller-exported environment over package/parent .env defaults.
# shellcheck source=/dev/null
_env=$(set -o posix; export -p); [[ ! -f "$PKG_ROOT/.env" ]] || source "$PKG_ROOT/.env"; [[ ! -f "$PKG_ROOT/../.env" ]] || source "$PKG_ROOT/../.env"; eval "$_env"
METADATA_JSON=${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/network-config.sh"
NETWORK=${1:?Usage: framework.sh NETWORK fresh|upgrade|upgrade-governance|upgrade-tokens|handover-governance|grant-resolver-admin|revoke-resolver-admin [ARGS] [--broadcast|--resume]}
ACTION=${2:?Operation required}
shift 2
for retired in NON_UPGRADABLE USE_MOCKS RESET_SUPERFLUID_FRAMEWORK CREATE_NEW_RESOLVER \
    NEW_SUPERFLUID_LOADER WITHOUT_ERC1820 NO_NEW_GOVERNANCE DISABLE_TEST_GOVERNANCE \
    ENABLE_APP_WHITELISTING APP_CALLBACK_GAS_LIMIT ALLOW_DECREASE_APP_CALLBACK_GAS_LIMIT \
    OUTPUT_FILE DRY_RUN; do
    if [[ -v "$retired" ]]; then
        echo "$retired is retired. Use explicit framework operations and reviewed policy overrides; see README Persistent framework deployment and upgrades." >&2
        exit 1
    fi
done
SCRIPT=foundry-scripts/Framework.s.sol:FrameworkScript
case "$ACTION" in
    fresh) SIGNATURE='fresh()'; COUNT=0 ;;
    upgrade) SIGNATURE='upgrade()'; COUNT=0 ;;
    upgrade-governance) SIGNATURE='upgradeGovernance()'; COUNT=0 ;;
    upgrade-tokens) SIGNATURE='upgradeTokens(address[])'; COUNT=1
        [[ "${1:-}" != ALL ]] || { echo 'ALL token discovery is not implemented. Supply a reviewed explicit address array after framework upgrade execution.' >&2; exit 1; } ;;
    handover-governance) SIGNATURE='handoverGovernance(address)'; COUNT=1 ;;
    grant-resolver-admin) SIGNATURE='grantResolverAdmin(address)'; COUNT=1 ;;
    revoke-resolver-admin) SIGNATURE='revokeResolverAdmin(address,address)'; COUNT=2 ;;
    provision-test-token) SCRIPT=foundry-scripts/ProvisionTestToken.s.sol:ProvisionTestToken
        SIGNATURE='run(string,string,uint8,uint256)'; COUNT=4 ;;
    *) echo "Unsupported framework operation: $ACTION" >&2; exit 1 ;;
esac
ARGS=()
for ((i=0; i<COUNT; i++)); do ARGS+=("${1:?Missing operation argument}"); shift; done
BROADCAST=0
RESUME=0
for flag in "$@"; do
    case "$flag" in
        --broadcast) BROADCAST=1 ;;
        --resume) BROADCAST=1; RESUME=1 ;;
        *) echo "Unsupported option: $flag" >&2; exit 1 ;;
    esac
done
RPC_URL=$(get_rpc_url "$NETWORK")
export HOST_ADDRESS=${HOST_ADDRESS:-$(get_host "$NETWORK")}
export RELEASE_VERSION=${RELEASE_VERSION:-v1}
mkdir -p "$PKG_ROOT/.tmp"
export SAFE_PAYLOADS_FILE=${SAFE_PAYLOADS_FILE:-.tmp/framework-safe-payloads.jsonl}
# Preserve payloads on resume; a new invocation starts a new payload collection.
cd "$PKG_ROOT"
if [[ "$ACTION" == fresh ]] && (( BROADCAST && ! RESUME )); then
    CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
    if [[ -f "${FOUNDRY_BROADCAST:-broadcast}/Framework.s.sol/$CHAIN_ID/fresh-latest.json" ]]; then
        echo 'Fresh broadcast artifacts already exist. Use --resume to finish them; archive the broadcast/cache artifacts explicitly before an intentional new framework deployment.' >&2
        exit 1
    fi
fi
if (( ! RESUME )); then : > "$SAFE_PAYLOADS_FILE"; fi
AUTH=()
if (( BROADCAST )); then
    if [[ -n "${PRIVATE_KEY:-}" ]]; then
        AUTH=(--private-key "$PRIVATE_KEY")
        export DEPLOYER=${DEPLOYER:-$(cast wallet address --private-key "$PRIVATE_KEY")}
    else
        AUTH=(--account "${WALLET_NAME:-sf-ops}")
        export DEPLOYER=${DEPLOYER:-$(cast_wallet_address_account "${WALLET_NAME:-sf-ops}")}
    fi
    AUTH+=(--broadcast --slow)
    (( ! RESUME )) || AUTH+=(--resume)
else
    # Unlocked simulation sender is sufficient. No signing key is read or required.
    if [[ -z "${DEPLOYER:-}" && "$ACTION" != fresh && "$ACTION" != provision-test-token && "$ACTION" != *resolver-admin ]]; then
        GOV=$(cast call "$HOST_ADDRESS" 'getGovernance()(address)' --rpc-url "$RPC_URL")
        export DEPLOYER=$(cast call "$GOV" 'owner()(address)' --rpc-url "$RPC_URL")
    fi
    export DEPLOYER=${DEPLOYER:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}
    AUTH=(--sender "$DEPLOYER")
fi
with_keystore_password forge script "$SCRIPT" --rpc-url "$RPC_URL" \
    --sig "$SIGNATURE" "${ARGS[@]}" "${AUTH[@]}"
echo "Safe payloads (not submitted): $SAFE_PAYLOADS_FILE"
if [[ -s "$SAFE_PAYLOADS_FILE" ]]; then cat "$SAFE_PAYLOADS_FILE"; fi
