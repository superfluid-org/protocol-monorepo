# Common environment, argument, signing and Safe proposal policy.
# All commands simulate unless --broadcast is explicitly supplied.
OPS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PKG_ROOT=$(cd "$OPS_DIR/.." && pwd)
_env=$(set -o posix; export -p)
set -a
# shellcheck source=/dev/null
[[ ! -f "$PKG_ROOT/.env" ]] || source "$PKG_ROOT/.env"
# shellcheck source=/dev/null
[[ ! -f "$PKG_ROOT/../.env" ]] || source "$PKG_ROOT/../.env"
set +a
eval "$_env"
unset _env
METADATA_JSON=${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}
# shellcheck source=/dev/null
source "$OPS_DIR/lib/network-config.sh"

parse_ops_args() {
    BROADCAST=0
    RESUME=0
    OPS_ARGS=()
    for arg in "$@"; do
        case "$arg" in
            --broadcast) BROADCAST=1 ;;
            --resume) RESUME=1 ;;
            --*) echo "Unknown option: $arg" >&2; return 1 ;;
            *) OPS_ARGS+=("$arg") ;;
        esac
    done
    (( ! RESUME || BROADCAST )) || { echo '--resume requires --broadcast' >&2; return 1; }
}

require_args() {
    [[ ${#OPS_ARGS[@]} == "$1" ]] || { echo "Usage: $2 [--broadcast [--resume]]" >&2; return 1; }
}

require_address() {
    [[ "$2" =~ ^0x[a-fA-F0-9]{40}$ ]] || { echo "$1 is not an Ethereum address" >&2; return 1; }
}

# For EOA simulation use its admin, for legacy multisig use an owner, and for
# Safe payload generation any sender suffices. No signing material is read.
get_simulation_sender() {
    local admin=${1:-} owners
    if [[ -n "${DEPLOYER:-${SIMULATION_SENDER:-}}" ]]; then
        printf '%s\n' "${DEPLOYER:-$SIMULATION_SENDER}"
    elif [[ -z "$admin" ]]; then
        printf '%s\n' 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
    elif [[ $(cast code "$admin" --rpc-url "$RPC_URL") == 0x ]]; then
        printf '%s\n' "$admin"
    elif cast call "$admin" 'required()(uint256)' --rpc-url "$RPC_URL" >/dev/null 2>&1; then
        owners=$(cast call "$admin" 'getOwners()(address[])' --rpc-url "$RPC_URL" --json) || return 1
        jq -er '.[0][0]' <<< "$owners"
    else
        printf '%s\n' 0x0000000000000000000000000000000000000001
    fi
}

build_forge_auth() {
    AUTH=()
    export SAFE_PAYLOAD_SIMULATED=true
    if (( BROADCAST )); then
        export SAFE_PAYLOAD_SIMULATED=false
        if [[ -n "${PRIVATE_KEY:-}" ]]; then
            AUTH=(--private-key "$PRIVATE_KEY")
            DEPLOYER=${DEPLOYER:-$(cast wallet address --private-key "$PRIVATE_KEY")} || return 1
        else
            apply_keystore_password_env
            AUTH=(--account "${WALLET_NAME:-sf-ops}")
            DEPLOYER=${DEPLOYER:-$(cast_wallet_address_account "${WALLET_NAME:-sf-ops}")} || return 1
        fi
        AUTH+=(--broadcast --slow)
        (( ! RESUME )) || AUTH+=(--resume)
    else
        DEPLOYER=$(get_simulation_sender "${1:-}") || return 1
        AUTH=(--sender "$DEPLOYER")
    fi
    export DEPLOYER
}

governance_admin() {
    local gov
    gov=$(cast call "$HOST_ADDRESS" 'getGovernance()(address)' --rpc-url "$RPC_URL") || return 1
    cast call "$gov" 'owner()(address)' --rpc-url "$RPC_URL"
}

resolver_admin() {
    if [[ -n "${RESOLVER_ADMIN:-}" ]]; then printf '%s\n' "$RESOLVER_ADMIN"; return; fi
    local count
    count=$(cast call "$RESOLVER_ADDRESS" 'getRoleMemberCount(bytes32)(uint256)' "$(cast to-bytes32 0x00)" --rpc-url "$RPC_URL") || return 1
    [[ "$count" == 1 ]] || { echo 'Select authorized RESOLVER_ADMIN explicitly when multiple admins exist' >&2; return 1; }
    cast call "$RESOLVER_ADDRESS" 'getRoleMember(bytes32,uint256)(address)' "$(cast to-bytes32 0x00)" 0 --rpc-url "$RPC_URL"
}

prepare_safe_payloads() {
    local action=$1 suffix=
    (( BROADCAST )) || suffix=-dry-run
    mkdir -p "$PKG_ROOT/.tmp"
    export SAFE_PAYLOADS_FILE=${SAFE_PAYLOADS_FILE:-$PKG_ROOT/.tmp/$CHAIN_ID-$action$suffix.jsonl}
    (( RESUME )) || : > "$SAFE_PAYLOADS_FILE"
}

submit_safe_payloads() {
    [[ -s "$SAFE_PAYLOADS_FILE" ]] || return 0
    if (( ! BROADCAST )); then cat "$SAFE_PAYLOADS_FILE"; return; fi
    local args=(propose-file --rpc-url "$RPC_URL" --payload-file "$SAFE_PAYLOADS_FILE" --mode single --broadcast)
    [[ -z "${SAFE_ORIGIN:-}" ]] || args+=(--origin "$SAFE_ORIGIN")
    npx ts-node "$OPS_DIR/safe-ops.ts" "${args[@]}"
}

init_network() {
    NETWORK=$1
    RPC_URL=$(get_rpc_url "$NETWORK") || return 1
    CHAIN_ID=$(get_chain_id "$NETWORK") || return 1
    export HOST_ADDRESS=${HOST_ADDRESS:-$(get_host "$NETWORK")}
    export RESOLVER_ADDRESS=${RESOLVER_ADDRESS:-$(get_resolver "$NETWORK")}
    cd "$PKG_ROOT" || return 1
}

# Discovery/verification have read-only options parsed by their leaf CLI.
run_framework_cli() {
    local entry=$1 network=${2:?Network required} rpc
    shift 2
    local args=()
    while (( $# )); do
        case "$1" in
            --rpc-url) RPC_URL=${2:?--rpc-url requires a value}; shift 2 ;;
            *) args+=("$1"); shift ;;
        esac
    done
    rpc=$(get_rpc_url "$network") || return 1
    exec node "$OPS_DIR/$entry" "$network" --rpc-url "$rpc" "${args[@]}"
}
