#!/usr/bin/env bash
set -eu
set -o pipefail

# Register only after governance activation has actually executed onchain.
# Usage: register-forwarder.sh <network> <resolverKey> <forwarderAddress>
# Env: WALLET_NAME, ALLOW_UPDATE=1 (explicit overwrite), SIMULATE=1, SAFE_*.
# A successful Safe proposal submission is not proof of activation.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"
# shellcheck source=/dev/null
_env=$(set -o posix; export -p); [[ -f "$PKG_ROOT/.env" ]] && source "$PKG_ROOT/.env"; [[ -f "$PKG_ROOT/../.env" ]] && source "$PKG_ROOT/../.env"; eval "$_env"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/network-config.sh"
network="${1:?Usage: $0 <network> <resolverKey> <forwarderAddress>}"
resolver_key="${2:?Usage: $0 <network> <resolverKey> <forwarderAddress>}"
forwarder="${3:?Usage: $0 <network> <resolverKey> <forwarderAddress>}"
[[ $# -eq 3 && "$forwarder" =~ ^0x[a-fA-F0-9]{40}$ ]] || { echo "Invalid forwarder arguments" >&2; exit 1; }
rpc=$(get_rpc_url "$network")
host=${HOST_ADDRESS:-$(get_host "$network")}
export HOST_ADDRESS=$host
[[ "$host" =~ ^0x[a-fA-F0-9]{40}$ ]] || { echo "No host for $network" >&2; exit 1; }
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
resolver=${RESOLVER_ADDRESS:-$(jq -r --arg network "$network" '.[] | select(.name == $network) | .contractsV1.resolver' "$METADATA_JSON")}
export RESOLVER_ADDRESS=$resolver
[[ "$resolver" =~ ^0x[a-fA-F0-9]{40}$ ]] || { echo "No resolver for $network" >&2; exit 1; }
resolved=$(cast call "$resolver" "get(string)(address)" "$resolver_key" --rpc-url "$rpc")
if [[ "${resolved,,}" == "${forwarder,,}" ]]; then
    echo "Already registered: $resolver_key → $forwarder"
    exit 0
fi
exec "$SCRIPT_DIR/resolver-set-key.sh" "$network" "$resolver_key" "$forwarder"
