import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";
import { createMockedFunction } from "matchstick-as/assembly/index";
import { FlowUpdated } from "../generated/ConstantFlowAgreementV1/IConstantFlowAgreementV1";
import { BIG_INT_ZERO, ZERO_ADDRESS } from "../src/utils";
import {
    FAKE_INITIAL_BALANCE,
    FAKE_SUPER_TOKEN_TOTAL_SUPPLY,
    hostAddress,
    resolverAddress,
} from "./constants";
import {
    getETHAddress,
    getETHBoolean,
    getETHInt32,
    getETHSignedBigInt,
    getETHString,
    getETHUnsignedBigInt,
} from "./converters";

// @note When we mock RPC calls, we are essentially defining what the contracts are returning
// so in the case of mocking token name/symbol, etc. we are saying that these are the values on the
// contract

/**
 * Creates the necessary mocked functions in order for getOrInitSuperToken to work as expected.
 * @param superToken
 * @param decimals
 * @param underlyingAddress
 * @param tokenName
 * @param tokenSymbol
 */
export function mockedHandleSuperTokenInitRPCCalls(
    superToken: string,
    decimals: i32,
    underlyingAddress: Address,
    tokenName: string,
    tokenSymbol: string
): void {
    // [START] getTokenInfoAndReturn =>
    // token.try_getUnderlyingToken()
    mockedGetUnderlyingToken(superToken, underlyingAddress.toHexString());
    // token.try_name()
    mockedTokenName(superToken, tokenName);
    // token.try_symbol()
    mockedTokenSymbol(superToken, tokenSymbol);
    // token.try_decimals()
    mockedTokenDecimals(superToken, decimals);
    // [END] getTokenInfoAndReturn

    mockedResolverGet(resolverAddress, "supertokens.v1." + tokenSymbol, ZERO_ADDRESS.toHexString());

    // updateTotalSupplyForNativeSuperToken(token, tokenStatistic, tokenAddress)
    mockedTokenTotalSupply(superToken, FAKE_SUPER_TOKEN_TOTAL_SUPPLY);
}

/**
 * Creates the necessary mocked functions in order for the handleFlowUpdated mapping function to work as expected.
 * @param flowUpdatedEvent
 * @param superToken
 * @param decimals
 * @param tokenName
 * @param tokenSymbol
 * @param underlyingAddress
 * @param expectedDeposit
 * @param expectedOwedDeposit
 */
export function mockedHandleFlowUpdatedRPCCalls(
    flowUpdatedEvent: FlowUpdated,
    superToken: string,
    decimals: i32,
    tokenName: string,
    tokenSymbol: string,
    underlyingAddress: Address,
    expectedDeposit: BigInt,
    expectedOwedDeposit: BigInt
): void {
    const sender = flowUpdatedEvent.params.sender.toHex();
    const receiver = flowUpdatedEvent.params.receiver.toHex();
    const flowRate = flowUpdatedEvent.params.flowRate;

    // tokenHasValidHost => tokenContract.try_getHost()
    mockedGetHost(superToken);

    // cfaContract.try_GetFlow(token,sender,receiver)
    mockedGetFlow(
        flowUpdatedEvent.address.toHexString(),
        superToken,
        flowUpdatedEvent.params.sender.toHexString(),
        flowUpdatedEvent.params.receiver.toHexString(),
        flowUpdatedEvent.block.timestamp,
        flowRate,
        expectedDeposit,
        expectedOwedDeposit
    );

    // getOrInitStream(event) => getOrInitAccount(sender) => host.try_getAppManifest(sender)
    mockedGetAppManifest(sender, false, false, BIG_INT_ZERO);
    // getOrInitStream(event) => getOrInitAccount(receiver) => host.try_getAppManifest(receiver)
    mockedGetAppManifest(receiver, false, false, BIG_INT_ZERO);

    // [START] getOrInitStream(event) => getOrInitSuperToken(token, block) => handleTokenRPCCalls(token)
    mockedHandleSuperTokenInitRPCCalls(
        superToken,
        decimals,
        underlyingAddress,
        tokenName,
        tokenSymbol
    );
    // [END] getOrInitStream(event) => getOrInitSuperToken(token, block) => handleTokenRPCCalls(token)

    mockedResolverGet(resolverAddress, "supertokens.v1." + tokenSymbol, ZERO_ADDRESS.toHexString());

    // updateATSStreamedAndBalanceUntilUpdatedAt => updateATSBalanceAndUpdatedAt => try_realtimeBalanceOf(sender)
    mockedRealtimeBalanceOf(
        superToken,
        sender,
        flowUpdatedEvent.block.timestamp,
        FAKE_INITIAL_BALANCE.minus(flowRate),
        flowRate,
        BIG_INT_ZERO
    );
    // updateATSStreamedAndBalanceUntilUpdatedAt => updateATSBalanceAndUpdatedAt => try_realtimeBalanceOf(receiver)
    mockedRealtimeBalanceOf(
        superToken,
        receiver,
        flowUpdatedEvent.block.timestamp,
        FAKE_INITIAL_BALANCE,
        BIG_INT_ZERO,
        BIG_INT_ZERO
    );
}

