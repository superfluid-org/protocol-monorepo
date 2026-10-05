// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";
import {
    IInstantDistributionAgreementV1
} from "../../../contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";
import { InstantDistributionAgreementV1 } from "../../../contracts/agreements/InstantDistributionAgreementV1.sol";

/// @notice Soft-freeze and per-deployment slot-cap tests for IDA.
/// @dev Foundry framework deploys unfrozen IDA with max=256. Production freeze/cap is applied
///      by upgrading logic (same path as deploy-framework.js).
contract InstantDistributionAgreementV1FreezeTest is FoundrySuperfluidTester {
    bytes internal constant EMPTY = "";
    uint32 internal constant INDEX_A = 0;
    uint32 internal constant INDEX_B = 1;
    uint128 internal constant ONE_UNIT = 1;
    uint256 internal constant DIST_AMOUNT = 100e18;

    constructor() FoundrySuperfluidTester(3) { }

    function _idaCall(bytes memory callData) internal {
        sf.host.callAgreement(sf.ida, callData, EMPTY);
    }

    function _createIndex(address publisher, uint32 indexId) internal {
        vm.startPrank(publisher);
        _idaCall(abi.encodeCall(sf.ida.createIndex, (superToken, indexId, EMPTY)));
        vm.stopPrank();
    }

    function _updateSubscription(address publisher, uint32 indexId, address subscriber, uint128 units) internal {
        vm.startPrank(publisher);
        _idaCall(abi.encodeCall(sf.ida.updateSubscription, (superToken, indexId, subscriber, units, EMPTY)));
        vm.stopPrank();
    }

    function _approve(address subscriber, address publisher, uint32 indexId) internal {
        vm.startPrank(subscriber);
        _idaCall(abi.encodeCall(sf.ida.approveSubscription, (superToken, publisher, indexId, EMPTY)));
        vm.stopPrank();
    }

    function _distribute(address publisher, uint32 indexId, uint256 amount) internal {
        vm.startPrank(publisher);
        _idaCall(abi.encodeCall(sf.ida.distribute, (superToken, indexId, amount, EMPTY)));
        vm.stopPrank();
    }

    function _upgradeIda(bool frozen, uint32 maxSubs) internal {
        // Foundry's test host is non-upgradable, so governance.updateAgreementClass reverts.
        // Etching the deployed IDA address with new logic bytecode is equivalent to a UUPS
        // logic swap: IDA is stateless, all index/subscription data lives on the Super Token.
        InstantDistributionAgreementV1 newLogic = new InstantDistributionAgreementV1(sf.host, frozen, maxSubs);
        vm.etch(address(sf.ida), address(newLogic).code);
    }

    function _expectFrozen(bytes memory callData) internal {
        vm.expectRevert(IInstantDistributionAgreementV1.IDA_NEW_ACTIVITY_FROZEN.selector);
        _idaCall(callData);
    }

    function testDefaultTestDeploymentIsUnfrozenWith256Slots() public view {
        assertFalse(sf.ida.NEW_ACTIVITY_FROZEN());
        assertEq(sf.ida.MAX_NUM_SUBSCRIPTIONS(), 256);
    }

    function testConstructorRejectsInvalidMax() public {
        vm.expectRevert(IInstantDistributionAgreementV1.IDA_INVALID_MAX_NUM_SUBSCRIPTIONS.selector);
        new InstantDistributionAgreementV1(sf.host, false, 0);

        vm.expectRevert(IInstantDistributionAgreementV1.IDA_INVALID_MAX_NUM_SUBSCRIPTIONS.selector);
        new InstantDistributionAgreementV1(sf.host, false, 257);
    }

    function testFreezeRevertsNewActivityAndKeepsUnwind() public {
        _createIndex(alice, INDEX_A);
        _updateSubscription(alice, INDEX_A, bob, ONE_UNIT);
        _updateSubscription(alice, INDEX_A, admin, ONE_UNIT);
        _approve(admin, alice, INDEX_A);
        _distribute(alice, INDEX_A, DIST_AMOUNT);

        (,,, uint256 pendingBob) = sf.ida.getSubscription(superToken, alice, INDEX_A, bob);
        assertEq(pendingBob, DIST_AMOUNT / 2, "pending should be half of distribution");

        (int256 bobAvailBefore,,,) = superToken.realtimeBalanceOfNow(bob);
        (, uint256 aliceDepositBefore,,) = superToken.realtimeBalanceOfNow(alice);
        assertGt(aliceDepositBefore, 0, "publisher should hold pending deposit");

        _upgradeIda(true, 256);
        assertTrue(sf.ida.NEW_ACTIVITY_FROZEN());
        assertEq(sf.ida.MAX_NUM_SUBSCRIPTIONS(), 256);
        assertEq(sf.ida.agreementType(), keccak256("org.superfluid-finance.agreements.InstantDistributionAgreement.v1"));

        vm.startPrank(alice);
        _expectFrozen(abi.encodeCall(sf.ida.createIndex, (superToken, INDEX_B, EMPTY)));
        _expectFrozen(abi.encodeCall(sf.ida.updateIndex, (superToken, INDEX_A, uint128(1e18), EMPTY)));
        _expectFrozen(abi.encodeCall(sf.ida.distribute, (superToken, INDEX_A, uint256(1e18), EMPTY)));
        _expectFrozen(abi.encodeCall(sf.ida.updateSubscription, (superToken, INDEX_A, bob, uint128(2), EMPTY)));
        vm.stopPrank();

        // Unwind: claim pending for bob (anyone can claim)
        vm.prank(alice);
        _idaCall(abi.encodeCall(sf.ida.claim, (superToken, alice, INDEX_A, bob, EMPTY)));

        (,,, uint256 pendingBobAfter) = sf.ida.getSubscription(superToken, alice, INDEX_A, bob);
        assertEq(pendingBobAfter, 0);

        (int256 bobAvailAfter,,,) = superToken.realtimeBalanceOfNow(bob);
        assertEq(uint256(int256(bobAvailAfter - bobAvailBefore)), DIST_AMOUNT / 2);

        (, uint256 aliceDepositAfterClaim,,) = superToken.realtimeBalanceOfNow(alice);
        assertLt(aliceDepositAfterClaim, aliceDepositBefore);

        // Unwind: approve remaining pending (bob already claimed; re-create pending via... bob is still pending 0)
        // admin is already approved — revoke then publisher-delete
        vm.prank(admin);
        _idaCall(abi.encodeCall(sf.ida.revokeSubscription, (superToken, alice, INDEX_A, EMPTY)));

        vm.prank(alice);
        _idaCall(abi.encodeCall(sf.ida.deleteSubscription, (superToken, alice, INDEX_A, bob, EMPTY)));

        (bool bobExists,,,) = sf.ida.getSubscription(superToken, alice, INDEX_A, bob);
        assertFalse(bobExists);

        // Approved subscriber dynamic balance still spends after freeze (admin received half)
        (int256 adminAvail,,,) = superToken.realtimeBalanceOfNow(admin);
        assertGe(adminAvail, int256(DIST_AMOUNT / 2));
    }

    function testConsecutiveFrozenUpgradesStayFrozen() public {
        _createIndex(alice, INDEX_A);
        _upgradeIda(true, 256);
        _upgradeIda(true, 256);
        assertTrue(sf.ida.NEW_ACTIVITY_FROZEN());
        vm.prank(alice);
        _expectFrozen(abi.encodeCall(sf.ida.createIndex, (superToken, INDEX_B, EMPTY)));
    }

    function testMax32AllowsThirtyTwoApprovalsAndRevertsThirtyThird() public {
        _upgradeIda(false, 32);
        assertFalse(sf.ida.NEW_ACTIVITY_FROZEN());
        assertEq(sf.ida.MAX_NUM_SUBSCRIPTIONS(), 32);

        for (uint32 i = 0; i < 32; ++i) {
            _createIndex(alice, i);
            _updateSubscription(alice, i, bob, ONE_UNIT);
            _approve(bob, alice, i);
        }

        (address[] memory publishers,,) = sf.ida.listSubscriptions(superToken, bob);
        assertEq(publishers.length, 32);

        _createIndex(alice, 32);
        _updateSubscription(alice, 32, bob, ONE_UNIT);
        vm.startPrank(bob);
        vm.expectRevert(IInstantDistributionAgreementV1.IDA_TOO_MANY_SUBSCRIPTIONS.selector);
        _idaCall(abi.encodeCall(sf.ida.approveSubscription, (superToken, alice, uint32(32), EMPTY)));
        vm.stopPrank();

        // Existing 32 approved slots still contribute to realtime balance after a distribution
        _distribute(alice, 0, DIST_AMOUNT);
        (int256 bobDynamic, uint256 deposit,) = sf.ida.realtimeBalanceOf(superToken, bob, block.timestamp);
        assertEq(uint256(bobDynamic), DIST_AMOUNT);
        assertEq(deposit, 0);
    }

    function testApproveAfterFreezeIsBlockedAndPendingBalanceRemains() public {
        _createIndex(alice, INDEX_A);
        _updateSubscription(alice, INDEX_A, bob, ONE_UNIT);
        _distribute(alice, INDEX_A, DIST_AMOUNT);

        (int256 bobBefore,,,) = superToken.realtimeBalanceOfNow(bob);
        _upgradeIda(true, 256);

        vm.startPrank(bob);
        vm.expectRevert(IInstantDistributionAgreementV1.IDA_NEW_ACTIVITY_FROZEN.selector);
        _idaCall(abi.encodeCall(sf.ida.approveSubscription, (superToken, alice, INDEX_A, EMPTY)));
        vm.stopPrank();

        (bool exist, bool approved, uint128 units, uint256 pending) =
            sf.ida.getSubscription(superToken, alice, INDEX_A, bob);
        assertTrue(exist);
        assertFalse(approved);
        assertEq(units, ONE_UNIT);
        assertEq(pending, DIST_AMOUNT);

        (int256 bobAfter,,,) = superToken.realtimeBalanceOfNow(bob);
        assertEq(bobAfter, bobBefore);
    }

    function testFrozenApprovalCannotAllocateNewSlot() public {
        _createIndex(alice, INDEX_A);
        _upgradeIda(true, 256);
        vm.startPrank(bob);
        vm.expectRevert(IInstantDistributionAgreementV1.IDA_NEW_ACTIVITY_FROZEN.selector);
        _idaCall(abi.encodeCall(sf.ida.approveSubscription, (superToken, alice, INDEX_A, EMPTY)));
        vm.stopPrank();
    }

    function testMax32CountsZeroUnitApprovalsAndReusesRevokedSlot() public {
        _upgradeIda(false, 32);
        for (uint32 i = 0; i < 32; ++i) {
            _createIndex(alice, i);
            _approve(bob, alice, i);
        }
        _createIndex(alice, 32);
        vm.startPrank(bob);
        vm.expectRevert(IInstantDistributionAgreementV1.IDA_TOO_MANY_SUBSCRIPTIONS.selector);
        _idaCall(abi.encodeCall(sf.ida.approveSubscription, (superToken, alice, uint32(32), EMPTY)));
        vm.stopPrank();

        vm.prank(bob);
        _idaCall(abi.encodeCall(sf.ida.revokeSubscription, (superToken, alice, 0, EMPTY)));
        _approve(bob, alice, 32);
        (address[] memory publishers,,) = sf.ida.listSubscriptions(superToken, bob);
        assertEq(publishers.length, 32);
    }

    function testLegacyApprovalsAboveNewCapRemainReadable() public {
        _upgradeIda(false, 256);
        for (uint32 i = 0; i < 33; ++i) {
            _createIndex(alice, i);
            _updateSubscription(alice, i, bob, ONE_UNIT);
            _approve(bob, alice, i);
        }
        _upgradeIda(false, 32);
        (address[] memory publishers,,) = sf.ida.listSubscriptions(superToken, bob);
        assertEq(publishers.length, 33);
        _distribute(alice, 32, DIST_AMOUNT);
        (int256 dynamicBalance,,) = sf.ida.realtimeBalanceOf(superToken, bob, block.timestamp);
        assertEq(uint256(dynamicBalance), DIST_AMOUNT);
        _createIndex(alice, 33);
        vm.startPrank(bob);
        vm.expectRevert(IInstantDistributionAgreementV1.IDA_TOO_MANY_SUBSCRIPTIONS.selector);
        _idaCall(abi.encodeCall(sf.ida.approveSubscription, (superToken, alice, uint32(33), EMPTY)));
        vm.stopPrank();
    }

    function testFuzzFrozenRevokedSlotCannotBeReused(uint32 indexId) public {
        _createIndex(alice, indexId);
        _approve(bob, alice, indexId);
        _upgradeIda(true, 256);
        vm.startPrank(bob);
        _idaCall(abi.encodeCall(sf.ida.revokeSubscription, (superToken, alice, indexId, EMPTY)));
        _expectFrozen(abi.encodeCall(sf.ida.approveSubscription, (superToken, alice, indexId, EMPTY)));
        vm.stopPrank();
        (address[] memory publishers,,) = sf.ida.listSubscriptions(superToken, bob);
        assertEq(publishers.length, 0);
    }

    function testFuzzPendingDistributionCanBeClaimedAfterFreeze(uint96 amountSeed) public {
        uint256 amount = bound(amountSeed, 1, DIST_AMOUNT);
        _createIndex(alice, INDEX_A);
        _updateSubscription(alice, INDEX_A, bob, ONE_UNIT);
        _distribute(alice, INDEX_A, amount);
        (int256 beforeBalance,,,) = superToken.realtimeBalanceOfNow(bob);
        _upgradeIda(true, 256);
        vm.prank(bob);
        _idaCall(abi.encodeCall(sf.ida.claim, (superToken, alice, INDEX_A, bob, EMPTY)));
        (int256 afterBalance,,,) = superToken.realtimeBalanceOfNow(bob);
        assertEq(afterBalance - beforeBalance, int256(amount));
        (,,, uint256 pending) = sf.ida.getSubscription(superToken, alice, INDEX_A, bob);
        assertEq(pending, 0);
        (, uint256 deposit,,) = superToken.realtimeBalanceOfNow(alice);
        assertEq(deposit, 0);
    }
}
