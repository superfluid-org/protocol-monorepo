#!/usr/bin/env bash
# Compose deploy → verify → register → activate → grant provider role for a deterministic forwarder.
# Source from deploy-clearmacro-forwarder*.sh (do not execute directly).
#
# Flags (env): SKIP_DEPLOY, SKIP_VERIFY, SKIP_REGISTER, SKIP_ACTIVATE, SKIP_GRANT_PROVIDER, SIMULATE
#   CLEARMACRO_PROVIDER_GRANTEE — relay signer to grant macros.superfluid.eth role (required unless skip)
#   CLEARMACRO_PROVIDER_NAME      — default macros.superfluid.eth
#   WALLET_NAME                   — Foundry keystore for resolver/gov/cast steps (default sf-ops)
#   MACRO_PROVIDER_ADMIN_WALLET   — optional override for grant step only

_OPS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_PKG_ROOT="$(cd "$_OPS_SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
[[ -f "$_PKG_ROOT/.env" ]] && source "$_PKG_ROOT/.env"
# shellcheck source=/dev/null
[[ -f "$_PKG_ROOT/../.env" ]] && source "$_PKG_ROOT/../.env"

# shellcheck source=/dev/null
[[ -f "$_OPS_SCRIPT_DIR/lib/network-config.sh" ]] && source "$_OPS_SCRIPT_DIR/lib/network-config.sh"

METADATA_JSON="${METADATA_JSON:-$_PKG_ROOT/../metadata/networks.json}"

has_deployed_code() {
    local rpc_url=$1
    local addr=$2
    local code
    code=$(cast code "$addr" --rpc-url "$rpc_url" | tr -d '[:space:]')
    [[ "$code" != "0x" && -n "$code" ]]
}

lower_hex() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

has_true_result() {
    local out_trim out_lc
    out_trim=$(echo "$1" | tr -d '[:space:]')
    out_lc=$(echo "$out_trim" | tr '[:upper:]' '[:lower:]')
    [[ "$out_lc" == "true" ]] \
        || [[ "$out_lc" == *"true" ]] \
        || [[ "$out_trim" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]
}

rollout_step() {
    echo "======== $1 ========"
}

rollout_skip() {
    echo "→ skip: $*"
}

rollout_done() {
    echo "→ done"
}

rollout_status_label() {
    case "$1" in
        ok) echo "ok" ;;
        skip) echo "skip" ;;
        fail) echo "FAIL" ;;
        na) echo "n/a" ;;
        *) echo "$1" ;;
    esac
}

# Etherscan-compatible getabi: status 1 + non-empty ABI means verified on explorer.
contract_is_verified_on_explorer() {
    local network=$1
    local addr=$2
    local chain_id api_key url response status result

    addr=$(lower_hex "$addr")
    chain_id=$(get_chain_id "$network")

    if [[ "$network" == "scroll-sepolia" ]]; then
        api_key="${SCROLLSCAN_API_KEY:-}"
        [[ -z "$api_key" ]] && return 1
        url="https://sepolia.scrollscan.com/api?module=contract&action=getabi&address=${addr}&apikey=${api_key}"
    elif [[ "$network" == "scroll-mainnet" ]]; then
        api_key="${SCROLLSCAN_API_KEY:-}"
        [[ -z "$api_key" ]] && return 1
        url="https://scrollscan.com/api?module=contract&action=getabi&address=${addr}&apikey=${api_key}"
    elif [[ "$network" == "degenchain" ]]; then
        url="https://explorer.degen.tips/api?module=contract&action=getabi&address=${addr}"
        if [[ -n "${BLOCKSCOUT_API_KEY:-}" ]]; then
            url="${url}&apikey=${BLOCKSCOUT_API_KEY}"
        fi
    else
        api_key="${ETHERSCAN_API_V2_KEY:-}"
        [[ -z "$api_key" ]] && return 1
        url="https://api.etherscan.io/v2/api?chainid=${chain_id}&module=contract&action=getabi&address=${addr}&apikey=${api_key}"
    fi

    response=$(curl -sf "$url") || return 1
    status=$(echo "$response" | jq -r '.status // empty')
    result=$(echo "$response" | jq -r '.result // empty')
    [[ "$status" == "1" ]] \
        && [[ -n "$result" ]] \
        && [[ "$result" != "Contract source code not verified" ]]
}