// Mocked Resolver Functions

/**
 * Creates a mocked Resolver.get(key) function
 * @param resolverAddress
 * @param key the key of the item
 * @param value the expected value (zero address means unlisted for given key)
 */
export function mockedResolverGet(
    resolverAddress: string,
    key: string,
    value: string
): void {
    createMockedFunction(
        Address.fromString(resolverAddress),
        "get",
        "get(string):(address)"
    )
        .withArgs([ethereum.Value.fromString(key)])
        .returns([ethereum.Value.fromAddress(Address.fromString(value))]);
}

// Mocked CFAv1 Functions

/**
 * Creates a mocked ConstantFlowAgreementV1.getFlow(token,sender,receiver) function
 * @param cfaV1Address address of cfaV1 contract
 * @param tokenAddress
 * @param senderAddress
 * @param receiverAddress
 * @param expectedTimestamp expected return timestamp (from transaction)
 * @param expectedFlowRate expected flow rate (from input)
 * @param expectedDeposit expected deposit (can be arbitrary, but useful to base off actual)
 * @param expectedOwedDeposit expected owed deposit (0 unless streaming to superApp callback)
 */
export function mockedGetFlow(
    cfaV1Address: string,
    tokenAddress: string,
    senderAddress: string,
    receiverAddress: string,
    expectedTimestamp: BigInt,
    expectedFlowRate: BigInt,
    expectedDeposit: BigInt,
    expectedOwedDeposit: BigInt
): void {
    createMockedFunction(
        Address.fromString(cfaV1Address),
        "getFlow",
        "getFlow(address,address,address):(uint256,int96,uint256,uint256)"
    )
        .withArgs([
            getETHAddress(tokenAddress),
            getETHAddress(senderAddress),
            getETHAddress(receiverAddress),
        ])
        .returns([
            getETHUnsignedBigInt(expectedTimestamp),
            getETHSignedBigInt(expectedFlowRate),
            getETHUnsignedBigInt(expectedDeposit),
            getETHUnsignedBigInt(expectedOwedDeposit),
        ]);
}

// Mocked Host Functions

/**
 * Creates a mocked Superfluid.getAppManifest(address) function
 * @param accountAddress
 * @param expectedIsSuperApp
 * @param expectedIsJailed
 * @param expectedNoopMask
 */
export function mockedGetAppManifest(
    accountAddress: string,
    expectedIsSuperApp: boolean,
    expectedIsJailed: boolean,
    expectedNoopMask: BigInt
): void {
    createMockedFunction(
        Address.fromString(hostAddress),
        "getAppManifest",
        "getAppManifest(address):(bool,bool,uint256)"
    )
        .withArgs([getETHAddress(accountAddress)])
        .returns([
            getETHBoolean(expectedIsSuperApp),
            getETHBoolean(expectedIsJailed),
            getETHUnsignedBigInt(expectedNoopMask),
        ]);
}

// Mocked SuperToken Functions

/**
 * Creates a mocked SuperToken.getHost() function
 * @param tokenAddress
 */
export function mockedGetHost(tokenAddress: string): void {
    createMockedFunction(
        Address.fromString(tokenAddress),
        "getHost",
        "getHost():(address)"
    )
        .withArgs([])
        .returns([ethereum.Value.fromAddress(Address.fromString(hostAddress))]);
}

/**
 * Creates a mocked SuperToken.getUnderlyingToken(address) function
 * @param tokenAddress
 * @param expectedUnderlyingToken
 */
