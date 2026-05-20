import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { Stream, StreamRevision, Token } from "../generated/schema";
import { getNativeAssetSuperTokenAddress } from "../src/addresses";
import { getStreamID } from "../src/utils";

/**
 * Creates a SuperToken entity
 * @param tokenAddress the address of the token
 * @param block transaction block object
 * @param decimals number of decimals
 * @param name token name
 * @param symbol token symbol
 * @param isListed whether the token is listed
 * @param underlyingAddress the underlying token address
 * @param rewardAddress the reward token address
 * @param liquidationPeriod the liquidation period
 * @param patricianPeriod the patrician period
 * @param minimumDeposit the minimum deposit
 * @returns Token
 */
export function createSuperToken(
    tokenAddress: Address,
    block: ethereum.Block,
    decimals: i32,
    name: string,
    symbol: string,
    isListed: boolean,
    underlyingAddress: Address,
): Token {
    const tokenId = tokenAddress.toHex();
    let currentTimestamp = block.timestamp;

    const token = new Token(tokenId);
    token.createdAtTimestamp = currentTimestamp;
    token.createdAtBlockNumber = block.number;
    token.decimals = decimals;
    token.name = name;
    token.symbol = symbol;
    token.isSuperToken = true;

    const nativeAssetSuperTokenAddress = getNativeAssetSuperTokenAddress();
    token.isNativeAssetSuperToken = tokenAddress.equals(
        nativeAssetSuperTokenAddress
    );
    token.isListed = isListed;

    token.underlyingAddress = underlyingAddress;
    token.underlyingToken = underlyingAddress.toHex();
    
    token.save();
    return token as Token;
}

/**
 * Creates a Stream entity
 * Note: this function currently assumes the createdAt/updatedAt is the same.
 * @param senderAddress 
 * @param receiverAddress 
 * @param tokenAddress 
 * @param revisionIndex 
 * @param block
 * @param currentFlowRate 
 * @param deposit 
 * @param streamedUntilUpdatedAt 
 * @returns 
 */
export function createStream(
    senderAddress: Address,
    receiverAddress: Address,
    tokenAddress: Address,
    revisionIndex: i32,
    block: ethereum.Block,
    currentFlowRate: BigInt,
    deposit: BigInt,
    streamedUntilUpdatedAt: BigInt,
    userData: Bytes
): Stream {
    const streamId = getStreamID(
        senderAddress,
        receiverAddress,
        tokenAddress,
        revisionIndex
    );
    const timestamp = block.timestamp;
    const blockNumber = block.number;

    const stream = new Stream(streamId);
    stream.createdAtTimestamp = timestamp;
    stream.createdAtBlockNumber = blockNumber;
    stream.updatedAtTimestamp = timestamp;
    stream.updatedAtBlockNumber = blockNumber;
    stream.currentFlowRate = currentFlowRate;
    stream.deposit = deposit;
    stream.owedDeposit = BigInt.fromI32(0);
    stream.streamedUntilUpdatedAt = streamedUntilUpdatedAt;
    stream.token = tokenAddress.toHex();
    stream.sender = senderAddress.toHex();
    stream.receiver = receiverAddress.toHex();
    stream.userData = userData;
    stream.save();
    return stream;
}

/**
 * Creates a StreamRevision entity
 * @param flowId 
 * @param tokenAddress 
 * @param streamId 
 * @param revisionIndex 
 * @param periodRevisionIndex 
 * @returns StreamRevision
 */
export function createStreamRevision(
    flowId: string,
    tokenAddress: string,
    streamId: string,
    revisionIndex: i32,
    periodRevisionIndex: i32,
): StreamRevision {
    const id = flowId + "-" + tokenAddress;

    const streamRevision = new StreamRevision(id);
    streamRevision.mostRecentStream = streamId;
    streamRevision.revisionIndex = revisionIndex;
    streamRevision.periodRevisionIndex =  periodRevisionIndex;

    streamRevision.save();
    return streamRevision;
}