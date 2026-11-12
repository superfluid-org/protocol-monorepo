#!/usr/bin/env bash
set -eu
set -o pipefail

# Register only after governance activation has actually executed onchain.
# Usage: register-forwarder.sh <network> <resolverKey> <forwarderAddress>
# ALLOW_UPDATE=1 explicitly overwrites a resolver entry; --broadcast enables side effects.
# A successful Safe proposal submission is not proof of activation.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/ops.sh"
parse_ops_args "$@"
require_args 3 'register-forwarder.sh NETWORK KEY FORWARDER'
FLAGS=()
(( ! BROADCAST )) || FLAGS+=(--broadcast)
(( ! RESUME )) || FLAGS+=(--resume)
set -- "${OPS_ARGS[@]}"
network="${1:?Usage: $0 <network> <resolverKey> <forwarderAddress>}"
resolver_key="${2:?Usage: $0 <network> <resolverKey> <forwarderAddress>}"
forwarder="${3:?Usage: $0 <network> <resolverKey> <forwarderAddress>}"
require_address FORWARDER "$forwarder"
rpc=$(get_rpc_url "$network")
host=${HOST_ADDRESS:-$(get_host "$network")}
export HOST_ADDRESS=$host
require_address HOST_ADDRESS "$host"
for address in "$host" "$forwarder"; do
    code=$(cast code "$address" --rpc-url "$rpc")
    if [[ -z "$code" || "$code" == 0x ]]; then
        echo "Registration blocked: no deployed code at $address" >&2
        exit 1
    fi
done
trusted=$(cast call "$host" "isTrustedForwarder(address)(bool)" "$forwarder" --rpc-url "$rpc")
if [[ "$trusted" != true ]]; then
    echo "Registration blocked: $forwarder is not trusted by host $host onchain." >&2
    echo "Execute the activation governance transaction first, then rerun register. A Safe proposal is not execution." >&2
    exit 1
fi
resolver=${RESOLVER_ADDRESS:-$(get_resolver "$network")}
export RESOLVER_ADDRESS=$resolver
require_address RESOLVER_ADDRESS "$resolver"
resolved=$(cast call "$resolver" "get(string)(address)" "$resolver_key" --rpc-url "$rpc")
if [[ "${resolved,,}" == "${forwarder,,}" ]]; then
    echo "Already registered: $resolver_key → $forwarder"
    exit 0
fi
exec "$SCRIPT_DIR/resolver-set-key.sh" "$network" "$resolver_key" "$forwarder" "${FLAGS[@]}"
