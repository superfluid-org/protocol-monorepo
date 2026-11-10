#!/usr/bin/env bash
set -euo pipefail

# JSON plan: bash new-ops-scripts/verify-framework.sh eth-sepolia --plan
# The Node entry point handles read-only RPC discovery and forge verification.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$SCRIPT_DIR/verify-framework.js" "$@"
