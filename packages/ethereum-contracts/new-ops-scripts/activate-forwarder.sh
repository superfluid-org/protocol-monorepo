#!/usr/bin/env bash
set -eu
set -o pipefail

# Step 4 — Governance: enable trusted forwarder for all Super Tokens.
#
# Usage:
#   new-ops-scripts/activate-forwarder.sh <network> <forwarderAddress>
#
# Env: WALLET_NAME, SIMULATE=1, SAFE_* (see gov-action.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

network="${1:?Usage: $0 <network> <forwarderAddress>}"
forwarder="${2:?Usage: $0 <network> <forwarderAddress>}"
zero=0x0000000000000000000000000000000000000000

exec "$SCRIPT_DIR/gov-action.sh" "$network" enableTrustedForwarder "$zero" "$forwarder"
