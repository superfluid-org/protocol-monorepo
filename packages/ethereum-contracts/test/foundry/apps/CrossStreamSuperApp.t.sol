// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ISuperfluid, ISuperToken } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { CFASuperAppBase } from "../../../contracts/apps/CFASuperAppBase.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import { ISuperToken } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";

import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";

import "forge-std/Test.sol";

using SuperTokenV1Library for ISuperToken;

/// @title CrossStreamSuperApp
/// @author Superfluid
/// @dev A super app used for testing "cross-stream" flows in callbacks
/// and its behavior surrounding the internal protocol accounting.
/// That is, two senders sending a flow to the super app
contract CrossStreamSuperApp is CFASuperAppBase {
    address public flowRecipient;
    address public prevSender;
    int96 public prevFlowRate;

    constructor(ISuperfluid host_, address z_) CFASuperAppBase(host_) {
        selfRegister(true, true, true);
        flowRecipient = z_;
    }

    function onFlowCreated(ISuperToken superToken, address sender, bytes calldata ctx)
        internal
        override
        returns (bytes memory newCtx)
    {
        newCtx = ctx;

        // get incoming stream
        int96 inFlowRate = superToken.getFlowRate(sender, address(this));

        if (prevSender == address(0)) {
            // first flow to super app creates a flow
            newCtx = superToken.createFlowWithCtx(flowRecipient, inFlowRate, newCtx);
        } else {
            // subsequent flows to super app updates and deletes the flow
            newCtx = superToken.updateFlowWithCtx(flowRecipient, inFlowRate, newCtx);
            newCtx = superToken.deleteFlowWithCtx(prevSender, address(this), newCtx);
        }

        prevSender = sender;
        prevFlowRate = inFlowRate;
    }
}

contract CrossStreamSuperAppTest is FoundrySuperfluidTester {
    CrossStreamSuperApp public superApp;

    constructor() FoundrySuperfluidTester(5) { }

    function setUp() public override {
        super.setUp();

        superApp = new CrossStreamSuperApp(sf.host, bob);
        _addAccount(address(superApp));
    }

    function testNoTokensMintedOrBurnedInCrossStreamSuperApp(int96 flowRate, uint32 blockTimestamp) public {
        // @note due to clipping, there is precision loss, therefore if the flow rate is too low
        // tokens will be unrecoverable
        flowRate = int96(bound(flowRate, 2 ** 31 - 1, 1e14));
        int96 initialFlowRate = flowRate;

        // @note transfer tokens from alice to carol so that
        // alice has type(uint64).max balance to start
        uint256 diff = type(uint88).max - type(uint64).max;
        vm.startPrank(alice);
        superToken.transfer(carol, diff);
        vm.stopPrank();

        uint256 balance = superToken.balanceOf(alice);

        uint256 amountOfTimeTillZero = balance / uint256(uint96(initialFlowRate));
        vm.assume(blockTimestamp < amountOfTimeTillZero);

        int256 rtbSumStart = _helperGetSuperTokenLiquiditySum(superToken);

        // send an initial deposit to the super app to allow the test to pass
        uint256 deposit = sf.cfa.getDepositRequiredForFlowRate(superToken, initialFlowRate);
        vm.startPrank(carol);
        superToken.transfer(address(superApp), deposit);
        vm.stopPrank();

        // @note We are mainly concerned with _definitionAumGtEqRtbSumInvariant holding true:
        // Assert the global invariants at every step.
        _assertGlobalInvariants();

        // create the first flow from alice -> super app -> bob
        vm.startPrank(alice);
        superToken.createFlow(address(superApp), initialFlowRate);
        vm.stopPrank();

        _assertGlobalInvariants();

        uint256 bt = block.timestamp;

        vm.warp(bt + blockTimestamp);

        assertEq(initialFlowRate, superToken.getFlowRate(alice, address(superApp)));

        // create the second flow from dan -> super app -> bob
        // this first: updates the flow from super app -> bob to equal to the new inflowRate (dan flow rateå)
        // then we delete the flow from alice -> super app, super app executes this deletion
        vm.startPrank(dan);
        int96 updatedFlowRate = initialFlowRate * 2;
        superToken.createFlow(address(superApp), updatedFlowRate);
        vm.stopPrank();

        _assertGlobalInvariants();

        // finally we close the stream from dan => super app and super app => bob
        vm.startPrank(dan);
        superToken.deleteFlow(dan, address(superApp));
        vm.stopPrank();

        _assertGlobalInvariants();

        vm.startPrank(bob);
        superToken.deleteFlow(address(superApp), bob);
        vm.stopPrank();

        _assertGlobalInvariants();

        int256 rtbSumEnd = _helperGetSuperTokenLiquiditySum(superToken);

        assertEq(rtbSumStart, rtbSumEnd, "rtbSumStart != rtbSumEnd");
    }
}
