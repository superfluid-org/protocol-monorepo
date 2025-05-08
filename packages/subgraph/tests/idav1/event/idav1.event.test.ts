import { Address, BigInt } from "@graphprotocol/graph-ts";
import { assert, beforeEach, clearStore, describe, test } from "matchstick-as";
import {
    handleIndexCreated,
    handleIndexDistributionClaimed,
    handleIndexSubscribed,
    handleIndexUnitsUpdated,
    handleIndexUnsubscribed,
    handleIndexUpdated,
    handleSubscriptionApproved,
    handleSubscriptionDistributionClaimed,
    handleSubscriptionRevoked,
    handleSubscriptionUnitsUpdated,
} from "../../../src/mappings/idav1";
import { BIG_INT_ZERO, getIndexID, ZERO_ADDRESS } from "../../../src/utils";
import { assertIDAEventBaseProperties, assertIDAIndexEventBaseProperties } from "../../assertionHelpers";
import { alice, bob, DEFAULT_DECIMALS, FAKE_INITIAL_BALANCE, maticXAddress, maticXName, maticXSymbol, resolverAddress } from "../../constants";
import { stringToBytes } from "../../converters";
import { mockedGetAppManifest, mockedGetHost, mockedHandleSuperTokenInitRPCCalls, mockedRealtimeBalanceOf, mockedResolverGet } from "../../mockedFunctions";
import {
    createIndexCreatedEvent,
    createIndexDistributionClaimedEvent,
    createIndexSubscribedEvent,
    createIndexUnitsUpdatedEvent,
    createIndexUnsubscribedEvent,
    createIndexUpdatedEvent,
    createSubscriptionApprovedEvent,
    createSubscriptionDistributionClaimedEvent,
    createSubscriptionRevokedEvent,
    createSubscriptionUnitsUpdatedEvent,
} from "../idav1.helper";

// NOTE: We use MATICx as the default token for the tests
const superToken = maticXAddress;

