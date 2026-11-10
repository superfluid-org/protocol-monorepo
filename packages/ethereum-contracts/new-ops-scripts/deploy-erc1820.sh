#!/usr/bin/env bash
# EIP-1820 canonical presigned transaction. Default prints the plan, sends nothing.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PKG_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
METADATA_JSON=${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/network-config.sh"
NETWORK=${1:?Usage: deploy-erc1820.sh NETWORK [--broadcast]}
MODE=${2:-}
[[ -z "$MODE" || "$MODE" == --broadcast ]] || { echo 'Only --broadcast is supported' >&2; exit 1; }
RPC_URL=$(get_rpc_url "$NETWORK")
REGISTRY=0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24
SIGNER=0xa990077c3205cbDf861e17Fa532eeB069cE9fF96
if [[ $(cast code "$REGISTRY" --rpc-url "$RPC_URL") != 0x ]]; then
    echo "ERC1820 already deployed at $REGISTRY"; exit 0
fi
cd "$PKG_ROOT"
RAW=$(node - <<'JS'
const {utils, BigNumber} = require('ethers');
const artifact = require('./dev-scripts/artifacts/ERC1820Registry.json');
const raw = utils.serializeTransaction({nonce: 0, gasPrice: BigNumber.from('100000000000'),
    gasLimit: 800000, value: 0, data: '0x' + artifact.bin}, {v: 27,
    r: '0x1820182018201820182018201820182018201820182018201820182018201820',
    s: '0x1820182018201820182018201820182018201820182018201820182018201820'});
const tx = utils.parseTransaction(raw);
if (tx.from.toLowerCase() !== '0xa990077c3205cbdf861e17fa532eeb069ce9ff96' ||
    utils.getContractAddress(tx).toLowerCase() !== '0x1820a4b7618bde71dce8cdc73aab6c95905fad24') throw Error('Noncanonical ERC1820 transaction');
console.log(raw);
JS
)
echo "Plan: fund canonical signer $SIGNER up to 0.1 ETH, then publish EIP-1820 presigned transaction ($REGISTRY)."
if [[ -z "$MODE" ]]; then echo "Simulation only: no funding or publishing. Raw transaction: $RAW"; exit 0; fi
BALANCE=$(cast balance "$SIGNER" --rpc-url "$RPC_URL")
NEEDED=$(node -e 'console.log((100000000000000000n-BigInt(process.argv[1])).toString())' "$BALANCE")
AUTH=(--account "${WALLET_NAME:-sf-ops}")
if [[ -n "${PRIVATE_KEY:-}" ]]; then AUTH=(--private-key "$PRIVATE_KEY"); fi
if [[ "$NEEDED" != -* && "$NEEDED" != 0 ]]; then
    with_keystore_password cast send "$SIGNER" --value "$NEEDED" --rpc-url "$RPC_URL" "${AUTH[@]}"
fi
cast publish "$RAW" --rpc-url "$RPC_URL"
[[ $(cast code "$REGISTRY" --rpc-url "$RPC_URL") != 0x ]] || { echo 'ERC1820 deployment failed' >&2; exit 1; }
