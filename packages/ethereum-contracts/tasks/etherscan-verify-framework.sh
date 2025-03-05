#!/usr/bin/env bash

# verification script for etherscan-like explorers.
# takes 2 arguments: the canonical network name and a file with a list of contract addresses to verify.
# If additional arguments are provided, they will be added to individual verification commands.
# tries to verify the (sub)set of contracts listed in the file.
# if proxy addresses are provided, verification against up-to-date logic contracts will only succeed
# once they point to those (after gov upgrade execution)

CONTRACTS_DIR=build/truffle

SOURCIFY_ONLY_NETWORKS=("degenchain")

TRUFFLE_NETWORK=$1
ADDRESSES_VARS=$2

shift 1

if [ -z "$ADDRESSES_VARS" ]; then
    EXTRA_ARGS="$*"
    echo "EXTRA_ARGS: $EXTRA_ARGS"
    echo "no addresses provided, fetching myself..."
    ADDRESSES_VARS="/tmp/superfluid.$TRUFFLE_NETWORK.addrs"
    npx truffle exec --network "$TRUFFLE_NETWORK" ops-scripts/info-print-contract-addresses.js : "$ADDRESSES_VARS" || exit 1
else
    shift 1
fi

EXTRA_ARGS="$*"

# shellcheck disable=SC1090
source "$ADDRESSES_VARS"

if [[ " ${SOURCIFY_ONLY_NETWORKS[*]} " == *" $TRUFFLE_NETWORK "* ]]; then
    VERIFIERS="sourcify"
else
    VERIFIERS="etherscan,sourcify"
fi

