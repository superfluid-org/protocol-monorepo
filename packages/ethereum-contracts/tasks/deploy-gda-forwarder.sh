#!/usr/bin/env bash
set -eu
set -o pipefail

# Usage: tasks/deploy-gda-forwarder.sh <network> [all|deploy|verify|activate|register]
# GDAFWD_DEPLOYER_PK: vanity deployer; WALLET_NAME: funder/admin keystore.
# SIMULATE=1 never funds, broadcasts, or proposes. SKIP_VERIFY skips explorer verification.
# Activation may only propose a Safe transaction. Execute it before rerunning register.
# ALLOW_UPDATE=1 is required to deliberately replace a different resolver value.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../new-ops-scripts/lib/rollout-forwarder.sh"
network="${1:?Usage: $0 <network> [all|deploy|verify|activate|register]}"
[[ $# -le 2 ]] || { echo "Too many arguments" >&2; exit 1; }
export SKIP_GRANT_PROVIDER=1
rollout_forwarder "$network" GDAv1Forwarder GDAv1Forwarder \
    0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08 "${GDAFWD_DEPLOYER_PK:-}" "${2:-all}"