has_provider_role() {
    local network=$1
    local grantee=$2
    local provider=$3
    local rpc_url=$4
    local host_addr=$5

    local simple_acl provider_role
    simple_acl=$(cast call "$host_addr" "getSimpleACL()(address)" --rpc-url "$rpc_url" | tr -d '[:space:]')
    if [[ "$simple_acl" == "0x0000000000000000000000000000000000000000" ]]; then
        return 1
    fi
    provider_role=$(cast keccak "$provider")
    has_true_result "$(cast call "$simple_acl" "hasRole(bytes32,address)(bool)" "$provider_role" "$grantee" --rpc-url "$rpc_url")"
}

rollout_forwarder() {
    local network=$1
    local contract=$2
    local resolver_key=$3
    local expected=$4
    local deployer_pk=$5

    local skip_register="${SKIP_REGISTER:-}"
    local skip_activate="${SKIP_ACTIVATE:-}"
    local skip_grant_provider="${SKIP_GRANT_PROVIDER:-}"
    local provider_grantee="${CLEARMACRO_PROVIDER_GRANTEE:-}"
    local provider_name="${CLEARMACRO_PROVIDER_NAME:-macros.superfluid.eth}"

    local contract_addr
    local rpc host resolver_address
    local st_deploy st_verify st_register st_activate st_grant

    rpc=$(get_rpc_url "$network") || exit 1
    host=$(get_host "$network") || exit 1
    resolver_address=$(jq -r '.[] | select(.name == "'"$network"'") | .contractsV1.resolver' "$METADATA_JSON") || exit 1
    resolver_address=$(echo "$resolver_address" | tr -d '[:space:]')
    if [[ -z "$resolver_address" || "$resolver_address" == "null" ]]; then
        resolver_address=""
    fi

    echo "Rollout on $network ($contract) → $expected"

    # --- 1/5 Deploy ---
    rollout_step "1/5 Deploy"
    if [[ "${SKIP_DEPLOY:-0}" -eq 1 ]]; then
        contract_addr="$expected"
        rollout_skip "SKIP_DEPLOY=1"
        st_deploy=skip
    elif has_deployed_code "$rpc" "$expected"; then
        contract_addr="$expected"
        rollout_skip "bytecode at $contract_addr"
        st_deploy=skip
    else
        if [[ -z "$deployer_pk" ]]; then
            echo "→ FAIL: deployer private key required (no bytecode at $expected)" >&2
            return 1
        fi
        export DETERMINISTIC_DEPLOYER_PK="$deployer_pk"
        export EXPECTED_ADDRESS="$expected"
        local tmpfile
        tmpfile=$(mktemp)
        if "$_OPS_SCRIPT_DIR/deploy-deterministic-forwarder.sh" "$network" "$contract" | tee "$tmpfile"; then
            contract_addr=$(tail -n 1 "$tmpfile")
            rollout_done
            st_deploy=ok
        else
            rm -f "$tmpfile"
            echo "→ FAIL: deploy script failed" >&2
            return 1
        fi
        rm -f "$tmpfile"
    fi
    echo "Forwarder: $contract_addr"

    # --- 2/5 Verify ---
    rollout_step "2/5 Verify"
    if [[ -n "${SKIP_VERIFY:-}" || -n "${SIMULATE:-}" ]]; then
        rollout_skip "SKIP_VERIFY or SIMULATE"
        st_verify=na
    elif contract_is_verified_on_explorer "$network" "$contract_addr"; then
        rollout_skip "already verified on explorer"
        st_verify=skip
    else
        if "$_OPS_SCRIPT_DIR/verify-forwarder.sh" "$network" "$contract" "$contract_addr"; then
            rollout_done
            st_verify=ok
        else
            rollout_skip "verification failed (non-fatal)"
            st_verify=fail
        fi
    fi

    # --- 3/5 Register ---
    rollout_step "3/5 Register (resolver)"
    if [[ -n "$skip_register" ]]; then
        rollout_skip "SKIP_REGISTER"
        st_register=na
    elif [[ -n "$resolver_address" ]]; then
        local resolved
        resolved=$(cast call "$resolver_address" "get(string)(address)" "$resolver_key" --rpc-url "$rpc" | tr -d '[:space:]')
        if [[ "$(lower_hex "$resolved")" == "$(lower_hex "$contract_addr")" ]]; then
            rollout_skip "resolver $resolver_key → $contract_addr"
            st_register=skip
        else
            export ALLOW_UPDATE=1
            if "$_OPS_SCRIPT_DIR/register-forwarder.sh" "$network" "$resolver_key" "$contract_addr"; then
                rollout_done
                st_register=ok
            else
                echo "→ FAIL: register failed" >&2
                return 1
            fi
        fi
    else
        export ALLOW_UPDATE=1
        if "$_OPS_SCRIPT_DIR/register-forwarder.sh" "$network" "$resolver_key" "$contract_addr"; then
            rollout_done
            st_register=ok
        else
            echo "→ FAIL: register failed" >&2
            return 1
        fi
    fi

    # --- 4/5 Activate ---
    rollout_step "4/5 Activate (gov)"
    if [[ -n "$skip_activate" ]]; then
        rollout_skip "SKIP_ACTIVATE"
        st_activate=na
    elif [[ -n "$host" ]]; then
        local trusted
        trusted=$(cast call "$host" "isTrustedForwarder(address)(bool)" "$contract_addr" --rpc-url "$rpc" | tr -d '[:space:]')
        if [[ "$trusted" == "true" ]]; then
            rollout_skip "host.isTrustedForwarder($contract_addr)"
            st_activate=skip
        else
            if "$_OPS_SCRIPT_DIR/activate-forwarder.sh" "$network" "$contract_addr"; then
                rollout_done
                st_activate=ok
            else
                echo "→ FAIL: activate failed" >&2
                return 1
            fi
        fi
    else
        if "$_OPS_SCRIPT_DIR/activate-forwarder.sh" "$network" "$contract_addr"; then
            rollout_done
            st_activate=ok
        else
            echo "→ FAIL: activate failed" >&2
            return 1
        fi
    fi

    # --- 5/5 Grant ---
    rollout_step "5/5 Grant provider role (SimpleACL)"
    if [[ -n "$skip_grant_provider" ]]; then
        rollout_skip "SKIP_GRANT_PROVIDER"
        st_grant=na
    elif [[ -z "$provider_grantee" ]]; then
        rollout_skip "CLEARMACRO_PROVIDER_GRANTEE not set"
        st_grant=na
    elif has_provider_role "$network" "$provider_grantee" "$provider_name" "$rpc" "$host"; then
        rollout_skip "$provider_grantee already has role for $provider_name"
        st_grant=skip
    else
        if "$_OPS_SCRIPT_DIR/grant-macro-provider-role.sh" "$network" "$provider_grantee" "$provider_name"; then
            rollout_done
            st_grant=ok
        else
            echo "→ FAIL: grant provider role failed" >&2
            return 1
        fi
    fi

    echo ""
    echo "Rollout complete on $network ($contract_addr): deploy=$(rollout_status_label "$st_deploy") verify=$(rollout_status_label "$st_verify") register=$(rollout_status_label "$st_register") activate=$(rollout_status_label "$st_activate") grant=$(rollout_status_label "$st_grant")"
    echo "$contract_addr"
}
