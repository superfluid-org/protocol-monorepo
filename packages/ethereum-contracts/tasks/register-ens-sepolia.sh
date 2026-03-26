#!/usr/bin/env bash
# Register an ENS .eth domain on Sepolia using Foundry wallet.
# Uses commit-reveal: commit -> wait ~60s -> register.
#
# Usage: ./tasks/register-ens-sepolia.sh [label]
#   label: ENS label (default: sftest) -> registers label.eth
#
# Requires: --account gh-agent-quick (or set FOUNDRY_ACCOUNT)
#   Foundry will prompt for keystore password when needed.
#
# RPC from .env (same as truffle): explicit ETH_SEPOLIA_PROVIDER_URL, SEPOLIA_PROVIDER_URL,
#   DEFAULT_PROVIDER_URL; or PROVIDER_URL_OVERRIDE; or PROVIDER_URL_TEMPLATE with {{NETWORK}}.
#   Override with SEPOLIA_RPC_URL.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETH_CONTRACTS="$(cd "$SCRIPT_DIR/.." && pwd)"
MONOREPO="$(cd "$ETH_CONTRACTS/../.." && pwd)"
LABEL="${1:-sftest}"

# shellcheck source=/dev/null
[[ -f "$ETH_CONTRACTS/.env" ]] && source "$ETH_CONTRACTS/.env"

RPC="${SEPOLIA_RPC_URL:-${ETH_SEPOLIA_PROVIDER_URL:-${SEPOLIA_PROVIDER_URL:-${DEFAULT_PROVIDER_URL:-${PROVIDER_URL_OVERRIDE:-}}}}}"
if [[ -z "${RPC:-}" && -n "${PROVIDER_URL_TEMPLATE:-}" && "$PROVIDER_URL_TEMPLATE" == *"{{NETWORK}}"* ]]; then
    RPC="${PROVIDER_URL_TEMPLATE/\{\{NETWORK\}\}/eth-sepolia}"
fi
RPC="${RPC:-https://rpc.sepolia.org}"
ACCOUNT="${FOUNDRY_ACCOUNT:-gh-agent-quick}"
DEFAULT_SENDER="0xd15d5d0f5b1b56a4daef75cfe108cb825e97d015"

# The keystore account signs the tx; default sender is the known gh-agent-quick address.
SENDER="${SENDER:-$DEFAULT_SENDER}"
ENS_SECRET="${ENS_SECRET:-$(python3 - <<'PY'
import secrets
print(secrets.randbits(256))
PY
)}"

echo "Registering $LABEL.eth on Sepolia"
echo "  Account: $ACCOUNT ($SENDER)"
echo "  RPC: $RPC"
echo "  ENS_SECRET: $ENS_SECRET"
echo ""

cd "$MONOREPO"

echo "=== Step 1: Commit ==="
ENS_LABEL="$LABEL" ENS_STEP=commit ENS_SECRET="$ENS_SECRET" SENDER="$SENDER" forge script \
    packages/ethereum-contracts/script/RegisterEnsSepolia.s.sol:RegisterEnsSepolia \
    --account "$ACCOUNT" \
    --sender "$SENDER" \
    --rpc-url "$RPC" \
    --broadcast \
    -vvv

echo ""
echo "Waiting 65 seconds (minCommitmentAge)..."
sleep 65

echo ""
echo "=== Step 2: Register ==="
ENS_LABEL="$LABEL" ENS_STEP=register ENS_SECRET="$ENS_SECRET" SENDER="$SENDER" forge script \
    packages/ethereum-contracts/script/RegisterEnsSepolia.s.sol:RegisterEnsSepolia \
    --account "$ACCOUNT" \
    --sender "$SENDER" \
    --rpc-url "$RPC" \
    --broadcast \
    -vvv

echo ""
echo "Done. $LABEL.eth registered to $SENDER"
