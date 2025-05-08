import { Address, BigInt, Bytes, crypto, ethereum } from "@graphprotocol/graph-ts";
import {
    assert,
    beforeEach,
    clearStore,
    describe,
    test,
} from "matchstick-as/assembly/index";
import {
    handleAgreementLiquidatedBy,
    handleAgreementLiquidatedV2,
    handleApproval,
    handleBurned,
    handleMinted,
    handleSent,
    handleTokenDowngraded,
    handleTokenUpgraded,
    handleTransfer,
} from "../../../src/mappings/superToken";
import { BIG_INT_ONE, BIG_INT_ZERO, encode, ZERO_ADDRESS } from "../../../src/utils";
import { assertEmptyTokenStatisticProperties, assertEventBaseProperties, assertTokenStatisticProperties } from "../../assertionHelpers";
import { alice, bob, cfaV1Address, charlie, DEFAULT_DECIMALS, delta, FAKE_INITIAL_BALANCE, FALSE, maticXName, maticXSymbol, TRUE } from "../../constants";
import { getETHAddress, getETHUnsignedBigInt, stringToBytes } from "../../converters";
import { createStream, createStreamRevision } from "../../mockedEntities";
import { mockedGetAppManifest, mockedGetHost, mockedHandleSuperTokenInitRPCCalls, mockedRealtimeBalanceOf } from "../../mockedFunctions";
import {
    createAgreementLiquidatedByEvent,
    createAgreementLiquidatedV2Event,
    createBurnedEvent,
    createMintedEvent,
    createSentEvent,
    createSuperTokenApprovalEvent,
    createTokenDowngradedEvent,
    createTokenUpgradedEvent,
    createTransferEvent,
} from "../superToken.helper";

