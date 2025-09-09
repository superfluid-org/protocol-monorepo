#!/usr/bin/env bash

set -e

set +x

# This script verifies the Superfluid framework contracts on Etherscan using Foundry.
# It takes 2 arguments:
# 1. The (canonical)network name
# 2. The addresses file
#
# It will verify contracts for which the address is set in its environment variable.
#
# Assume all required environment variables for addresses are set (e.g., RESOLVER_ADDRESS, HOST_ADDRESS, etc.).
# Also assume ETHERSCAN_API_V2_KEY and CHAIN_ID are set.
# Run this from the directory where foundry.toml is configured (packages/ethereum-contracts).

NETWORK_NAME=$1
ADDRESSES_VARS=$2

# Determine RPC_URL from environment variables
if [ -n "$RPC_URL" ]; then
    echo "using provided RPC_URL: $RPC_URL"
elif [ -n "$PROVIDER_URL_TEMPLATE" ]; then
    RPC_URL="${PROVIDER_URL_TEMPLATE//\{\{NETWORK\}\}/$NETWORK_NAME}"
    echo "using RPC_URL from template: $RPC_URL"
else
    echo "Error: Neither RPC_URL nor PROVIDER_URL_TEMPLATE environment variable is set"
    exit 1
fi

# get chain id from RPC
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
echo "using chain id: $CHAIN_ID"

# shellcheck disable=SC1090
source "$ADDRESSES_VARS"

COMMON_OPTS="--rpc-url ${RPC_URL} --etherscan-api-key ${ETHERSCAN_API_V2_KEY} --watch"

