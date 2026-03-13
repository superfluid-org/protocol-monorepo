# Shared Safe transaction payload handling for ops scripts.
# Source this file, then call:
#   handle_safe_tx_payloads <script_log> <script_dir> <rpc_url>
#
# Uses env vars:
#   SIMULATE, SAFE_ORIGIN, SAFE_PROPOSER_PK, SAFE_API_KEY

handle_safe_tx_payloads() {
    local script_log=$1
    local script_dir=$2
    local rpc_url=$3
    local safe_tx_lines

    safe_tx_lines=$(grep "<<<SAFE_TX:v1>>>" "$script_log" || true)
    if [[ -z "$safe_tx_lines" ]]; then
        return 0
    fi

    echo ""
    echo "Captured Safe transaction payloads:"
    while IFS= read -r safe_line; do
        local payload safe_address to_address value_hex data_hex action_type origin_env
        payload=${safe_line#*<<<SAFE_TX:v1>>>}
        safe_address=$(printf '%s' "$payload" | jq -r '.safeAddress')
        to_address=$(printf '%s' "$payload" | jq -r '.to')
        value_hex=$(printf '%s' "$payload" | jq -r '.value // empty')
        data_hex=$(printf '%s' "$payload" | jq -r '.data')
        action_type=$(printf '%s' "$payload" | jq -r '.actionType')

        echo "  Action Type: $action_type"
        echo "    Safe: $safe_address"
        echo "    To: $to_address"
        if [[ -n "$value_hex" ]]; then
            echo "    Value: $value_hex"
        fi
        echo "    Data: $data_hex"

        if [[ -z "${SIMULATE:-}" ]] && [[ -f "$script_dir/propose-safe-tx.ts" ]]; then
            origin_env="${SAFE_ORIGIN:-$action_type}"
            echo "    Proposing Safe transaction via propose-safe-tx.ts"
            SAFE_ADDRESS="$safe_address" \
            SAFE_TX_PAYLOAD="$payload" \
            SAFE_ORIGIN="$origin_env" \
            RPC_URL="$rpc_url" \
            SAFE_PROPOSER_PK="${SAFE_PROPOSER_PK:-}" \
            SAFE_API_KEY="${SAFE_API_KEY:-}" \
            npx ts-node "$script_dir/propose-safe-tx.ts"
        fi
    done <<< "$safe_tx_lines"
}
