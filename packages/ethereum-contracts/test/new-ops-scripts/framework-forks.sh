#!/usr/bin/env bash
# Read-only remote forks. Forge tests mutate only their in-memory fork, never the RPC.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../new-ops-scripts/lib/ops.sh"
IFS=',' read -ra NETWORKS <<< "${FRAMEWORK_FORK_NETWORKS:-optimism-sepolia,eth-mainnet,optimism-mainnet,arc-mainnet}"
for network in "${NETWORKS[@]}"; do
    unset RPC_URL HOST_ADDRESS RESOLVER_ADDRESS
    export PROVIDER_URL_TEMPLATE=${PROVIDER_URL_TEMPLATE:-https://\{\{NETWORK\}\}.rpc.x.superfluid.dev}
    init_network "$network"
    FORK_RPC_URL=$RPC_URL FORK_HOST=$HOST_ADDRESS FORK_RESOLVER=$RESOLVER_ADDRESS \
        forge test --match-contract FrameworkForkTest -vv
 done
