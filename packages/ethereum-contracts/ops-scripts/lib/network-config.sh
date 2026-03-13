# Network config helpers for ops scripts.
# Source this file, then use get_rpc_url, get_host, get_chain_id.
# Prerequisites: METADATA_JSON must be set (path to networks.json).
#
# RPC priority: RPC_URL | PROVIDER_URL_OVERRIDE | PROVIDER_URL_TEMPLATE | metadata publicRPCs[0]

get_rpc_url() {
    local network=$1
    if [[ -n "${RPC_URL:-}" ]]; then
        echo "$RPC_URL"
        return
    fi
    if [[ -n "${PROVIDER_URL_OVERRIDE:-}" ]]; then
        echo "$PROVIDER_URL_OVERRIDE"
        return
    fi
    if [[ -n "${PROVIDER_URL_TEMPLATE:-}" ]]; then
        if [[ "$PROVIDER_URL_TEMPLATE" != *"{{NETWORK}}"* ]]; then
            echo "Error: PROVIDER_URL_TEMPLATE must contain {{NETWORK}}" >&2
            return 1
        fi
        echo "$PROVIDER_URL_TEMPLATE" | sed "s/{{NETWORK}}/$network/"
        return
    fi
    # Fallback: metadata publicRPCs[0]
    local rpc
    rpc=$(jq -r '.[] | select(.name == "'"$network"'") | .publicRPCs[0]' "${METADATA_JSON:?METADATA_JSON not set}")
    if [[ -z "$rpc" || "$rpc" == "null" ]]; then
        echo "No RPC URL found for network $network" >&2
        return 1
    fi
    echo "$rpc"
}

get_host() {
    local network=$1
    jq -r '.[] | select(.name == "'"$network"'") | .contractsV1.host' "${METADATA_JSON:?METADATA_JSON not set}"
}

get_chain_id() {
    local network=$1
    jq -r '.[] | select(.name == "'"$network"'") | .chainId' "${METADATA_JSON:?METADATA_JSON not set}"
}
