import fs from "fs";
import { ethers } from "hardhat";
import { TransactionResponse } from "@ethersproject/providers";
import { gql, request } from "graphql-request";
import { Framework, TestToken } from "@superfluid-finance/sdk-core";
import {
    IIndexSubscription,
    IMeta,
    ISubgraphErrors,
    ITestModifyFlowData,
    ITestUpdateFlowOperatorData,
} from "../interfaces";
import { FlowActionType } from "./constants";
import TestTokenABI from "../../abis/TestToken.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
const ORDER_MULTIPLIER = 10000; // This number is also defined as ORDER_MULTIPLIER in packages/subgraph/src/utils.ts
const MAX_SAFE_SECONDS = BigNumber.from("8640000000000"); // This number is also defined as MAX_SAFE_SECONDS in packages/subgraph/src/utils.ts
/**************************************************************************
 * Test Helper Functions
 *************************************************************************/
/**
 * Before setup function - deploy the framework, get signers, deploy test tokens,
 * initialize framework.
 * @param tokenAmount
 * @returns
 */
export const beforeSetup = async (tokenAmount: number) => {
    const [Deployer, Alpha, Bravo, Charlie] = await ethers.getSigners();
    const signers = [Deployer, Alpha, Bravo, Charlie];
    const signerDict: { [address: string]: SignerWithAddress } = signers.reduce(
        (x, y) => ({ ...x, [y.address]: y }),
        {}
    );

    console.log("Reading framework config...");
    const readFromDir = __dirname.split("test")[0] + "config/hardhat.json";
    const rawData = fs.readFileSync(readFromDir);
    const frameworkAddresses = JSON.parse(rawData.toString());

    const users = signers.map((x) => x.address);
    let totalSupply = 0;
    const chainId = (await Deployer.provider!.getNetwork()).chainId;

    console.log(`Creating Superfluid Framework (chainId: ${chainId})...`);
    const sf = await Framework.create({
        chainId,
        protocolReleaseVersion: "test",
        provider: Deployer.provider!,
        resolverAddress: frameworkAddresses.resolverV1Address,
    });

    const resolver = sf.contracts.resolver.connect(Deployer);

    console.log("\n");
    console.log("Loading Super Token fDAIx...");
    const fDAIx = await sf.loadWrapperSuperToken("fDAIx");

    // types not properly handling this case
    const fDAI = new ethers.Contract(
        fDAIx.underlyingToken.address,
        TestTokenABI
    ) as unknown as TestToken;

    console.log(
        "Mint fDAI, approve fDAIx allowance and upgrade fDAI to fDAIx for users..."
    );
    const amount = tokenAmount.toFixed(0);

    for (let i = 0; i < signers.length; i++) {
        console.log(`Processing user ${i + 1}/${signers.length}: ${signers[i].address}`);
        const stringBigIntAmount = ethers.utils.parseUnits(amount).toString();
        await fDAI
            .connect(signers[0])
            .mint(signers[i].address, stringBigIntAmount);
        await fDAI
            .connect(signers[i])
            .approve(fDAIx.address, stringBigIntAmount);
        await fDAIx
            .upgrade({
                amount: stringBigIntAmount,
            })
            .exec(signers[i]);
        totalSupply += Number(stringBigIntAmount);
    }

    // NOTE: although we already set this in initialization, we need to reset it here to ensure
    // we wait for the indexer to catch up before the tests start
    console.log("Setting resolver key...");
    const txn = await resolver.set("supertokens.test.fDAIx", fDAIx.address);
    const receipt = await txn.wait();

    console.log(`Waiting for block ${receipt.blockNumber} to be indexed...`);
    await waitUntilBlockIndexed(receipt.blockNumber);
    const resolverFDAIxAddress = await resolver.get("supertokens.test.fDAIx");

    if (resolverFDAIxAddress !== fDAIx.address) {
        throw new Error("fDAIx not set properly in resolver.");
    }

    console.log(
        "\n************** Superfluid Framework Setup Complete **************\n"
    );

    return {
        users,
        sf,
        fDAI,
        fDAIx,
        signerDict,
        totalSupply: totalSupply.toString(),
    };
};