FAILED_VERIFICATIONS=()
function try_verify() {
    echo # newline for better readability
    cmd="npx truffle run --network $TRUFFLE_NETWORK --verifiers=$VERIFIERS verify $* ${EXTRA_ARGS:+$EXTRA_ARGS}"
    echo "> $cmd"
    $cmd || FAILED_VERIFICATIONS[${#FAILED_VERIFICATIONS[@]}]="$*"
        # NOTE: append using length so that having spaces in the element is not a problem
        # TODO: version 0.6.5 of the plugin seems to not reliably return non-zero if verification fails
}

function link_library() {
    local contract_name="$1"
    local library_name="$2"
    local library_address="$3"

    echo "linking $contract_name to $library_name at $library_address"

    cp -f "$CONTRACTS_DIR/${contract_name}.json" "$CONTRACTS_DIR/${contract_name}.json.bak"
    jq -s '.[0] * .[1]' \
        "$CONTRACTS_DIR/${contract_name}.json.bak" \
        <(cat <<EOF
{
    "networks": {
        "$NETWORK_ID": {
            "links": {
                "${library_name}": "${library_address}"
            }
        }
    }
}
EOF
        ) > "$CONTRACTS_DIR/${contract_name}.json"
}

if [ -n "$RESOLVER" ]; then
    try_verify Resolver@"${RESOLVER}"
fi

if [ -n "$ERC2771_FORWARDER" ]; then
    try_verify ERC2771Forwarder@"${ERC2771_FORWARDER}"
fi
if [ -n "$SIMPLE_FORWARDER" ]; then
    try_verify SimpleForwarder@"${SIMPLE_FORWARDER}"
fi

if [ -n "$SUPERFLUID_HOST_LOGIC" ]; then
    # verify the logic contract. May or may not be already set as a proxy implementation
    try_verify Superfluid@"${SUPERFLUID_HOST_LOGIC}"
fi
if [ -n "$SUPERFLUID_HOST_PROXY" ]; then
    # by verifying against the proxy address, the contracts are "linked" in the Explorer
    try_verify Superfluid@"${SUPERFLUID_HOST_PROXY}" --custom-proxy UUPSProxy
fi

if [ -n "$SUPERFLUID_GOVERNANCE" ]; then
    if [ -n "$IS_TESTNET" ]; then
        try_verify TestGovernance@"${SUPERFLUID_GOVERNANCE}"
    else
        if [ -n "$SUPERFLUID_GOVERNANCE_LOGIC" ]; then
            try_verify SuperfluidGovernanceII@"${SUPERFLUID_GOVERNANCE_LOGIC}"
        fi
        try_verify SuperfluidGovernanceII@"${SUPERFLUID_GOVERNANCE}" --custom-proxy SuperfluidGovernanceIIProxy
    fi
fi

if [ -n "$SUPERFLUID_LOADER" ]; then
    try_verify SuperfluidLoader@"${SUPERFLUID_LOADER}"
fi

if [ -n "$SUPER_TOKEN_FACTORY_LOGIC" ]; then
    try_verify SuperTokenFactory@"${SUPER_TOKEN_FACTORY_LOGIC}"
fi
if [ -n "$SUPER_TOKEN_FACTORY_PROXY" ]; then
    try_verify SuperTokenFactory@"${SUPER_TOKEN_FACTORY_PROXY}" --custom-proxy UUPSProxy
fi

if [ -n "$POOL_ADMIN_NFT_PROXY" ]; then
    try_verify PoolAdminNFT@"${POOL_ADMIN_NFT_PROXY}" --custom-proxy UUPSProxy
fi

if [ -n "$POOL_MEMBER_NFT_PROXY" ]; then
    try_verify PoolMemberNFT@"${POOL_MEMBER_NFT_PROXY}" --custom-proxy UUPSProxy
fi

if [ -n "$POOL_ADMIN_NFT_LOGIC" ]; then
    try_verify PoolAdminNFT@"${POOL_ADMIN_NFT_LOGIC}"
fi

if [ -n "$POOL_MEMBER_NFT_LOGIC" ]; then
    try_verify PoolMemberNFT@"${POOL_MEMBER_NFT_LOGIC}"
fi

if [ -n "$SUPER_TOKEN_LOGIC" ]; then
    try_verify SuperToken@"${SUPER_TOKEN_LOGIC}"
fi

if [ -n "$CFA_LOGIC" ]; then
    try_verify ConstantFlowAgreementV1@"${CFA_LOGIC}"
fi
if [ -n "$CFA_PROXY" ]; then
    try_verify ConstantFlowAgreementV1@"${CFA_PROXY}" --custom-proxy UUPSProxy
fi

if [ -n "$SLOTS_BITMAP_LIBRARY" ]; then
    try_verify SlotsBitmapLibrary@"${SLOTS_BITMAP_LIBRARY}"
fi

link_library "InstantDistributionAgreementV1" "SlotsBitmapLibrary" "${SLOTS_BITMAP_LIBRARY}"
if [ -n "$IDA_LOGIC" ]; then
    try_verify InstantDistributionAgreementV1@"${IDA_LOGIC}"
fi
if [ -n "$IDA_PROXY" ]; then
    try_verify InstantDistributionAgreementV1@"${IDA_PROXY}" --custom-proxy UUPSProxy
fi
mv -f $CONTRACTS_DIR/InstantDistributionAgreementV1.json.bak $CONTRACTS_DIR/InstantDistributionAgreementV1.json

if [ -n "$SUPERFLUID_POOL_DEPLOYER_LIBRARY" ]; then
    try_verify SuperfluidPoolDeployerLibrary@"${SUPERFLUID_POOL_DEPLOYER_LIBRARY}"
fi

if [ -n "$DUMMY_BEACON_PROXY" ]; then
    try_verify BeaconProxy@"${DUMMY_BEACON_PROXY}"
fi

# this will fail with 'Library address is not prefixed with "0x"' if a library address is not set
link_library "GeneralDistributionAgreementV1" "SlotsBitmapLibrary" "${SLOTS_BITMAP_LIBRARY}"
link_library "GeneralDistributionAgreementV1" "SuperfluidPoolDeployerLibrary" "${SUPERFLUID_POOL_DEPLOYER_LIBRARY}"
if [ -n "$GDA_LOGIC" ]; then
    try_verify GeneralDistributionAgreementV1@"${GDA_LOGIC}"
fi

if [ -n "$GDA_PROXY" ]; then
    try_verify GeneralDistributionAgreementV1@"${GDA_PROXY}" --custom-proxy UUPSProxy
fi
mv -f $CONTRACTS_DIR/GeneralDistributionAgreementV1.json.bak $CONTRACTS_DIR/GeneralDistributionAgreementV1.json

if [ -n "$SUPERFLUID_POOL_BEACON" ]; then
    try_verify SuperfluidUpgradeableBeacon@"${SUPERFLUID_POOL_BEACON}"
fi

if [ -n "$SUPERFLUID_POOL_LOGIC" ]; then
    try_verify SuperfluidPool@"${SUPERFLUID_POOL_LOGIC}"
fi

# super tokens

if [ -n "$SUPER_TOKEN_NATIVE_COIN" ];then
    # special case: verify only the proxy
    # it is expected to point to a SuperToken logic contract which is already verified
    try_verify SuperToken@"${SUPER_TOKEN_NATIVE_COIN}" --custom-proxy SETHProxy
fi

# testnet tokens
for var in "${!NON_SUPER_TOKEN_@}"; do
    addr=${!var}
    try_verify TestToken@"$addr"
done

# optional peripery contracts

if [ -n "$CFAV1_FORWARDER" ];then
    try_verify CFAv1Forwarder@"${CFAV1_FORWARDER}"
fi

if [ -n "$GDAV1_FORWARDER" ];then
    try_verify GDAv1Forwarder@"${GDAV1_FORWARDER}"
fi

if [ -n "$TOGA" ];then
    try_verify TOGA@"${TOGA}"
fi

if [ -n "$BATCH_LIQUIDATOR" ];then
    try_verify BatchLiquidator@"${BATCH_LIQUIDATOR}"
fi

if [ -n "$FLOW_SCHEDULER" ];then
    try_verify FlowScheduler@"${FLOW_SCHEDULER}"
fi

if [ -n "$VESTING_SCHEDULER" ];then
    try_verify VestingScheduler@"${VESTING_SCHEDULER}"
fi

set +x

echo "Failed verifications (may be incomplete, better visually check the log!):"
printf -- "- %s\n" "${FAILED_VERIFICATIONS[@]}"
exit ${#FAILED_VERIFICATIONS[@]}