describe("InstantDistributionV1 Event Entity Unit Tests", () => {
    beforeEach(() => {
        clearStore();
    });

    test("handleIndexCreated() - Should create a new IndexCreatedEvent entity", () => {
        const eventName = "IndexCreated";
        const publisher = alice;
        const indexId = BigInt.fromI32(1);
        const userData = stringToBytes("");

        const indexCreatedEvent = createIndexCreatedEvent(
            superToken,
            publisher,
            indexId,
            userData
        );

        mockedGetHost(superToken);
        mockedHandleSuperTokenInitRPCCalls(
            superToken,
            DEFAULT_DECIMALS,
            ZERO_ADDRESS,
            maticXName,
            maticXSymbol
        );

        // getOrInitIndex(event) => getOrInitAccount(publisher) => host.try_getAppManifest(sender)
        mockedGetAppManifest(publisher, false, false, BIG_INT_ZERO);

        // updateATSStreamedAndBalanceUntilUpdatedAt(publisher, token, block, null) => updateATSBalanceAndUpdatedAt(ats, block, balanceDelta) =>
        // token.realtimeBalanceOf(account, block.timestamp)
        mockedRealtimeBalanceOf(
            superToken,
            publisher,
            indexCreatedEvent.block.timestamp,
            BIG_INT_ZERO,
            BIG_INT_ZERO,
            BIG_INT_ZERO
        );

        handleIndexCreated(indexCreatedEvent);

        assertIDAIndexEventBaseProperties(
            indexCreatedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher,
            userData.toHexString()
        );
    });

    test("handleIndexDistributionClaimed() - Should create a new IndexDistributionClaimedEvent entity", () => {
        const eventName = "IndexDistributionClaimed";
        const publisher = alice;
        const subscriber = bob;
        const indexId = BigInt.fromI32(1);
        const amount = BigInt.fromI32(100);

        const indexDistributionClaimedEvent = createIndexDistributionClaimedEvent(
            superToken,
            publisher,
            indexId,
            subscriber,
            amount
        );

        handleIndexDistributionClaimed(indexDistributionClaimedEvent);

        const indexEntityId = getIndexID(
            Address.fromString(publisher),
            Address.fromString(superToken),
            indexId
        );

        const id = assertIDAEventBaseProperties(
            indexDistributionClaimedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher
        );
        assert.fieldEquals("IndexDistributionClaimedEvent", id, "subscriber", subscriber);
        assert.fieldEquals("IndexDistributionClaimedEvent", id, "amount", amount.toString());
        assert.fieldEquals("IndexDistributionClaimedEvent", id, "index", indexEntityId);
    });

    test("handleIndexUpdated() - Should create a new IndexUpdatedEvent entity", () => {
        const eventName = "IndexUpdated";
        const publisher = alice;
        const oldIndexValue = BigInt.fromI32(0);
        const newIndexValue = BigInt.fromI32(100);
        const totalUnitsPending = BigInt.fromI32(50);
        const totalUnitsApproved = BigInt.fromI32(50);
        const indexId = BigInt.fromI32(1);
        const userData = stringToBytes("");

        const indexUpdatedEvent = createIndexUpdatedEvent(
            superToken,
            publisher,
            indexId,
            oldIndexValue,
            newIndexValue,
            totalUnitsPending,
            totalUnitsApproved,
            userData
        );

        handleIndexUpdated(indexUpdatedEvent);

        const id = assertIDAIndexEventBaseProperties(
            indexUpdatedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher,
            userData.toHexString()
        );
        assert.fieldEquals("IndexUpdatedEvent", id, "oldIndexValue", oldIndexValue.toString());
        assert.fieldEquals("IndexUpdatedEvent", id, "newIndexValue", newIndexValue.toString());
        assert.fieldEquals("IndexUpdatedEvent", id, "totalUnitsPending", totalUnitsPending.toString());
        assert.fieldEquals("IndexUpdatedEvent", id, "totalUnitsApproved", totalUnitsApproved.toString());
    });
    
    test("handleIndexSubscribed() - Should create a new IndexSubscribedEvent entity", () => {
        const eventName = "IndexSubscribed";
        const publisher = alice;
        const subscriber = bob;
        const indexId = BigInt.fromI32(1);
        const userData = stringToBytes("");

        const indexSubscribedEvent = createIndexSubscribedEvent(
            superToken,
            publisher,
            indexId,
            subscriber,
            userData
        );

        handleIndexSubscribed(indexSubscribedEvent);

        const id = assertIDAIndexEventBaseProperties(
            indexSubscribedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher,
            userData.toHexString()
        );
        assert.fieldEquals("IndexSubscribedEvent", id, "subscriber", subscriber);
    });

    test("handleIndexUnitsUpdated() - Should create a new IndexUnitsUpdatedEvent entity", () => {
        const eventName = "IndexUnitsUpdated";
        const publisher = alice;
        const subscriber = bob;
        const oldUnits = BigInt.fromI32(0);
        const units = BigInt.fromI32(100);
        const indexId = BigInt.fromI32(1);
        const userData = stringToBytes("");

        const indexUnitsUpdatedEvent = createIndexUnitsUpdatedEvent(
            superToken,
            publisher,
            indexId,
            subscriber,
            units,
            userData
        );

        // getOrInitIndex(event) => getOrInitAccount(publisher) => host.try_getAppManifest(sender)
        mockedGetAppManifest(publisher, false, false, BIG_INT_ZERO);
        mockedGetAppManifest(subscriber, false, false, BIG_INT_ZERO);

        handleIndexUnitsUpdated(indexUnitsUpdatedEvent);

        const id = assertIDAIndexEventBaseProperties(
            indexUnitsUpdatedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher,
            userData.toHexString()
        );

        assert.fieldEquals("IndexUnitsUpdatedEvent", id, "subscriber", subscriber);
        assert.fieldEquals("IndexUnitsUpdatedEvent", id, "units", units.toString());
        assert.fieldEquals("IndexUnitsUpdatedEvent", id, "oldUnits", oldUnits.toString());
    });

    test("handleIndexUnsubscribed() - Should create a new IndexUnsubscribedEvent entity", () => {
        const eventName = "IndexUnsubscribed";
        const publisher = alice;
        const subscriber = bob;
        const indexId = BigInt.fromI32(1);
        const userData = stringToBytes("");

        const indexUnsubscribedEvent = createIndexUnsubscribedEvent(
            superToken,
            publisher,
            indexId,
            subscriber,
            userData
        );

        handleIndexUnsubscribed(indexUnsubscribedEvent);

        const id = assertIDAIndexEventBaseProperties(
            indexUnsubscribedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher,
            userData.toHexString()
        );
        assert.fieldEquals("IndexUnsubscribedEvent", id, "subscriber", subscriber);
    });

    test("handleSubscriptionApproved() - Should create a new SubscriptionApprovedEvent entity", () => {
        const eventName = "SubscriptionApproved";
        const publisher = alice;
        const subscriber = bob;
        const indexId = BigInt.fromI32(1);
        const userData = stringToBytes("");

        const subscriptionApprovedEvent = createSubscriptionApprovedEvent(
            superToken,
            subscriber,
            publisher,
            indexId,
            userData
        );

        mockedResolverGet(resolverAddress, "supertokens.v1.MATICx", ZERO_ADDRESS.toHexString());

        mockedRealtimeBalanceOf(
            superToken,
            subscriber,
            subscriptionApprovedEvent.block.timestamp,
            FAKE_INITIAL_BALANCE,
            BIG_INT_ZERO,
            BIG_INT_ZERO
        );

        mockedRealtimeBalanceOf(
            superToken,
            publisher,
            subscriptionApprovedEvent.block.timestamp,
            FAKE_INITIAL_BALANCE,
            BIG_INT_ZERO,
            BIG_INT_ZERO
        );

        handleSubscriptionApproved(subscriptionApprovedEvent);

        const id = assertIDAEventBaseProperties(
            subscriptionApprovedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher
        );
        assert.fieldEquals("SubscriptionApprovedEvent", id, "subscriber", subscriber);
        assert.fieldEquals("SubscriptionApprovedEvent", id, "userData", userData.toHexString());
    });

    test("handleSubscriptionDistributionClaimed() - Should create a new SubscriptionDistributionClaimedEvent entity", () => {
        const eventName = "SubscriptionDistributionClaimed";
        const publisher = alice;
        const subscriber = bob;
        const indexId = BigInt.fromI32(1);
        const amount = BigInt.fromI32(100);

        const subscriptionDistributionClaimedEvent = createSubscriptionDistributionClaimedEvent(
            superToken,
            subscriber,
            publisher,
            indexId,
            amount
        );

        handleSubscriptionDistributionClaimed(subscriptionDistributionClaimedEvent);

        const id = assertIDAEventBaseProperties(
            subscriptionDistributionClaimedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher
        );
        assert.fieldEquals("SubscriptionDistributionClaimedEvent", id, "subscriber", subscriber);
        assert.fieldEquals("SubscriptionDistributionClaimedEvent", id, "amount", amount.toString());
    });

    test("handleSubscriptionRevoked() - Should create a new SubscriptionRevokedEvent entity", () => {
        const eventName = "SubscriptionRevoked";
        const publisher = alice;
        const subscriber = bob;
        const indexId = BigInt.fromI32(1);
        const userData = stringToBytes("");

        const subscriptionRevokedEvent = createSubscriptionRevokedEvent(
            superToken,
            subscriber,
            publisher,
            indexId,
            userData
        );

        handleSubscriptionRevoked(subscriptionRevokedEvent);

        const id = assertIDAEventBaseProperties(
            subscriptionRevokedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher
        );
        assert.fieldEquals("SubscriptionRevokedEvent", id, "subscriber", subscriber);
        assert.fieldEquals("SubscriptionRevokedEvent", id, "userData", userData.toHexString());
    });

    test("handleSubscriptionUnitsUpdated() - Should create a new SubscriptionUnitsUpdatedEvent entity", () => {
        const eventName = "SubscriptionUnitsUpdated";
        const publisher = alice;
        const subscriber = bob;
        const indexId = BigInt.fromI32(1);
        const units = BigInt.fromI32(100);
        const userData = stringToBytes("");

        const subscriptionUnitsUpdatedEvent = createSubscriptionUnitsUpdatedEvent(
            superToken,
            subscriber,
            publisher,
            indexId,
            units,
            userData
        );

        handleSubscriptionUnitsUpdated(subscriptionUnitsUpdatedEvent);

        const id = assertIDAEventBaseProperties(
            subscriptionUnitsUpdatedEvent,
            eventName,
            superToken,
            indexId.toString(),
            publisher
        );

        assert.fieldEquals("SubscriptionUnitsUpdatedEvent", id, "subscriber", subscriber);
        assert.fieldEquals("SubscriptionUnitsUpdatedEvent", id, "userData", userData.toHexString());
    });
});