FAILED_VERIFICATIONS=()
function try_verify() {
    address=$1
    contract=$2
    echo -e "\n--------------------------------\n"
    echo "verifying $contract at $address"
    cmd="forge verify-contract $address $contract $COMMON_OPTS"
    echo "$cmd"
    $cmd || FAILED_VERIFICATIONS[${#FAILED_VERIFICATIONS[@]}]="$*"
}

# proxies

if [ -n "$SUPERFLUID_HOST_PROXY" ]; then
    try_verify "${SUPERFLUID_HOST_PROXY}" packages/ethereum-contracts/contracts/upgradability/UUPSProxy.sol:UUPSProxy
fi

if [ -n "$SUPER_TOKEN_FACTORY_PROXY" ]; then
    try_verify "${SUPER_TOKEN_FACTORY_PROXY}" packages/ethereum-contracts/contracts/upgradability/UUPSProxy.sol:UUPSProxy
fi

if [ -n "$POOL_ADMIN_NFT_PROXY" ]; then
    try_verify "${POOL_ADMIN_NFT_PROXY}" packages/ethereum-contracts/contracts/upgradability/UUPSProxy.sol:UUPSProxy
fi

if [ -n "$POOL_MEMBER_NFT_PROXY" ]; then
    try_verify "${POOL_MEMBER_NFT_PROXY}" packages/ethereum-contracts/contracts/upgradability/UUPSProxy.sol:UUPSProxy
fi

if [ -n "$ERC2771_FORWARDER" ]; then
    try_verify "${ERC2771_FORWARDER}" packages/ethereum-contracts/contracts/utils/ERC2771Forwarder.sol:ERC2771Forwarder
fi

if [ -n "$SUPERFLUID_GOVERNANCE" ]; then
    if [ -z "$IS_TESTNET" ]; then
        # mainnet -> it's the proxy
        try_verify "${SUPERFLUID_GOVERNANCE}" packages/ethereum-contracts/contracts/governance/SuperfluidGovernanceIIProxy.sol:SuperfluidGovernanceIIProxy
    fi
fi

if [ -n "$SUPER_TOKEN_NATIVE_COIN" ]; then
    try_verify "${SUPER_TOKEN_NATIVE_COIN}" packages/ethereum-contracts/contracts/tokens/SETH.sol:SETHProxy
fi


# it's called "dummy" because the instance exists for the purpose of verification
if [ -n "$DUMMY_BEACON_PROXY" ]; then
    try_verify "${DUMMY_BEACON_PROXY}" lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol:BeaconProxy
fi

# libs

if [ -n "$SLOTS_BITMAP_LIBRARY" ]; then
    try_verify "${SLOTS_BITMAP_LIBRARY}" packages/ethereum-contracts/contracts/libs/SlotsBitmapLibrary.sol:SlotsBitmapLibrary
fi

if [ -n "$SUPERFLUID_POOL_DEPLOYER_LIBRARY" ]; then
    try_verify "${SUPERFLUID_POOL_DEPLOYER_LIBRARY}" packages/ethereum-contracts/contracts/agreements/gdav1/SuperfluidPoolDeployerLibrary.sol:SuperfluidPoolDeployerLibrary
fi

# core

if [ -n "$SUPERFLUID_HOST_LOGIC" ]; then
    try_verify "${SUPERFLUID_HOST_LOGIC}" packages/ethereum-contracts/contracts/superfluid/Superfluid.sol:Superfluid
fi

if [ -n "$SUPERFLUID_GOVERNANCE" ]; then
    if [ -n "$IS_TESTNET" ]; then
        # testnet -> no proxy
        try_verify "${SUPERFLUID_GOVERNANCE}" packages/ethereum-contracts/contracts/utils/TestGovernance.sol:TestGovernance
    fi
fi
 
if [ -n "$SUPERFLUID_GOVERNANCE_LOGIC" ]; then
    try_verify "${SUPERFLUID_GOVERNANCE_LOGIC}" packages/ethereum-contracts/contracts/governance/SuperfluidGovernanceII.sol:SuperfluidGovernanceII
fi

if [ -n "$CFA_LOGIC" ]; then
    try_verify "${CFA_LOGIC}" packages/ethereum-contracts/contracts/agreements/ConstantFlowAgreementV1.sol:ConstantFlowAgreementV1
fi

if [ -n "$IDA_LOGIC" ]; then
    try_verify "${IDA_LOGIC}" packages/ethereum-contracts/contracts/agreements/InstantDistributionAgreementV1.sol:InstantDistributionAgreementV1
fi

if [ -n "$GDA_LOGIC" ]; then
    try_verify "${GDA_LOGIC}" packages/ethereum-contracts/contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol:GeneralDistributionAgreementV1
fi

if [ -n "$SUPERFLUID_POOL_LOGIC" ]; then
    try_verify "${SUPERFLUID_POOL_LOGIC}" packages/ethereum-contracts/contracts/agreements/gdav1/SuperfluidPool.sol:SuperfluidPool
fi

if [ -n "$SUPERFLUID_POOL_BEACON" ]; then
    try_verify "${SUPERFLUID_POOL_BEACON}" packages/ethereum-contracts/contracts/upgradability/SuperfluidUpgradeableBeacon.sol:SuperfluidUpgradeableBeacon
fi

if [ -n "$SUPER_TOKEN_FACTORY_LOGIC" ]; then
    try_verify "${SUPER_TOKEN_FACTORY_LOGIC}" packages/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol:SuperTokenFactory
fi

if [ -n "$SUPER_TOKEN_LOGIC" ]; then
    try_verify "${SUPER_TOKEN_LOGIC}" packages/ethereum-contracts/contracts/superfluid/SuperToken.sol:SuperToken
fi

# utils

if [ -n "$RESOLVER_ADDRESS" ]; then
    try_verify "${RESOLVER_ADDRESS}" contracts/utils/Resolver.sol:Resolver
fi

if [ -n "$SIMPLE_FORWARDER" ]; then
    try_verify "${SIMPLE_FORWARDER}" packages/ethereum-contracts/contracts/utils/SimpleForwarder.sol:SimpleForwarder
fi

if [ -n "$SUPERFLUID_LOADER" ]; then
    try_verify "${SUPERFLUID_LOADER}" packages/ethereum-contracts/contracts/utils/SuperfluidLoader.sol:SuperfluidLoader
fi

if [ -n "$SIMPLE_ACL" ]; then
    try_verify "${SIMPLE_ACL}" packages/ethereum-contracts/contracts/utils/SimpleACL.sol:SimpleACL
fi

if [ -n "$POOL_ADMIN_NFT_LOGIC" ]; then
    try_verify "${POOL_ADMIN_NFT_LOGIC}" packages/ethereum-contracts/contracts/agreements/gdav1/PoolAdminNFT.sol:PoolAdminNFT
fi

if [ -n "$CFAV1_FORWARDER" ]; then
    try_verify "${CFAV1_FORWARDER}" packages/ethereum-contracts/contracts/utils/CFAv1Forwarder.sol:CFAv1Forwarder
fi

if [ -n "$GDAV1_FORWARDER" ]; then
    try_verify "${GDAV1_FORWARDER}" packages/ethereum-contracts/contracts/utils/GDAv1Forwarder.sol:GDAv1Forwarder
fi

if [ -n "$TOGA" ]; then
    try_verify "${TOGA}" packages/ethereum-contracts/contracts/utils/TOGA.sol:TOGA
fi

if [ -n "$BATCH_LIQUIDATOR" ]; then
    try_verify "${BATCH_LIQUIDATOR}" packages/ethereum-contracts/contracts/utils/BatchLiquidator.sol:BatchLiquidator
fi

# testnet tokens

for var in "${!NON_SUPER_TOKEN_@}"; do
    addr=${!var}
    try_verify "${addr}" packages/ethereum-contracts/contracts/utils/TestToken.sol:TestToken
done

# optional peripery contracts

echo -e "\n================================\n"
if [ ${#FAILED_VERIFICATIONS[@]} -eq 0 ]; then
    echo "Succeeded without error"
else
    echo "Failed verifications (may be incomplete, better visually check the log!):"
    printf -- "- %s\n" "${FAILED_VERIFICATIONS[@]}"
fi

exit ${#FAILED_VERIFICATIONS[@]}