// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { FlowOperatorDefinitions } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IFlowScheduler } from "./../contracts/interface/IFlowScheduler.sol";
import { FlowScheduler } from "./../contracts/FlowScheduler.sol";
import { FoundrySuperfluidTester } from "@superfluid-finance/ethereum-contracts/test/foundry/FoundrySuperfluidTester.t.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

/// @title FlowSchedulerTests
/// @notice Look at me , I am the captain now - Elvijs
contract FlowSchedulerTest is FoundrySuperfluidTester {

    event FlowScheduleCreated(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 startDate,
        uint32 startMaxDelay,
        int96 flowRate,
        uint32 endDate,
        uint256 startAmount,
        bytes userData
    );

    event FlowScheduleDeleted(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver
    );

    event CreateFlowExecuted(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 startDate,
        uint32 startMaxDelay,
        int96 flowRate,
        uint256 startAmount,
        bytes userData
    );

    event DeleteFlowExecuted(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 endDate,
        bytes userData
    );

    /// @dev This is required by solidity for using the SupertTokenV1Library in the tester
    using SuperTokenV1Library for SuperToken;
    constructor() FoundrySuperfluidTester(3) {}
    FlowScheduler internal flowScheduler;

    function setUp() override public virtual {
        super.setUp();
        flowScheduler = new FlowScheduler(sf.host);
    }

    function getHashID(
        address _superToken,
        address sender,
        address receiver
    )
        public pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(
            _superToken,
            sender,
            receiver
        ));
    }

    /// @dev Constants for Testing
    uint32 internal defaultStartDate = uint32(block.timestamp + 1);
    uint32 testNumber;
    int96 defaultFlowRate = int96(1000);
    uint32 defaultStartMaxDelay = uint32(60);
    uint256 defaultStartAmount = 500;

    function testCreateFlowScheduleWithExplicitTimeWindow() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        uint32 defaultEndDate = defaultStartDate + uint32(3600);
        emit FlowScheduleCreated(
            superToken,
            alice,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultEndDate,
            defaultStartAmount,
            ""
        );
        vm.expectCall(
            address(flowScheduler),
            abi.encodeCall(
                flowScheduler.createFlowSchedule,
                (
                    superToken,
                    bob,
                    defaultStartDate,
                    defaultStartMaxDelay,
                    defaultFlowRate,
                    defaultStartAmount,
                    defaultEndDate,
                    "",
                    ""
                )
            )
        );
        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );

        (uint32 startDate,,uint32 endDate,,,) = flowScheduler.flowSchedules(getHashID(address(superToken),alice,bob));
        assertTrue(startDate != 0 || endDate != 0, "Flow schedule not created");
    }

    function testCreateFlowScheduleWithZeroTimes() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        uint32 startMaxDelay = 0;
        uint32 defaultEndDate = 3600;
        emit FlowScheduleCreated(
            superToken,
            alice,
            bob,
            0,
            startMaxDelay,
            defaultFlowRate,
            defaultEndDate,
            defaultStartAmount,
            ""
        );
        vm.expectCall(
            address(flowScheduler),
            abi.encodeCall(
                flowScheduler.createFlowSchedule,
                (
                    superToken,
                    bob,
                    0,
                    startMaxDelay,
                    defaultFlowRate,
                    defaultStartAmount,
                    defaultEndDate,
                    "",
                    ""
                )
            )
        );
        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            0,
            startMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );
        (uint32 startDate,,uint32 endDate,,,) = flowScheduler.flowSchedules(getHashID(address(superToken),alice,bob));
        assertTrue(startDate != 0 || endDate != 0, "Flow schedule not created");
    }

    function testCannotCreateFlowScheduleWhenSenderSameAsReceiver() public {
        // Expect revert on receiver same as sender.
        vm.prank(alice);
        vm.expectRevert(IFlowScheduler.AccountInvalid.selector);
        flowScheduler.createFlowSchedule(
            superToken,
            alice,
            defaultStartDate,
            uint32(60),
            defaultFlowRate,
            defaultStartAmount,
            defaultStartDate + uint32(3600),
            "",
            ""
        );
    }

    function testCannotCreateFlowScheduleWhenTimeWindowInvalid() public {
        vm.expectRevert(IFlowScheduler.TimeWindowInvalid.selector);
        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            uint32(0),
            uint32(60),
            int96(1000),
            defaultStartAmount,
            uint32(0),
            "",
            ""
        );
    }

    function testCannotExecuteCreateFlowWhenScheduleDNE() public {
        vm.prank(admin);
        // Expect revert on when schedule does not exist.
        vm.expectRevert(IFlowScheduler.TimeWindowInvalid.selector);
        vm.warp(100);
        flowScheduler.executeCreateFlow(superToken,alice,bob,"");
    }

    function testCannotExecuteDeleteFlowWhenScheduleDNE() public {
        vm.prank(admin);
        // Expect revert on when schedule does not exist.
        vm.expectRevert(IFlowScheduler.TimeWindowInvalid.selector);
        flowScheduler.executeDeleteFlow(superToken,alice,bob,"");
    }

    function testCannotExecuteCreateFlowWithInvalidPermissions() public {
        vm.prank(bob);
        superToken.increaseAllowance(address(flowScheduler), type(uint256).max);
        vm.prank(bob);
        flowScheduler.createFlowSchedule(
            superToken, alice, defaultStartDate, uint32(1000), int96(1000), defaultStartAmount, defaultStartDate + uint32(3600), "", ""
        );

        vm.expectRevert(0xa3eab6ac); // error CFA_ACL_OPERATOR_NO_CREATE_PERMISSIONS() -> 0xa3eab6ac
        vm.warp(defaultStartDate + 1000);
        vm.prank(admin);
        flowScheduler.executeCreateFlow(superToken, bob,alice,"");
    }

    function testCannotExecuteCreateFlowWhenTimeWindowInvalid() public {
        // Expect revert on when start and end are both 0.
        vm.expectRevert(IFlowScheduler.TimeWindowInvalid.selector);
        vm.startPrank(admin);
        flowScheduler.executeCreateFlow(superToken,alice,bob,"");

        // Expect revert on when start time is exactly block.timestamp.
        vm.expectRevert(IFlowScheduler.TimeWindowInvalid.selector);
        flowScheduler.executeCreateFlow(superToken,alice,bob,"");

        // Expect revert on when start time is after end time.
        vm.expectRevert(IFlowScheduler.TimeWindowInvalid.selector);
        flowScheduler.executeCreateFlow(superToken,alice,bob,"");

        // Expect revert on when start time is empty and duration is not.
        vm.expectRevert(IFlowScheduler.TimeWindowInvalid.selector);
        flowScheduler.executeCreateFlow(superToken,alice,bob,"");
        vm.stopPrank();
    }

    function testExecuteCreateFlow() public {
        vm.startPrank(alice);
        flowScheduler.createFlowSchedule(
            superToken, bob, defaultStartDate, uint32(100), int96(1000), defaultStartAmount, defaultStartDate + uint32(3600), "", ""
        );
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                superToken,
                address(flowScheduler),
                FlowOperatorDefinitions.AUTHORIZE_FLOW_OPERATOR_CREATE,
                1000,
                new bytes(0)
                )
            ),
            new bytes(0)
        );
        // increase allowance so flowScheduler can transfer tokens from alice to bob
        // when vesting starts
        superToken.increaseAllowance(address(flowScheduler), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit CreateFlowExecuted(
            superToken, alice, bob, defaultStartDate, uint32(100), int96(1000), defaultStartAmount, ""
        );
        vm.warp(100);
        vm.expectCall(
            address(flowScheduler),
            abi.encodeCall(
                flowScheduler.executeCreateFlow,
                (superToken, alice, bob, "")
            )
        );
        FlowScheduler.FlowSchedule memory schedule = flowScheduler.getFlowSchedule(address(superToken), alice, bob);
        assertEq(schedule.startAmount, defaultStartAmount);
        uint256 bobBalanceBefore = superToken.balanceOf(bob);
        uint256 aliceBalanceBefore = superToken.balanceOf(alice);
        flowScheduler.executeCreateFlow(superToken, alice, bob, "");
        schedule = flowScheduler.getFlowSchedule(address(superToken), alice, bob);
        assertEq(schedule.startAmount, 0);
        // Bob's balance is slightly more than or equal to his previous balance plus defaultStartAmount
        // this is due to the logic which determines the startAmount
        assertTrue(superToken.balanceOf(bob) >= bobBalanceBefore + defaultStartAmount);

        // Alice's balance is less than or equal to previous balance sub defaultStartAmount
        // it is actually slightly less because of the deposit paid for stream creation
        assertTrue(superToken.balanceOf(alice) <= aliceBalanceBefore - defaultStartAmount);
    }

    function testExecute2xCreateFlow() public {
        vm.startPrank(alice);
        flowScheduler.createFlowSchedule(
            superToken, bob, defaultStartDate, uint32(100), int96(1000), 0, defaultStartDate + uint32(3600), "", ""
        );
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                superToken,
                address(flowScheduler),
                FlowOperatorDefinitions.AUTHORIZE_FLOW_OPERATOR_CREATE,
                1000,
                new bytes(0)
                )
            ),
            new bytes(0)
        );
        // Remove any allowance
        superToken.approve(address(flowScheduler), 0);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit CreateFlowExecuted(
            superToken, alice, bob, defaultStartDate, uint32(100), int96(1000), 0, ""
        );
        vm.warp(100);
        vm.expectCall(
            address(flowScheduler),
            abi.encodeCall(
                flowScheduler.executeCreateFlow,
                (superToken, alice, bob, "")
            )
        );

        FlowScheduler.FlowSchedule memory schedule = flowScheduler.getFlowSchedule(alice, bob, address(superToken));
        assertEq(schedule.startAmount, 0);
        flowScheduler.executeCreateFlow(superToken, alice, bob, "");
        schedule = flowScheduler.getFlowSchedule(address(superToken), alice, bob);
        assertEq(schedule.startAmount, 0);

        // try to execute again
        vm.expectRevert(IFlowScheduler.TimeWindowInvalid.selector);
        flowScheduler.executeCreateFlow(superToken,alice,bob,"");
    }

    function testCreateScheduleAndDeleteSchedule() public {
        vm.startPrank(alice);
        flowScheduler.createFlowSchedule(
            superToken, bob, defaultStartDate, 60, int96(1000), defaultStartAmount, defaultStartDate + uint32(3600), "", ""
        );
        FlowScheduler.FlowSchedule memory schedule1 = flowScheduler.getFlowSchedule(address(superToken), alice, bob);
        assertEq(schedule1.startDate, defaultStartDate);
        vm.expectEmit(true, true, true, true);
        emit FlowScheduleDeleted(superToken, alice, bob);
        flowScheduler.deleteFlowSchedule(superToken, bob, "");
        FlowScheduler.FlowSchedule memory schedule2 = flowScheduler.getFlowSchedule(address(superToken), alice, bob);
        assertEq(schedule2.startDate, 0);
    }
}
