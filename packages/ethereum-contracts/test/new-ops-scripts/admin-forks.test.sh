#!/usr/bin/env bash
# Start two LOCAL anvil forks first, then MAINNET_FORK_RPC=... TESTNET_FORK_RPC=... bash this file.
# All sends below impersonate accounts on local forks. Never accepts a remote endpoint.
set -euo pipefail
cd "$(dirname "$0")/../.."
MAINNET_FORK_RPC=${MAINNET_FORK_RPC:-http://127.0.0.1:18548}
TESTNET_FORK_RPC=${TESTNET_FORK_RPC:-http://127.0.0.1:18549}
for rpc in "$MAINNET_FORK_RPC" "$TESTNET_FORK_RPC"; do
    [[ "$rpc" =~ ^http://(127\.0\.0\.1|localhost):[0-9]+/?$ ]] || { echo 'Only localhost anvil endpoints accepted' >&2; exit 1; }
    cast rpc web3_clientVersion --rpc-url "$rpc" | jq -e 'test("anvil"; "i")'
done
ZERO=0x0000000000000000000000000000000000000000
ROLE=0x0000000000000000000000000000000000000000000000000000000000000000
RESOLVER=0xeE4cD028f5fdaAdeA99f8fc38e8bA8A57c90Be53
MULTI=0xae09720B8E27CfC171d07baEb1b6eF97030C3D52
OWNER=0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015
TOKEN=$(cast call "$RESOLVER" 'get(string)(address)' supertokens.v1.ETHx --rpc-url "$MAINNET_FORK_RPC")
SYMBOL="OPS_MIGRATION_FORK_TEST_$(date +%s)"
KEY="supertokens.v1.$SYMBOL"
if RPC_URL=$MAINNET_FORK_RPC SIMULATE=1 bash new-ops-scripts/register-forwarder.sh eth-mainnet "$KEY" "$RESOLVER"; then
    echo 'ERROR: untrusted contract was published as a forwarder' >&2; exit 1
fi
[[ $(cast call "$RESOLVER" 'get(string)(address)' "$KEY" --rpc-url "$MAINNET_FORK_RPC") == "$ZERO" ]]
RPC_URL=$MAINNET_FORK_RPC SIMULATE=1 RELEASE_VERSION=v1 bash new-ops-scripts/resolver-token.sh eth-mainnet list "$TOKEN" "$SYMBOL"
[[ $(cast call "$RESOLVER" 'get(string)(address)' "$KEY" --rpc-url "$MAINNET_FORK_RPC") == "$ZERO" ]]
INPUT=$(jq -er --arg to "${MULTI,,}" '.transactions[] | select((.transaction.to | ascii_downcase) == $to) | .transaction.input' broadcast/ResolverSetKey.s.sol/1/dry-run/run-latest.json)
EXPECTED_SET=$(cast calldata 'set(string,address)' "$KEY" "$TOKEN")
EXPECTED_SUBMIT=$(cast calldata 'submitTransaction(address,uint256,bytes)' "$RESOLVER" 0 "$EXPECTED_SET")
[[ "${INPUT,,}" == "${EXPECTED_SUBMIT,,}" ]]
cast decode-calldata 'submitTransaction(address,uint256,bytes)' "$INPUT"
cast decode-calldata 'set(string,address)' "$EXPECTED_SET"
cast rpc anvil_impersonateAccount "$OWNER" --rpc-url "$MAINNET_FORK_RPC"
cast rpc anvil_setBalance "$OWNER" 0x56BC75E2D63100000 --rpc-url "$MAINNET_FORK_RPC"
cast send "$MULTI" --data "$INPUT" --from "$OWNER" --unlocked --rpc-url "$MAINNET_FORK_RPC" --json
[[ $(cast call "$RESOLVER" 'get(string)(address)' "$KEY" --rpc-url "$MAINNET_FORK_RPC") == "$TOKEN" ]]
if RPC_URL=$MAINNET_FORK_RPC SIMULATE=1 RELEASE_VERSION=v1 bash new-ops-scripts/resolver-token.sh eth-mainnet list "$TOKEN" "$SYMBOL"; then
    echo 'ERROR: occupied resolver key was not rejected' >&2; exit 1
fi
RPC_URL=$MAINNET_FORK_RPC SIMULATE=1 RELEASE_VERSION=v1 ALLOW_UPDATE=1 bash new-ops-scripts/resolver-token.sh eth-mainnet list "$TOKEN" "$SYMBOL"
# Governance is Safe on mainnet: assert real payload target/calldata and no state change.
RPC_URL=$MAINNET_FORK_RPC SIMULATE=1 bash new-ops-scripts/gov-action.sh eth-mainnet setTokenMinimumDeposit "$TOKEN" 42
# Testnet EOA paths: simulate first, execute generated calldata locally, then read back state.
RESOLVER=0x6813edE4E78ecb830d380d0F7F684c12aAc95F02
RPC_URL=$TESTNET_FORK_RPC SIMULATE=1 bash new-ops-scripts/resolver-set-key.sh eth-sepolia "$KEY" "$TOKEN"
[[ $(cast call "$RESOLVER" 'get(string)(address)' "$KEY" --rpc-url "$TESTNET_FORK_RPC") == "$ZERO" ]]
INPUT=$(jq -er '.transactions[0].transaction.input' broadcast/ResolverSetKey.s.sol/11155111/dry-run/run-latest.json)
[[ "${INPUT,,}" == "${EXPECTED_SET,,}" ]]
cast rpc anvil_impersonateAccount "$OWNER" --rpc-url "$TESTNET_FORK_RPC"
cast rpc anvil_setBalance "$OWNER" 0x56BC75E2D63100000 --rpc-url "$TESTNET_FORK_RPC"
cast send "$RESOLVER" --data "$INPUT" --from "$OWNER" --unlocked --rpc-url "$TESTNET_FORK_RPC" --json
[[ $(cast call "$RESOLVER" 'get(string)(address)' "$KEY" --rpc-url "$TESTNET_FORK_RPC") == "$TOKEN" ]]
GOV=0xC6ec04c7b2f09E66aa50Ad9127dF6E0dC4B15DD3
HOST=0x109412E3C84f0539b43d39dB691B08c90f58dC7c
BEFORE=$(cast call "$GOV" 'getSuperTokenMinimumDeposit(address,address)(uint256)' "$HOST" "$ZERO" --rpc-url "$TESTNET_FORK_RPC")
RPC_URL=$TESTNET_FORK_RPC SIMULATE=1 bash new-ops-scripts/gov-action.sh eth-sepolia setTokenMinimumDeposit "$ZERO" 424242
[[ $(cast call "$GOV" 'getSuperTokenMinimumDeposit(address,address)(uint256)' "$HOST" "$ZERO" --rpc-url "$TESTNET_FORK_RPC") == "$BEFORE" ]]
INPUT=$(jq -er '.transactions[0].transaction.input' broadcast/GovAction.s.sol/11155111/dry-run/run-latest.json)
EXPECTED=$(cast calldata 'setSuperTokenMinimumDeposit(address,address,uint256)' "$HOST" "$ZERO" 424242)
[[ "${INPUT,,}" == "${EXPECTED,,}" ]]
cast send "$GOV" --data "$INPUT" --from "$OWNER" --unlocked --rpc-url "$TESTNET_FORK_RPC" --json
[[ $(cast call "$GOV" 'getSuperTokenMinimumDeposit(address,address)(uint256)' "$HOST" "$ZERO" --rpc-url "$TESTNET_FORK_RPC" --json | jq -r '.[0]') == 424242 ]]
echo 'Fork acceptance passed: mainnet legacy multisig list + overwrite guard; testnet resolver and governance EOA execution; simulations left fork state unchanged.'
