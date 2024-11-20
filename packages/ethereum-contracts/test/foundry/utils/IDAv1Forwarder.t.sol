// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IDAv1Forwarder } from "../../../contracts/utils/IDAv1Forwarder.sol";

contract IDAv1ForwarderIntegrationTest is FoundrySuperfluidTester {
    constructor() FoundrySuperfluidTester(3) { }

    function testIDAv1ForwarderCreateIndex(uint32 indexId, bytes memory userData) external {
        vm.startPrank(alice);
        sf.idaV1Forwarder.createIndex(superToken, indexId, userData);
        _helperAssertCreateIndex(superToken, alice, indexId);
        vm.stopPrank();
    }

    function testIDAv1ForwarderUpdateIndex(uint32 indexValue, bytes memory userData) external {
        uint128 units = 10;
        vm.assume(indexValue >= units);

        vm.startPrank(alice);
        sf.idaV1Forwarder.createIndex(superToken, 0, userData);
        _helperAssertCreateIndex(superToken, alice, 0);

        sf.idaV1Forwarder.updateSubscriptionUnits(superToken, 0, bob, units, userData);

        sf.idaV1Forwarder.updateIndex(superToken, 0, uint128(indexValue), userData);
        vm.stopPrank();

        (bool exist, uint128 indexValue_, uint128 totalUnitsApproved, uint128 totalUnitsPending) =
            sf.idaV1Forwarder.getIndex(superToken, alice, 0);
        assertTrue(exist, "testIDAv1ForwarderUpdateIndex: index should exist");
        assertEq(indexValue_, uint128(indexValue), "testIDAv1ForwarderUpdateIndex: index value mismatch");
        assertEq(totalUnitsApproved, 0, "testIDAv1ForwarderUpdateIndex: total approved units mismatch");
        assertEq(totalUnitsPending, units, "testIDAv1ForwarderUpdateIndex: total units pending mismatch");
    }

    function testIDAv1ForwarderDistribute(uint32 amount, bytes memory userData) external {
        uint128 units = 10;
        vm.assume(amount >= units);

        vm.startPrank(alice);
        sf.idaV1Forwarder.createIndex(superToken, 0, userData);
        _helperAssertCreateIndex(superToken, alice, 0);

        sf.idaV1Forwarder.updateSubscriptionUnits(superToken, 0, bob, units, userData);
        (, uint128 newIndexValue) = sf.idaV1Forwarder.calculateDistribution(superToken, alice, 0, uint128(amount));

        sf.idaV1Forwarder.distribute(superToken, 0, uint128(amount), userData);
        vm.stopPrank();

        (bool exist, uint128 indexValue_, uint128 totalUnitsApproved, uint128 totalUnitsPending) =
            sf.idaV1Forwarder.getIndex(superToken, alice, 0);
        assertTrue(exist, "testIDAv1ForwarderDistribute: index should exist");
        assertEq(indexValue_, newIndexValue, "testIDAv1ForwarderDistribute: index value mismatch");
        assertEq(totalUnitsApproved, 0, "testIDAv1ForwarderDistribute: total approved units mismatch");
        assertEq(totalUnitsPending, units, "testIDAv1ForwarderDistribute: total units pending mismatch");
    }

    function testIDAv1ForwarderApproveSubscription(address subscriber, uint128 units, bytes memory userData) external {
        vm.assume(units > 0);
        vm.assume(subscriber != address(0));
        vm.startPrank(alice);
        sf.idaV1Forwarder.createIndex(superToken, 0, userData);
        _helperAssertCreateIndex(superToken, alice, 0);

        sf.idaV1Forwarder.updateSubscriptionUnits(superToken, 0, subscriber, units, userData);
        vm.stopPrank();
        vm.startPrank(subscriber);
        sf.idaV1Forwarder.approveSubscription(superToken, alice, 0, userData);
        vm.stopPrank();

        (bool indexExists, uint128 indexValue, uint128 totalUnitsApproved, uint128 totalUnitsPending) =
            sf.idaV1Forwarder.getIndex(superToken, alice, 0);
        assertTrue(indexExists, "testIDAv1ForwarderApproveSubscription: index should exist");
        assertEq(indexValue, 0, "testIDAv1ForwarderApproveSubscription: index value mismatch");
        assertEq(totalUnitsApproved, units, "testIDAv1ForwarderApproveSubscription: total approved units mismatch");
        assertEq(totalUnitsPending, 0, "testIDAv1ForwarderApproveSubscription: total units pending mismatch");

        (bool subExists, bool approved, uint128 units_, uint256 pendingDistribution) =
            sf.idaV1Forwarder.getSubscription(superToken, alice, 0, subscriber);
        assertTrue(subExists, "testIDAv1ForwarderApproveSubscription: subscription should exist");
        assertTrue(approved, "testIDAv1ForwarderApproveSubscription: subscription should be approved");
        assertEq(units_, units, "testIDAv1ForwarderApproveSubscription: subscription units mismatch");
        assertEq(
            pendingDistribution, 0, "testIDAv1ForwarderApproveSubscription: subscription pending distribution mismatch"
        );
    }

    function testIDAv1ForwarderRevokeSubscription(address subscriber, uint128 units, bytes memory userData) external {
        vm.assume(units > 0);
        vm.assume(subscriber != address(0));
        vm.startPrank(alice);
        sf.idaV1Forwarder.createIndex(superToken, 0, userData);
        _helperAssertCreateIndex(superToken, alice, 0);

        sf.idaV1Forwarder.updateSubscriptionUnits(superToken, 0, subscriber, units, userData);
        vm.stopPrank();

        vm.startPrank(subscriber);
        sf.idaV1Forwarder.approveSubscription(superToken, alice, 0, userData);
        sf.idaV1Forwarder.revokeSubscription(superToken, alice, 0, userData);
        vm.stopPrank();

        (bool indexExists, uint128 indexValue, uint128 totalUnitsApproved, uint128 totalUnitsPending) =
            sf.idaV1Forwarder.getIndex(superToken, alice, 0);
        assertTrue(indexExists, "testIDAv1ForwarderRevokeSubscription: index should exist");
        assertEq(indexValue, 0, "testIDAv1ForwarderRevokeSubscription: index value mismatch");
        assertEq(totalUnitsApproved, 0, "testIDAv1ForwarderRevokeSubscription: total approved units mismatch");
        assertEq(totalUnitsPending, units, "testIDAv1ForwarderRevokeSubscription: total units pending mismatch");

        (bool subExists, bool approved, uint128 units_, uint256 pendingDistribution) =
            sf.idaV1Forwarder.getSubscription(superToken, alice, 0, subscriber);
        assertTrue(subExists, "testIDAv1ForwarderRevokeSubscription: subscription should exist");
        assertTrue(!approved, "testIDAv1ForwarderRevokeSubscription: subscription should not be approved");
        assertEq(units_, units, "testIDAv1ForwarderRevokeSubscription: subscription units mismatch");
        assertEq(
            pendingDistribution, 0, "testIDAv1ForwarderRevokeSubscription: subscription pending distribution mismatch"
        );
    }

    function testIDAv1ForwarderDeleteSubscription(address subscriber, uint128 units, bytes memory userData) external {
        vm.assume(units > 0);
        vm.assume(subscriber != address(0));
        vm.startPrank(alice);
        sf.idaV1Forwarder.createIndex(superToken, 0, userData);
        _helperAssertCreateIndex(superToken, alice, 0);

        sf.idaV1Forwarder.updateSubscriptionUnits(superToken, 0, subscriber, units, userData);
        sf.idaV1Forwarder.deleteSubscription(superToken, alice, 0, subscriber, userData);
        vm.stopPrank();

        (bool indexExists, uint128 indexValue, uint128 totalUnitsApproved, uint128 totalUnitsPending) =
            sf.idaV1Forwarder.getIndex(superToken, alice, 0);
        assertTrue(indexExists, "testIDAv1ForwarderDeleteSubscription: index should exist");
        assertEq(indexValue, 0, "testIDAv1ForwarderDeleteSubscription: index value mismatch");
        assertEq(totalUnitsApproved, 0, "testIDAv1ForwarderDeleteSubscription: total approved units mismatch");
        assertEq(totalUnitsPending, 0, "testIDAv1ForwarderDeleteSubscription: total units pending mismatch");

        (bool subExists, bool approved, uint128 units_, uint256 pendingDistribution) =
            sf.idaV1Forwarder.getSubscription(superToken, alice, 0, subscriber);
        assertTrue(!subExists, "testIDAv1ForwarderDeleteSubscription: subscription should not exist");
        assertTrue(!approved, "testIDAv1ForwarderDeleteSubscription: subscription should not be approved");
        assertEq(units_, 0, "testIDAv1ForwarderDeleteSubscription: subscription units mismatch");
        assertEq(
            pendingDistribution, 0, "testIDAv1ForwarderDeleteSubscription: subscription pending distribution mismatch"
        );
    }

    function testIDAv1ForwarderGetSubscriptionByID(
        address publisher,
        address subscriber,
        uint128 units,
        uint32 indexId,
        bytes memory userData
    ) external {
        vm.assume(subscriber != address(0));
        vm.assume(publisher != address(0));
        vm.assume(units > 0);

        vm.startPrank(publisher);
        sf.idaV1Forwarder.createIndex(superToken, indexId, userData);
        _helperAssertCreateIndex(superToken, publisher, indexId);
        sf.idaV1Forwarder.updateSubscriptionUnits(superToken, indexId, subscriber, units, userData);
        vm.stopPrank();

        bytes32 publisherId = sf.idaV1Forwarder.getPublisherId(publisher, indexId);
        bytes32 subscriptionId = sf.idaV1Forwarder.getSubscriptionId(subscriber, publisherId);
        (address publisher_, uint32 indexId_, bool approved, uint128 units_, uint256 pendingDistribution) =
            sf.idaV1Forwarder.getSubscriptionByID(superToken, subscriptionId);

        assertEq(publisher, publisher_, "testIDAv1ForwarderGetSubscriptionByID: publisher mismatch");
        assertEq(indexId, indexId_, "testIDAv1ForwarderGetSubscriptionByID: index ID mismatch");
        assertFalse(approved, "testIDAv1ForwarderGetSubscriptionByID: subscription should not be approved");
        assertEq(units, units_, "testIDAv1ForwarderGetSubscriptionByID: units mismatch");
        assertEq(pendingDistribution, 0, "testIDAv1ForwarderGetSubscriptionByID: pending distribution mismatch");
    }

    function testIDAv1ForwarderEmptyListSubscriptions(address subscriber) external view {
        vm.assume(subscriber != address(0));
        (address[] memory publishers, uint32[] memory indexIds, uint128[] memory unitsList) =
            sf.idaV1Forwarder.listSubscriptions(superToken, subscriber);
        assertEq(publishers.length, 0, "testIDAv1ForwarderEmptyListSubscriptions: publishers length mismatch");
        assertEq(indexIds.length, 0, "testIDAv1ForwarderEmptyListSubscriptions: index IDs length mismatch");
        assertEq(unitsList.length, 0, "testIDAv1ForwarderEmptyListSubscriptions: units length mismatch");
    }
}
