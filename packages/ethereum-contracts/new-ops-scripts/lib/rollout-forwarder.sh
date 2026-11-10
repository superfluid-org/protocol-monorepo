#!/usr/bin/env bash
# Source from forwarder tasks. Deploy → verify → activate → confirm execution → register.
# Optional sixth argument / FORWARDER_PHASE: all (default), deploy, verify, activate, register.
# Rerun register after a pending governance transaction executes; a proposal is not activation.
# Existing ClearMacro callers may additionally grant a provider role after registration.
# Flags: SKIP_DEPLOY, SKIP_VERIFY, SKIP_ACTIVATE, SKIP_REGISTER, SKIP_GRANT_PROVIDER, SIMULATE.

_OPS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_PKG_ROOT="$(cd "$_OPS_SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
_env=$(set -o posix; export -p); [[ -f "$_PKG_ROOT/.env" ]] && source "$_PKG_ROOT/.env"; [[ -f "$_PKG_ROOT/../.env" ]] && source "$_PKG_ROOT/../.env"; eval "$_env"
# shellcheck source=/dev/null
source "$_OPS_SCRIPT_DIR/lib/network-config.sh"
METADATA_JSON="${METADATA_JSON:-$_PKG_ROOT/../metadata/networks.json}"

has_deployed_code() {
    local code
    code=$(cast code "$2" --rpc-url "$1") || return 1
    [[ "$code" != "0x" && -n "$code" ]]
}

has_provider_role() {
    local simple_acl provider_role
    simple_acl=$(cast call "$4" "getSimpleACL()(address)" --rpc-url "$3") || return 1
    [[ "$simple_acl" != "0x0000000000000000000000000000000000000000" ]] || return 1
    provider_role=$(cast keccak "$2") || return 1
    [[ "$(cast call "$simple_acl" "hasRole(bytes32,address)(bool)" "$provider_role" "$1" --rpc-url "$3")" == "true" ]]
}

rollout_forwarder() {
    local network=$1 contract=$2 resolver_key=$3 expected=$4 deployer_pk=$5
    local phase=${6:-${FORWARDER_PHASE:-all}}
    local rpc host verification_failed=0
    case "$phase" in
        all|deploy|verify|activate|register) ;;
        *) echo "Unknown forwarder phase: $phase (use all, deploy, verify, activate, register)" >&2; return 1 ;;
    esac
    # Normalize the existing nonempty SIMULATE convention for every child component.
    if [[ -n "${SIMULATE:-}" ]]; then export SIMULATE=1; fi
    rpc=$(get_rpc_url "$network") || return 1
    host=$(get_host "$network") || return 1
    if [[ ! "$host" =~ ^0x[a-fA-F0-9]{40}$ ]] || ! has_deployed_code "$rpc" "$host"; then
        echo "No deployed host for $network" >&2
        return 1
    fi
    echo "Forwarder rollout: $network $contract $expected (phase=$phase)"

    if [[ "$phase" == all || "$phase" == deploy ]]; then
        if has_deployed_code "$rpc" "$expected"; then
            echo "Deploy: bytecode already present at $expected"
        elif [[ -n "${SKIP_DEPLOY:-}" && "${SKIP_DEPLOY}" != 0 ]]; then
            echo "Deploy skipped; no bytecode at $expected" >&2
        else
            if [[ -z "$deployer_pk" ]]; then
                echo "The contract-specific deployer private key is required (no bytecode at $expected)" >&2
                return 1
            fi
            DETERMINISTIC_DEPLOYER_PK="$deployer_pk" EXPECTED_ADDRESS="$expected" SKIP_ADDRESS_CHECK=0 \
                "$_OPS_SCRIPT_DIR/deploy-deterministic-forwarder.sh" "$network" "$contract" || return 1
        fi
        if [[ -n "${SIMULATE:-}" ]] && ! has_deployed_code "$rpc" "$expected"; then
            echo "Simulation only: activation and registration require deployed bytecode; run those phases after deployment."
            return 0
        fi
    fi
    if ! has_deployed_code "$rpc" "$expected"; then
        echo "No deployed forwarder at $expected; run the deploy phase first" >&2
        return 1
    fi
    [[ "$phase" != deploy ]] || return 0

    if [[ "$phase" == all || "$phase" == verify ]]; then
        if [[ -n "${SKIP_VERIFY:-}" || -n "${SIMULATE:-}" ]]; then
            echo "Verify skipped (SKIP_VERIFY or SIMULATE)"
        elif ! "$_OPS_SCRIPT_DIR/verify-forwarder.sh" "$network" "$contract" "$expected"; then
            echo "Verification failed; activation/registration remain independently resumable" >&2
            verification_failed=1
        fi
    fi
    if [[ "$phase" == verify ]]; then return "$verification_failed"; fi

    if [[ "$phase" == all || "$phase" == activate ]]; then
        if [[ "$(cast call "$host" "isTrustedForwarder(address)(bool)" "$expected" --rpc-url "$rpc")" == true ]]; then
            echo "Activate: already trusted onchain"
        elif [[ -n "${SKIP_ACTIVATE:-}" ]]; then
            echo "Activate skipped (SKIP_ACTIVATE); registration still requires onchain activation"
        else
            "$_OPS_SCRIPT_DIR/activate-forwarder.sh" "$network" "$expected" || return 1
        fi
    fi
    [[ "$phase" != activate ]] || return 0

    if [[ "$phase" == register || ( "$phase" == all && -z "${SKIP_REGISTER:-}" ) ]]; then
        # register-forwarder repeats this live check independently, including for direct callers.
        if [[ "$(cast call "$host" "isTrustedForwarder(address)(bool)" "$expected" --rpc-url "$rpc")" != true ]]; then
            echo "Registration blocked: activation has not executed onchain. A Safe proposal is not execution." >&2
            echo "After governance execution, rerun this task with phase register (or rerun all)." >&2
            return 1
        fi
        "$_OPS_SCRIPT_DIR/register-forwarder.sh" "$network" "$resolver_key" "$expected" || return 1
    elif [[ "$phase" == all ]]; then
        echo "Register skipped (SKIP_REGISTER)"
    fi

    if [[ "$phase" == all && -z "${SKIP_GRANT_PROVIDER:-}" && -n "${CLEARMACRO_PROVIDER_GRANTEE:-}" ]]; then
        local provider_name=${CLEARMACRO_PROVIDER_NAME:-macros.superfluid.eth}
        if [[ -n "${SIMULATE:-}" ]]; then
            echo "Provider role grant skipped (SIMULATE)"
        elif has_provider_role "$CLEARMACRO_PROVIDER_GRANTEE" "$provider_name" "$rpc" "$host"; then
            echo "Provider role already granted"
        else
            "$_OPS_SCRIPT_DIR/grant-macro-provider-role.sh" "$network" "$CLEARMACRO_PROVIDER_GRANTEE" "$provider_name" || return 1
        fi
    fi
    echo "$expected"
    return "$verification_failed"
}
