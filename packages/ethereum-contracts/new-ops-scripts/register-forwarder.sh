#!/usr/bin/env bash
set -eu
set -o pipefail

# Step 3 — Register forwarder address in the resolver.
#
# Usage:
#   new-ops-scripts/register-forwarder.sh <network> <resolverKey> <forwarderAddress>
#
# Env: WALLET_NAME, ALLOW_UPDATE=1, SIMULATE=1, SAFE_* (see resolver-set-key.sh)
#
# Mainnet: run after activate-forwarder governance tx is executed (or use SKIP_REGISTER on rollout).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/resolver-set-key.sh" "$@"