describe("SuperToken Mapper Unit Tests", () => {
    describe("Event Entity Mapping Tests", () => {
        beforeEach(() => {
            clearStore();
        });

        test("handleAgreementLiquidatedBy() - Should create a new handleAgreementLiquidatedByEvent entity", () => {
            const eventName = "AgreementLiquidatedBy";
            const liquidatorAccount = alice;
            const penaltyAccount = bob; // sender
            const bondAccount = charlie;
            const receiver = delta;
            const agreementClass = cfaV1Address;
            const values: Array<ethereum.Value> = [
                getETHAddress(penaltyAccount),
                getETHAddress(receiver),
            ];
            const agreementId = crypto.keccak256(encode(values)); // flowId keccak256(abi.encode(sender, receiver))
            const rewardAmount = BigInt.fromI32(100);
            const currentFlowRate = BigInt.fromI32(42069);
            const revisionIndex = 0;
            const bailoutAmount = BIG_INT_ZERO;
            const deposit = BigInt.fromI32(420);

            const agreementLiquidatedByEvent = createAgreementLiquidatedByEvent(
                liquidatorAccount,
                agreementClass,
                Bytes.fromByteArray(agreementId),
                penaltyAccount,
                bondAccount,
                rewardAmount,
                bailoutAmount
            );

            const tokenAddress = agreementLiquidatedByEvent.address.toHex();

            const stream = createStream(
                Address.fromString(penaltyAccount),
                Address.fromString(receiver),
                agreementLiquidatedByEvent.address,
                revisionIndex,
                agreementLiquidatedByEvent.block,
                currentFlowRate,
                deposit,
                BIG_INT_ZERO,
                stringToBytes("")
            );

            createStreamRevision(
                agreementLiquidatedByEvent.params.id.toHex(),
                tokenAddress,
                stream.id,
                revisionIndex,
                0 // periodRevisionIndex
            );

            mockedGetHost(tokenAddress);

            mockedHandleSuperTokenInitRPCCalls(
                tokenAddress,
                DEFAULT_DECIMALS,
                ZERO_ADDRESS,
                maticXName,
                maticXSymbol
            );

            mockedRealtimeBalanceOf(
                tokenAddress,
                liquidatorAccount,
                agreementLiquidatedByEvent.block.timestamp,
                FAKE_INITIAL_BALANCE,
                BIG_INT_ZERO,
                BIG_INT_ZERO
            );
            mockedGetAppManifest(liquidatorAccount, false, false, BIG_INT_ZERO);

            mockedRealtimeBalanceOf(
                tokenAddress,
                penaltyAccount,
                agreementLiquidatedByEvent.block.timestamp,
                FAKE_INITIAL_BALANCE,
                BIG_INT_ZERO,
                BIG_INT_ZERO
            );
            mockedGetAppManifest(penaltyAccount, false, false, BIG_INT_ZERO);

            mockedRealtimeBalanceOf(
                tokenAddress,
                bondAccount,
                agreementLiquidatedByEvent.block.timestamp,
                FAKE_INITIAL_BALANCE,
                BIG_INT_ZERO,
                BIG_INT_ZERO
            );
            mockedGetAppManifest(bondAccount, false, false, BIG_INT_ZERO);

            handleAgreementLiquidatedBy(agreementLiquidatedByEvent);

            const id = assertEventBaseProperties(
                agreementLiquidatedByEvent,
                eventName
            );
            const entityName = eventName + "Event";
            assert.fieldEquals(entityName, id, "token", tokenAddress);
            assert.fieldEquals(entityName, id, "liquidatorAccount", liquidatorAccount);
            assert.fieldEquals(entityName, id, "agreementClass", agreementClass);
            assert.fieldEquals(entityName, id, "agreementId", agreementId.toHexString());
            assert.fieldEquals(entityName, id, "penaltyAccount", penaltyAccount);
            assert.fieldEquals(entityName, id, "bondAccount", bondAccount);
            assert.fieldEquals(entityName, id, "rewardAmount", rewardAmount.toString());
            assert.fieldEquals(entityName, id, "bailoutAmount", bailoutAmount.toString());
            assert.fieldEquals(entityName, id, "deposit", deposit.toString());
            assert.fieldEquals(entityName, id, "flowRateAtLiquidation", currentFlowRate.toString());
        });

        test("handleAgreementLiquidatedV2() - Should create a new AgreementLiquidatedV2Event entity", () => {
            const eventName = "AgreementLiquidatedV2";
            const liquidatorAccount = alice;
            const targetAccount = bob; // sender
            const receiver = delta;
            const rewardAmountReceiver = charlie;
            const agreementClass = cfaV1Address;
            const agreementIdValues: Array<ethereum.Value> = [getETHAddress(targetAccount), getETHAddress(receiver)];
            const version = BIG_INT_ONE;
            const liquidationType = BIG_INT_ZERO
            const versionValue = getETHUnsignedBigInt(BIG_INT_ONE);
            const liquidationTypeValue = getETHUnsignedBigInt(BIG_INT_ZERO);
            const liquidationTypeDataValues: Array<ethereum.Value> = [
                versionValue,
                liquidationTypeValue,
              ]
            const agreementId = encode(agreementIdValues);
            const liquidationTypeData = encode(liquidationTypeDataValues);
            const rewardAmount = BigInt.fromI32(100);
            const revisionIndex = 0;
            const targetAccountBalanceDelta = rewardAmount.neg();
            const currentFlowRate = BigInt.fromI32(42069);
            const deposit = BigInt.fromI32(420);

            const agreementLiquidatedV2Event = createAgreementLiquidatedV2Event(
                liquidatorAccount,
                agreementClass,
                agreementId,
                targetAccount,
                rewardAmountReceiver,
                rewardAmount,
                targetAccountBalanceDelta,
                liquidationTypeData
            );
            const stream = createStream(
                Address.fromString(targetAccount),
                Address.fromString(receiver),
                agreementLiquidatedV2Event.address,
                revisionIndex,
                agreementLiquidatedV2Event.block,
                currentFlowRate,
                deposit,
                BIG_INT_ZERO,
                stringToBytes("")
            );
            const tokenAddress = agreementLiquidatedV2Event.address.toHex();

            createStreamRevision(
                agreementLiquidatedV2Event.params.id.toHex(),
                tokenAddress,
                stream.id,
                revisionIndex,
                0 // periodRevisionIndex
            );

            mockedGetHost(tokenAddress);

            mockedHandleSuperTokenInitRPCCalls(
                tokenAddress,
                DEFAULT_DECIMALS,
                ZERO_ADDRESS,
                maticXName,
                maticXSymbol
            );

            mockedRealtimeBalanceOf(
                tokenAddress,
                liquidatorAccount,
                agreementLiquidatedV2Event.block.timestamp,
                FAKE_INITIAL_BALANCE,
                BIG_INT_ZERO,
                BIG_INT_ZERO
            );
            mockedGetAppManifest(liquidatorAccount, false, false, BIG_INT_ZERO);

            mockedRealtimeBalanceOf(
                tokenAddress,
                targetAccount,
                agreementLiquidatedV2Event.block.timestamp,
                FAKE_INITIAL_BALANCE,
                BIG_INT_ZERO,
                BIG_INT_ZERO
            );
            mockedGetAppManifest(targetAccount, false, false, BIG_INT_ZERO);

            mockedRealtimeBalanceOf(
                tokenAddress,
                rewardAmountReceiver,
                agreementLiquidatedV2Event.block.timestamp,
                FAKE_INITIAL_BALANCE,
                BIG_INT_ZERO,
                BIG_INT_ZERO
            );
            mockedGetAppManifest(rewardAmountReceiver, false, false, BIG_INT_ZERO);

            handleAgreementLiquidatedV2(agreementLiquidatedV2Event);

            const id = assertEventBaseProperties(
                agreementLiquidatedV2Event,
                eventName
            );
            const entityName = eventName + "Event";
            assert.fieldEquals(entityName, id, "token", tokenAddress);
            assert.fieldEquals(entityName, id, "agreementClass", agreementClass);
            assert.fieldEquals(entityName, id, "agreementId", agreementId.toHexString());
            assert.fieldEquals(entityName, id, "liquidatorAccount", liquidatorAccount);
            assert.fieldEquals(entityName, id, "targetAccount", targetAccount);
            assert.fieldEquals(entityName, id, "rewardAmountReceiver", rewardAmountReceiver);
            assert.fieldEquals(entityName, id, "rewardAmount", rewardAmount.toString());
            assert.fieldEquals(entityName, id, "targetAccountBalanceDelta", targetAccountBalanceDelta.toString());
            assert.fieldEquals(entityName, id, "version", version.toString());
            assert.fieldEquals(entityName, id, "liquidationType", liquidationType.toString());
            assert.fieldEquals(entityName, id, "deposit", deposit.toString());
            assert.fieldEquals(entityName, id, "flowRateAtLiquidation", currentFlowRate.toString());

            assertTokenStatisticProperties(
                null,
                null,
                agreementLiquidatedV2Event.address.toHex(),
                agreementLiquidatedV2Event.block.timestamp,
                agreementLiquidatedV2Event.block.number,
                0, // totalNumberOfActiveStreams
                0, // totalCFANumberOfActiveStreams
                0, // totalGDANumberOfActiveStreams
                0, // totalNumberOfClosedStreams
                0, // totalCFANumberOfClosedStreams
                0, // totalGDANumberOfClosedStreams
                0, // totalNumberOfIndexes
                0, // totalNumberOfActiveIndexes
                0, // totalSubscriptionsWithUnits
                0, // totalApprovedSubscriptions
                BIG_INT_ZERO, // totalDeposit
                BIG_INT_ZERO, // totalCFADeposit
                BIG_INT_ZERO, // totalGDADeposit
                BIG_INT_ZERO, // totalOutflowRate
                BIG_INT_ZERO, // totalCFAOutflowRate
                BIG_INT_ZERO, // totalGDAOutflowRate
                BIG_INT_ZERO, // totalAmountStreamedUntilUpdatedAt
                BIG_INT_ZERO, // totalCFAAmountStreamedUntilUpdatedAt
                BIG_INT_ZERO, // totalAmountTransferredUntilUpdatedAt
                BIG_INT_ZERO, // totalAmountDistributedUntilUpdatedAt
                BIG_INT_ZERO, // totalSupply = 0
                3, // totalNumberOfAccounts
                3 // totalNumberOfHolders
            );
        });

        test("handleTokenUpgraded() - Should create a new TokenUpgradedEvent entity", () => {
            const account = alice;
            const amount = BigInt.fromI32(100);

            const tokenUpgradedEvent = createTokenUpgradedEvent(
                account,
                amount,
            );

            mockedGetHost(tokenUpgradedEvent.address.toHex());

            handleTokenUpgraded(tokenUpgradedEvent);

            const id = assertEventBaseProperties(
                tokenUpgradedEvent,
                "TokenUpgraded"
            );
            assert.fieldEquals("TokenUpgradedEvent", id, "account", account);
            assert.fieldEquals("TokenUpgradedEvent", id, "amount", amount.toString());
        });

        test("handleTokenDowngraded() - Should create a new TokenDowngradedEvent entity", () => {
            const account = alice;
            const amount = BigInt.fromI32(100);

            const tokenDowngradedEvent = createTokenDowngradedEvent(
                account,
                amount,
            );

            mockedGetHost(tokenDowngradedEvent.address.toHex());

            handleTokenDowngraded(tokenDowngradedEvent);

            const id = assertEventBaseProperties(
                tokenDowngradedEvent,
                "TokenDowngraded"
            );
            assert.fieldEquals("TokenDowngradedEvent", id, "account", account);
            assert.fieldEquals("TokenDowngradedEvent", id, "amount", amount.toString());
        });

        test("handleApproval() - Should create a new ApprovalEvent entity", () => {
            const owner = alice;
            const spender = bob;
            const value = BigInt.fromI32(100);

            const superTokenApprovalEvent = createSuperTokenApprovalEvent(
                owner,
                spender,
                value
            );

            handleApproval(superTokenApprovalEvent);

            const id = assertEventBaseProperties(
                superTokenApprovalEvent,
                "Approval"
            );
            assert.fieldEquals("ApprovalEvent", id, "owner", owner);
            assert.fieldEquals("ApprovalEvent", id, "to", spender);
            assert.fieldEquals("ApprovalEvent", id, "amount", value.toString());
        });

        test("handleTransfer() - Should create a new TransferEvent entity", () => {
            const from = alice;
            const to = bob;
            const value = BigInt.fromI32(100);

            const transferEvent = createTransferEvent(
                from,
                to,
                value
            );

            handleTransfer(transferEvent);

            const id = assertEventBaseProperties(
                transferEvent,
                "Transfer"
            );
            assert.fieldEquals("TransferEvent", id, "from", from);
            assert.fieldEquals("TransferEvent", id, "to", to);
            assert.fieldEquals("TransferEvent", id, "value", value.toString());
            assertTokenStatisticProperties(
                null,
                null,
                transferEvent.address.toHex(),
                transferEvent.block.timestamp,
                transferEvent.block.number,
                0, // totalNumberOfActiveStreams
                0, // totalCFANumberOfActiveStreams
                0, // totalGDANumberOfActiveStreams
                0, // totalNumberOfClosedStreams
                0, // totalCFANumberOfClosedStreams
                0, // totalGDANumberOfClosedStreams
                0, // totalNumberOfIndexes
                0, // totalNumberOfActiveIndexes
                0, // totalSubscriptionsWithUnits
                0, // totalApprovedSubscriptions
                BIG_INT_ZERO, // totalDeposit
                BIG_INT_ZERO, // totalCFADeposit
                BIG_INT_ZERO, // totalGDADeposit
                BIG_INT_ZERO, // totalOutflowRate
                BIG_INT_ZERO, // totalCFAOutflowRate
                BIG_INT_ZERO, // totalGDAOutflowRate
                BIG_INT_ZERO, // totalAmountStreamedUntilUpdatedAt
                BIG_INT_ZERO, // totalCFAAmountStreamedUntilUpdatedAt
                value, // totalAmountTransferredUntilUpdatedAt
                BIG_INT_ZERO, // totalAmountDistributedUntilUpdatedAt
                BIG_INT_ZERO, // totalSupply = 0
                2, // totalNumberOfAccounts,
                2 // totalNumberOfHolders
            );
        });

        test("handleSent() - Should create a new SentEvent entity", () => {
            const operator = alice;
            const from = alice;
            const to = bob;
            const amount = BigInt.fromI32(100);
            const data = stringToBytes("");
            const operatorData = stringToBytes("");

            const sentEvent = createSentEvent(
                operator,
                from,
                to,
                amount,
                data,
                operatorData
            );

            mockedGetHost(sentEvent.address.toHex());

            handleSent(sentEvent);

            const id = assertEventBaseProperties(
                sentEvent,
                "Sent"
            );
            assert.fieldEquals("SentEvent", id, "operator", operator);
            assert.fieldEquals("SentEvent", id, "from", from);
            assert.fieldEquals("SentEvent", id, "to", to);
            assert.fieldEquals("SentEvent", id, "amount", amount.toString());
            assert.fieldEquals("SentEvent", id, "data", data.toHexString());
            assert.fieldEquals("SentEvent", id, "operatorData", operatorData.toHexString());
        });

        test("handleBurned() - Should create a new BurnedEvent entity", () => {
            const operator = alice;
            const from = bob;
            const amount = BigInt.fromI32(100);
            const data = stringToBytes("");
            const operatorData = stringToBytes("");

            const burnedEvent = createBurnedEvent(
                operator,
                from,
                amount,
                data,
                operatorData
            );

            handleBurned(burnedEvent);

            const id = assertEventBaseProperties(burnedEvent, "Burned");
            assert.fieldEquals("BurnedEvent", id, "operator", operator);
            assert.fieldEquals("BurnedEvent", id, "from", from);
            assert.fieldEquals("BurnedEvent", id, "amount", amount.toString());
            assert.fieldEquals("BurnedEvent", id, "data", data.toHexString());
            assert.fieldEquals(
                "BurnedEvent",
                id,
                "operatorData",
                operatorData.toHexString()
            );
        });

        test("handleMinted() - Should create a new MintedEvent entity", () => {
            const operator = alice;
            const to = bob;
            const amount = BigInt.fromI32(100);
            const data = stringToBytes("");
            const operatorData = stringToBytes("");

            const mintedEvent = createMintedEvent(
                operator,
                to,
                amount,
                data,
                operatorData
            );

            handleMinted(mintedEvent);

            const id = assertEventBaseProperties(mintedEvent, "Minted");
            assert.fieldEquals("MintedEvent", id, "operator", operator);
            assert.fieldEquals("MintedEvent", id, "to", to);
            assert.fieldEquals("MintedEvent", id, "amount", amount.toString());
            assert.fieldEquals("MintedEvent", id, "data", data.toHexString());
            assert.fieldEquals(
                "MintedEvent",
                id,
                "operatorData",
                operatorData.toHexString()
            );
        });

        test("TokenStatistic::totalNumberOfHolders should decrease its count when a user transfers tokens and the balance reaches 0.", () => {
            const from = alice;
            const to = bob;
            const value = BigInt.fromI32(100);

            const transferEvent = createTransferEvent(
                from,
                to,
                value
            );

            handleTransfer(transferEvent);

            const id = assertEventBaseProperties(
                transferEvent,
                "Transfer"
            );
            assert.fieldEquals("TransferEvent", id, "from", from);
            assert.fieldEquals("TransferEvent", id, "to", to);
            assert.fieldEquals("TransferEvent", id, "value", value.toString());

            assertTokenStatisticProperties(
                null,
                null,
                transferEvent.address.toHex(),
                transferEvent.block.timestamp,
                transferEvent.block.number,
                0, // totalNumberOfActiveStreams
                0, // totalCFANumberOfActiveStreams
                0, // totalGDANumberOfActiveStreams
                0, // totalNumberOfClosedStreams
                0, // totalCFANumberOfClosedStreams
                0, // totalGDANumberOfClosedStreams
                0, // totalNumberOfIndexes
                0, // totalNumberOfActiveIndexes
                0, // totalSubscriptionsWithUnits
                0, // totalApprovedSubscriptions
                BIG_INT_ZERO, // totalDeposit
                BIG_INT_ZERO, // totalCFADeposit
                BIG_INT_ZERO, // totalGDADeposit
                BIG_INT_ZERO, // totalOutflowRate
                BIG_INT_ZERO, // totalCFAOutflowRate
                BIG_INT_ZERO, // totalGDAOutflowRate
                BIG_INT_ZERO, // totalAmountStreamedUntilUpdatedAt
                BIG_INT_ZERO, // totalCFAAmountStreamedUntilUpdatedAt
                value, // totalAmountTransferredUntilUpdatedAt
                BIG_INT_ZERO, // totalAmountDistributedUntilUpdatedAt
                BIG_INT_ZERO, // totalSupply = 0
                2, // totalNumberOfAccounts,
                2 // totalNumberOfHolders
            );


            const secondTransferEvent = createTransferEvent(
                from,
                to,
                value
            );

            mockedRealtimeBalanceOf(
                secondTransferEvent.address.toHex(),
                from,
                secondTransferEvent.block.timestamp,
                BIG_INT_ZERO,
                BIG_INT_ZERO,
                BIG_INT_ZERO
            );

            handleTransfer(secondTransferEvent);

            assertTokenStatisticProperties(
                null,
                null,
                secondTransferEvent.address.toHex(),
                secondTransferEvent.block.timestamp,
                secondTransferEvent.block.number,
                0, // totalNumberOfActiveStreams
                0, // totalCFANumberOfActiveStreams
                0, // totalGDANumberOfActiveStreams
                0, // totalNumberOfClosedStreams
                0, // totalCFANumberOfClosedStreams
                0, // totalGDANumberOfClosedStreams
                0, // totalNumberOfIndexes
                0, // totalNumberOfActiveIndexes
                0, // totalSubscriptionsWithUnits
                0, // totalApprovedSubscriptions
                BIG_INT_ZERO, // totalDeposit
                BIG_INT_ZERO, // totalCFADeposit
                BIG_INT_ZERO, // totalGDADeposit
                BIG_INT_ZERO, // totalOutflowRate
                BIG_INT_ZERO, // totalCFAOutflowRate
                BIG_INT_ZERO, // totalGDAOutflowRate
                BIG_INT_ZERO, // totalAmountStreamedUntilUpdatedAt
                BIG_INT_ZERO, // totalCFAAmountStreamedUntilUpdatedAt
                value.times(BigInt.fromI32(2)), // totalAmountTransferredUntilUpdatedAt
                BIG_INT_ZERO, // totalAmountDistributedUntilUpdatedAt
                BIG_INT_ZERO, // totalSupply = 100
                2, // totalNumberOfAccounts,
                1 // totalNumberOfHolders
            );
        });
    });

    describe("Higher Order Entity Mapping Tests", () => {
        beforeEach(() => {
            clearStore();
        });

        test("handleBurned() - Should create a new TokenStatistic entity", () => {
            const operator = alice;
            const from = bob;
            const amount = BigInt.fromI32(100);
            const data = stringToBytes("");
            const operatorData = stringToBytes("");

            const burnedEvent = createBurnedEvent(
                operator,
                from,
                amount,
                data,
                operatorData
            );

            handleBurned(burnedEvent);
            assertEmptyTokenStatisticProperties(
                null,
                null,
                burnedEvent.address.toHex(),
                burnedEvent.block.timestamp,
                burnedEvent.block.number,
                amount.neg() // totalSupply = -100 (not possible in practice)
            );
        });

        test("handleMinted() - Should create a new TokenStatistic entity", () => {
            const operator = alice;
            const to = bob;
            const amount = BigInt.fromI32(100);
            const data = stringToBytes("");
            const operatorData = stringToBytes("");

            const mintedEvent = createMintedEvent(
                operator,
                to,
                amount,
                data,
                operatorData
            );

            handleMinted(mintedEvent);
            assertEmptyTokenStatisticProperties(
                null,
                null,
                mintedEvent.address.toHex(),
                mintedEvent.block.timestamp,
                mintedEvent.block.number,
                amount // totalSupply = 100
            );
        });
    });
});