export const monthlyToSecondRate = (monthlyRate: number) => {
    const days = 30;
    const hours = days * 24;
    const minutes = hours * 60;
    const seconds = minutes * 60;
    return Math.round((monthlyRate / seconds) * 10 ** 18);
};

// NOTE: + 1 ensures that the flow rate is never 0
export const getRandomFlowRate = (max: number) =>
    Math.floor(Math.random() * max) + 1;

export const getCurrentBlockNumber = async () => {
    const query = gql`
        query {
            _meta {
                block {
                    number
                }
            }
        }
    `;
    const data = await subgraphRequest<IMeta>(query);
    if (!data) return 0;

    return data._meta.block.number;
};

export const subgraphRequest = async <T>(
    query: string,
    variables?: { [key: string]: any }
): Promise<T> => {
    try {
        const response = await request<T & ISubgraphErrors>(
            "http://localhost:8000/subgraphs/name/superfluid-test",
            query,
            variables
        );

        if (response.errors) {
            throw new Error(
                `Failed call to subgraph with query ${query}, error thrown: ${JSON.stringify(
                    response.errors
                )}`
            );
        }

        return response;
    } catch (err) {
        throw new Error(
            `Failed call to subgraph with query ${query} and error ${err}`
        );
    }
};

export const fetchEntityAndEnsureExistence = async <T>(
    query: string,
    id: string,
    entityName: string
) => {
    const vars = {
        id,
    };
    const data = await subgraphRequest<{ response: T } & ISubgraphErrors>(
        query,
        vars
    );
    if (data.response == null) {
        throw new Error(entityName + " entity not found.");
    }

    return data.response;
};

export const fetchEventAndEnsureExistence = async <T>(
    query: string,
    transactionHash: string,
    eventName: string
) => {
    const vars = {
        transactionHash,
    };
    const data = await subgraphRequest<
        {
            response: T[];
        } & ISubgraphErrors
    >(query, vars);
    const event = data.response[0];

    if (!event) {
        throw new Error(eventName + " entity not found.");
    }

    return event;
};

export function toBN(num: any) {
    return ethers.BigNumber.from(num);
}

