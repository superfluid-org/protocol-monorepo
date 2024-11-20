// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "../FoundrySuperfluidTester.t.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";

contract InstantDistributionAgreementV1IntegrationTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    constructor() FoundrySuperfluidTester(3) { }

    function testAlice2Bob(uint32 indexId, uint32 units, uint32 newIndexValue) public {
        vm.assume(units > 0);

        bool exist;
        uint128 indexValue;
        uint128 totalUnitsApproved;
        uint128 totalUnitsPending;

        // alice creates index
        _helperCreateIndex(superToken, alice, indexId);

        // alice updates subscription units for bob
        IDASubscriptionParams memory params =
            IDASubscriptionParams({ superToken: superToken, publisher: alice, subscriber: bob, indexId: indexId });

        _helperUpdateSubscriptionUnits(params, units);

        // alice distributes
        _helperUpdateIndexValue(superToken, alice, indexId, newIndexValue);
        (exist, indexValue, totalUnitsApproved, totalUnitsPending) = superToken.getIndex(alice, indexId);

        // bob subscribes to alice's index
        _helperApproveSubscription(params);

        _warpAndAssertAll(superToken);
    }

    function testRevertMaxNumberOFSubscriptionsASubscriberCanHave() public {
        uint32 maxNumSubs = sf.ida.MAX_NUM_SUBSCRIPTIONS();

        for (uint256 i; i < maxNumSubs; ++i) {
            vm.startPrank(alice);
            superToken.createIndex(uint32(i));
            superToken.updateSubscriptionUnits(uint32(i), bob, 1);
            vm.stopPrank();

            vm.startPrank(bob);
            superToken.approveSubscription(alice, uint32(i));
            vm.stopPrank();
        }

        (, uint32[] memory indexIds,) = superToken.listSubscriptions(bob);
        assertEq(indexIds.length, maxNumSubs, "IDAv1.t: subscriptions length mismatch");

        vm.startPrank(alice);
        superToken.createIndex(uint32(maxNumSubs));
        superToken.updateSubscriptionUnits(uint32(maxNumSubs), bob, 1);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert("SlotBitmap out of bound");
        superToken.approveSubscription(alice, uint32(maxNumSubs));
        vm.stopPrank();

        _warpAndAssertAll(superToken);
    }
}
