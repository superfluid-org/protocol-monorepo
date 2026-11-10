#!/usr/bin/env bash
set -eu
set -o pipefail

# Usage: tasks/deploy-macro-forwarder.sh <network> [all|deploy|verify|activate|register]
# Deploys BlindMacroForwarder, NOT ClearMacroForwarder.
# MACROFWD_DEPLOYER_PK: vanity deployer; WALLET_NAME: funder/admin keystore.
# SIMULATE=1 never funds, broadcasts, or proposes. SKIP_VERIFY skips explorer verification.
# Activation may only propose a Safe transaction. Execute it before rerunning register.
# ALLOW_UPDATE=1 is required to deliberately replace a different resolver value.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../new-ops-scripts/lib/rollout-forwarder.sh"
network="${1:?Usage: $0 <network> [all|deploy|verify|activate|register]}"
[[ $# -le 2 ]] || { echo "Too many arguments" >&2; exit 1; }
SKIP_GRANT_PROVIDER=1
rollout_forwarder "$network" BlindMacroForwarder BlindMacroForwarder \
    0xFD0268E33111565dE546af2675351A4b1587F89F "${MACROFWD_DEPLOYER_PK:-}" "${2:-all}"
