// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { FoundrySuperfluidTester } from "../../foundry/FoundrySuperfluidTester.t.sol";
import { ISuperfluidPool, SuperfluidPool } from "../../../contracts/agreements/gdav1/SuperfluidPool.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import { ISuperToken, SuperToken } from "../../../contracts/superfluid/SuperToken.sol";

/// @dev This contract includes test sequences discovered by echidna which broke invariants previously.
contract EchidnaTestCases is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    SuperfluidPool public currentPool;

    constructor() FoundrySuperfluidTester(6) { }

    function setUp() public override {
        super.setUp();
        vm.startPrank(alice);
        currentPool = SuperfluidPool(address(superToken.createPool(alice, poolConfig)));
        _addAccount(address(currentPool));
        vm.stopPrank();
    }

    function testDistributeFlowToDisconnectedMember(address member, uint64 units, int32 flowRate, bool useForwarder)
        public
    {
        vm.assume(member != address(0));
        vm.assume(flowRate > 0);

        _helperUpdateMemberUnits(currentPool, alice, member, units);

        _helperDistributeFlow(superToken, alice, alice, currentPool, flowRate, useForwarder);
    }

    function testLiquidationCase() public {
        int96 flowRate = 28880687301540251;
        uint256 warpTime = 70;

        _helperCreateFlow(superToken, alice, bob, flowRate);
        _helperTransferAll(superToken, alice, bob);
        vm.warp(block.timestamp + warpTime);
        _helperDeleteFlow(superToken, carol, alice, bob);
    }
}