export function asleep(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

export const waitUntilBlockIndexed = async (txnBlockNumber: number) => {
    let currentBlock: number;
    do {
        currentBlock = await getCurrentBlockNumber();
        console.log(`Waiting for subgraph... Current: ${currentBlock}, Target: ${txnBlockNumber}`);
        await asleep(50);
    } while (txnBlockNumber > currentBlock);
};

export const getCurrentTotalAmountStreamed = (
    streamedSoFar: string,
    currentTime: string,
    lastUpdatedAtTime: string,
    outflowRate: string
) => {
    return toBN(streamedSoFar).add(
        toBN(outflowRate).mul(toBN(currentTime).sub(toBN(lastUpdatedAtTime)))
    );
};

/**************************************************************************
 * Entity ID Getters
 *************************************************************************/

export const getStreamId = (
    sender: string,
    receiver: string,
    token: string,
    revisionIndex: string
) =>
    [sender, receiver, token, revisionIndex + ".0"]
        .map((x) => x.toLowerCase())
        .join("-");

export const getFlowOperatorId = ({
    flowOperator,
    token,
    sender,
}: {
    flowOperator: string;
    token: string;
    sender: string;
}) => [flowOperator, token, sender].map((x) => x.toLowerCase()).join("-");

export const getRevisionIndexId = (
    sender: string,
    receiver: string,
    token: string
) => [sender, receiver, token].map((x) => x.toLowerCase()).join("-");

export const getIndexId = (publisher: string, token: string, indexId: string) =>
    [publisher, token, indexId].map((x) => x.toLowerCase()).join("-");

export const getSubscriptionId = (
    subscriber: string,
    publisher: string,
    token: string,
    indexId: string
) =>
    [subscriber, publisher, token, indexId]
        .map((x) => x.toLowerCase())
        .join("-");

export const getATSId = (accountId: string, tokenId: string) => {
    return accountId + "-" + tokenId;
};

/**************************************************************************
 * Modifier Functions
 *************************************************************************/

/**
 * Create/Update/Delete a flow between a sender and receiver.
 * Also waits for the graph to index and also returns the receipt
 * of the txn and data from the blockchain.
 * @param provider
 * @param sf
 * @param actionType
 * @param superToken
 * @param sender
 * @param receiver
 * @param newFlowRate
 * @returns txnReceipt, flow updatedAt (on-chain), flowRate (current on-chain)
 */
export const modifyFlowAndReturnCreatedFlowData = async (
    data: ITestModifyFlowData
) => {
    const actionToTypeStringMap = new Map([
        [FlowActionType.Create, "Create"],
        [FlowActionType.Update, "Update"],
        [FlowActionType.Delete, "Delete"],
    ]);
    console.log(
        `${actionToTypeStringMap.get(data.actionType)} flow from ${
            data.sender
        } to ${data.receiver} at ${data.newFlowRate}`
    );

    let signer = data.liquidator
        ? await ethers.getSigner(data.liquidator)
        : await ethers.getSigner(data.sender);
    const baseData = {
        superToken: data.superToken.address,
        sender: data.sender,
        receiver: data.receiver,
        userData: "0x",
    };
    let txnResponse: TransactionResponse;
    if (data.sender === data.flowOperator || data.liquidator) {
        txnResponse =
            data.actionType === FlowActionType.Create
                ? await data.framework.cfaV1
                      .createFlow({
                          ...baseData,
                          flowRate: data.newFlowRate.toString(),
                      })
                      .exec(signer)
                : data.actionType === FlowActionType.Update
                ? await data.framework.cfaV1
                      .updateFlow({
                          ...baseData,
                          flowRate: data.newFlowRate.toString(),
                      })
                      .exec(signer)
                : await data.framework.cfaV1
                      .deleteFlow({
                          ...baseData,
                          sender: data.sender,
                      })
                      .exec(signer);
    } else {
        // flowOperator is the signer here
        signer = await ethers.getSigner(data.flowOperator);
        txnResponse =
            data.actionType === FlowActionType.Create
                ? await data.framework.cfaV1
                      .createFlowByOperator({
                          ...baseData,
                          flowRate: data.newFlowRate.toString(),
                          sender: data.sender,
                      })
                      .exec(signer)
                : data.actionType === FlowActionType.Update
                ? await data.framework.cfaV1
                      .updateFlowByOperator({
                          ...baseData,
                          flowRate: data.newFlowRate.toString(),
                          sender: data.sender,
                      })
                      .exec(signer)
                : await data.framework.cfaV1
                      .deleteFlowByOperator({
                          ...baseData,
                          sender: data.sender,
                      })
                      .exec(signer);
    }

    if (!txnResponse.blockNumber) {
        throw new Error("No block number");
    }

    const block = await data.provider.getBlock(txnResponse.blockNumber);
    const timestamp = block.timestamp;
    await waitUntilBlockIndexed(txnResponse.blockNumber);
    const transactionReceipt = await txnResponse.wait();
    const methodFilter = data.framework.cfaV1.contract.filters.FlowUpdated();
    const methodSignature = methodFilter?.topics?.pop();
    const transactionLog = transactionReceipt.logs.find(
        (log) => log.topics[0] === methodSignature
    );
    const { flowRate, deposit } = await data.framework.cfaV1.getFlow({
        superToken: data.superToken.address,
        sender: data.sender,
        receiver: data.receiver,
        providerOrSigner: data.provider,
    });
    return {
        txnResponse,
        timestamp,
        flowRate: toBN(flowRate),
        deposit,
        logIndex: transactionLog?.logIndex,
    };
};

export const updateFlowOperatorPermissions = async (
    data: ITestUpdateFlowOperatorData
) => {
    const signer = await ethers.getSigner(data.sender);
    let txnResponse: TransactionResponse;

    const baseData = {
        superToken: data.superToken.address,
        sender: data.sender,
        flowOperator: data.flowOperator,
        userData: "0x",
    };

    // update flowOperator data
    if (data.isFullControl) {
        txnResponse = await data.framework.cfaV1
            .authorizeFlowOperatorWithFullControl(baseData)
            .exec(signer);
    } else if (data.isFullControlRevoke) {
        txnResponse = await data.framework.cfaV1
            .revokeFlowOperatorWithFullControl(baseData)
            .exec(signer);
    } else {
        txnResponse = await data.framework.cfaV1
            .updateFlowOperatorPermissions({
                ...baseData,
                permissions: data.permissions,
                flowRateAllowance: data.flowRateAllowance,
            })
            .exec(signer);
    }

    if (!txnResponse.blockNumber) {
        throw new Error("No block number");
    }

    const block = await data.provider.getBlock(txnResponse.blockNumber);
    const timestamp = block.timestamp;
    await waitUntilBlockIndexed(txnResponse.blockNumber);
    const transactionReceipt = await txnResponse.wait();
    const methodFilter =
        data.framework.cfaV1.contract.filters.FlowOperatorUpdated();
    const methodSignature = methodFilter?.topics?.pop();
    const transactionLog = transactionReceipt.logs.find(
        (log) => log.topics[0] === methodSignature
    );
    return { timestamp, txnResponse, logIndex: transactionLog?.logIndex };
};

export const hasSubscriptionWithUnits = (
    subscriptions: { [id: string]: IIndexSubscription | undefined },
    id: string
) => {
    const subscription = subscriptions[id];
    return subscription != null && toBN(subscription.units).gt(toBN(0));
};

/**
 * See ConstantFlowAgreementV1.sol for more details about deposit clipping.
 * @param deposit
 * @param roundingDown
 * @returns
 */
export const clipDepositNumber = (deposit: BigNumber, roundingDown = false) => {
    // last 32 bits of the deposit (96 bits) is clipped off
    const rounding = roundingDown
        ? 0
        : deposit.and(toBN(0xffffffff)).isZero()
        ? 0
        : 1;
    return deposit.shr(32).add(toBN(rounding)).shl(32);
};

export const getOrder = (blockNumber?: number, logIndex?: number) => {
    return blockNumber! * ORDER_MULTIPLIER + logIndex!;
};

export function calculateMaybeCriticalAtTimestamp(
    updatedAtTimestamp: string,
    balanceUntilUpdatedAt: string,
    totalNetFlowRate: string
) {
    // When the flow rate is not negative then there's no way to have a critical balance timestamp anymore.
    if (toBN(totalNetFlowRate).gte(toBN("0"))) return null;
    // When there's no balance then that either means:
    // 1. account is already critical, and we keep the existing timestamp when the liquidations supposedly started
    // 2. it's a new account without a critical balance timestamp to begin with
    if (toBN(balanceUntilUpdatedAt).lte(toBN("0"))) {
        throw new Error(
            "This will never gonna hit `Already critical` case because can't simulate realistic liquidation"
        ); //https://github.com/superfluid-finance/protocol-monorepo/pull/885
    }
    const secondsUntilCritical = toBN(balanceUntilUpdatedAt).div(
        toBN(totalNetFlowRate).abs()
    );
    const calculatedCriticalTimestamp = secondsUntilCritical.add(
        toBN(updatedAtTimestamp)
    );
    if (calculatedCriticalTimestamp.gt(MAX_SAFE_SECONDS)) {
        return MAX_SAFE_SECONDS.toString();
    }
    return calculatedCriticalTimestamp.toString();
}
