#!/usr/bin/env bash
# Source from forwarder tasks. Deploy → verify → activate → confirm execution → register.
# Optional sixth argument: all (default), deploy, verify, activate, register.
# Rerun register after a pending governance transaction executes; a proposal is not activation.
# Existing ClearMacro callers may additionally grant a provider role after registration.
# Sourced by deploy-forwarder.sh after the common ops prelude.
_OPS_SCRIPT_DIR=$OPS_DIR

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
    local phase=${6:-all}
    local rpc host verification_failed=0
    case "$phase" in
        all|deploy|verify|activate|register) ;;
        *) echo "Unknown forwarder phase: $phase (use all, deploy, verify, activate, register)" >&2; return 1 ;;
    esac
    local flags=()
    (( ! BROADCAST )) || flags+=(--broadcast)
    init_network "$network" || return 1
    rpc=$RPC_URL
    host=$HOST_ADDRESS
    if ! require_address HOST_ADDRESS "$host" || ! has_deployed_code "$rpc" "$host"; then
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
                "$_OPS_SCRIPT_DIR/deploy-deterministic-forwarder.sh" "$network" "$contract" "${flags[@]}" || return 1
        fi
        if (( ! BROADCAST )) && ! has_deployed_code "$rpc" "$expected"; then
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
        if (( ! BROADCAST )) || [[ -n "${SKIP_VERIFY:-}" ]]; then
            echo 'Verify skipped (simulation or SKIP_VERIFY)'
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
            "$_OPS_SCRIPT_DIR/activate-forwarder.sh" "$network" "$expected" "${flags[@]}" || return 1
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
        "$_OPS_SCRIPT_DIR/register-forwarder.sh" "$network" "$resolver_key" "$expected" "${flags[@]}" || return 1
    elif [[ "$phase" == all ]]; then
        echo "Register skipped (SKIP_REGISTER)"
    fi

    if [[ "$phase" == all && -z "${SKIP_GRANT_PROVIDER:-}" && -n "${CLEARMACRO_PROVIDER_GRANTEE:-}" ]]; then
        local provider_name=${CLEARMACRO_PROVIDER_NAME:-macros.superfluid.eth}
        if has_provider_role "$CLEARMACRO_PROVIDER_GRANTEE" "$provider_name" "$rpc" "$host"; then
            echo "Provider role already granted"
        else
            WALLET_NAME=${MACRO_PROVIDER_ADMIN_WALLET:-${WALLET_NAME:-sf-ops}} \
                "$_OPS_SCRIPT_DIR/acl-grant-role.sh" "$network" "$provider_name" "$CLEARMACRO_PROVIDER_GRANTEE" "${flags[@]}" || return 1
        fi
    fi
    echo "$expected"
    return "$verification_failed"
}
