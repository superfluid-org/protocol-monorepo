# Choose a real authorized sender for eth_call-only Foundry simulation, without keys/signatures.
# EOA admin: itself; legacy multisig: first owner; Safe: arbitrary sender (payload only).
get_simulation_sender() {
    local admin=$1 rpc=$2 owners
    if [[ -n "${SIMULATION_SENDER:-}" ]]; then printf '%s\n' "$SIMULATION_SENDER"; return; fi
    if [[ $(cast code "$admin" --rpc-url "$rpc") == 0x ]]; then printf '%s\n' "$admin"; return; fi
    if cast call "$admin" 'required()(uint256)' --rpc-url "$rpc" >/dev/null 2>&1; then
        owners=$(cast call "$admin" 'getOwners()(address[])' --rpc-url "$rpc" --json) || return 1
        jq -er '.[0][0]' <<< "$owners"
    else
        printf '%s\n' 0x0000000000000000000000000000000000000001
    fi
}
