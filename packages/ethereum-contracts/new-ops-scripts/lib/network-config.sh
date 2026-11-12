# Shared, chain-bound metadata and RPC lookup for all operator commands.
# Prerequisite: METADATA_JSON points to networks.json.
get_chain_id() {
    local id
    id=$(jq -er --arg network "$1" '.[] | select(.name == $network) | .chainId' "${METADATA_JSON:?METADATA_JSON not set}") || {
        echo "Unknown network $1: add its name, chainId and publicRPCs to METADATA_JSON first (and a reviewed ChainPolicy entry for fresh deployments)." >&2
        return 1
    }
    printf '%s\n' "$id"
}

get_rpc_url() {
    local network=$1 expected rpc actual
    expected=$(get_chain_id "$network") || return 1
    if [[ -n "${RPC_URL:-}" ]]; then
        rpc=$RPC_URL
    elif [[ -n "${PROVIDER_URL_OVERRIDE:-}" ]]; then
        rpc=$PROVIDER_URL_OVERRIDE
    elif [[ -n "${PROVIDER_URL_TEMPLATE:-}" ]]; then
        [[ "$PROVIDER_URL_TEMPLATE" == *'{{NETWORK}}'* ]] || {
            echo 'PROVIDER_URL_TEMPLATE must contain {{NETWORK}}' >&2; return 1;
        }
        rpc=${PROVIDER_URL_TEMPLATE//\{\{NETWORK\}\}/$network}
    else
        rpc=$(jq -er --arg network "$network" '.[] | select(.name == $network) | .publicRPCs[0] // empty' "$METADATA_JSON") || {
            echo "No RPC URL found for network $network" >&2; return 1;
        }
    fi
    actual=$(cast chain-id --rpc-url "$rpc") || return 1
    [[ "$actual" == "$expected" ]] || {
        echo "RPC chain $actual differs from NETWORK $network chain $expected" >&2; return 1;
    }
    printf '%s\n' "$rpc"
}

get_host() {
    jq -r --arg network "$1" '.[] | select(.name == $network) | .contractsV1.host // empty' "${METADATA_JSON:?METADATA_JSON not set}"
}

get_resolver() {
    jq -r --arg network "$1" '.[] | select(.name == $network) | .contractsV1.resolver // empty' "${METADATA_JSON:?METADATA_JSON not set}"
}

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/keystore-env.sh"