export function mockedGetUnderlyingToken(
    tokenAddress: string,
    expectedUnderlyingToken: string
): void {
    createMockedFunction(
        Address.fromString(tokenAddress),
        "getUnderlyingToken",
        "getUnderlyingToken():(address)"
    )
        .withArgs([])
        .returns([getETHAddress(expectedUnderlyingToken)]);
}

/**
 * Creates a mocked SuperToken.realtimeBalanceOf(address,uint256) function
 * @param superTokenAddress
 * @param accountAddress
 * @param timestamp
 * @param expectedAvailableBalance
 * @param expectedDeposit
 * @param expectedOwedDeposit
 */
export function mockedRealtimeBalanceOf(
    superTokenAddress: string,
    accountAddress: string,
    timestamp: BigInt,
    expectedAvailableBalance: BigInt,
    expectedDeposit: BigInt,
    expectedOwedDeposit: BigInt
): void {
    createMockedFunction(
        Address.fromString(superTokenAddress),
        "realtimeBalanceOf",
        "realtimeBalanceOf(address,uint256):(int256,uint256,uint256)"
    )
        .withArgs([
            getETHAddress(accountAddress),
            getETHUnsignedBigInt(timestamp),
        ])
        .returns([
            getETHSignedBigInt(expectedAvailableBalance),
            getETHUnsignedBigInt(expectedDeposit),
            getETHUnsignedBigInt(expectedOwedDeposit),
        ]);
}

/**
 * Creates a mocked SuperToken.name() function
 * @param tokenAddress
 * @param expectedName
 */
export function mockedTokenName(
    tokenAddress: string,
    expectedName: string
): void {
    createMockedFunction(
        Address.fromString(tokenAddress),
        "name",
        "name():(string)"
    )
        .withArgs([])
        .returns([getETHString(expectedName)]);
}

/**
 * Creates a mocked SuperToken.symbol() function
 * @param tokenAddress
 * @param expectedSymbol
 */
export function mockedTokenSymbol(
    tokenAddress: string,
    expectedSymbol: string
): void {
    createMockedFunction(
        Address.fromString(tokenAddress),
        "symbol",
        "symbol():(string)"
    )
        .withArgs([])
        .returns([getETHString(expectedSymbol)]);
}

/**
 * Creates a mocked SuperToken.decimals() function
 * @param tokenAddress
 * @param expectedDecimals
 */
export function mockedTokenDecimals(
    tokenAddress: string,
    expectedDecimals: i32
): void {
    createMockedFunction(
        Address.fromString(tokenAddress),
        "decimals",
        "decimals():(uint8)"
    )
        .withArgs([])
        .returns([getETHInt32(expectedDecimals)]);
}

/**
 * Creates a mocked SuperToken.totalSupply() function
 * @param tokenAddress
 * @param expectedTotalSupply
 */
export function mockedTokenTotalSupply(
    tokenAddress: string,
    expectedTotalSupply: BigInt
): void {
    createMockedFunction(
        Address.fromString(tokenAddress),
        "totalSupply",
        "totalSupply():(uint256)"
    )
        .withArgs([])
        .returns([getETHUnsignedBigInt(expectedTotalSupply)]);
}

/**
 * Creates a mocked SuperToken.approve() function
 * @param tokenAddress
 * @param ownerAddress
 * @param spenderAddress
 * @param expectedValue
 */
export function mockedApprove(
    tokenAddress: string,
    ownerAddress: string,
    spenderAddress: string,
    expectedValue: BigInt
): void {
    createMockedFunction(
        Address.fromString(tokenAddress),
        "allowance",
        "allowance(address,address):(uint256)",
    )
        .withArgs([
            ethereum.Value.fromAddress(Address.fromString(ownerAddress)),
            ethereum.Value.fromAddress(Address.fromString(spenderAddress))
        ])
        .returns([getETHUnsignedBigInt(expectedValue)]);
}

export function mockedAppManifestAndRealtimeBalanceOf(
    tokenAddress: string,
    accountAddress: string,
    timestamp: BigInt
): void {
    mockedGetAppManifest(accountAddress, false, false, BIG_INT_ZERO);
    mockedRealtimeBalanceOf(
        tokenAddress,
        accountAddress,
        timestamp,
        FAKE_INITIAL_BALANCE,
        BIG_INT_ZERO,
        BIG_INT_ZERO
    );
}
