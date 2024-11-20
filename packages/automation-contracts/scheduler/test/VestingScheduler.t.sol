// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { FlowOperatorDefinitions } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IVestingScheduler } from "./../contracts/interface/IVestingScheduler.sol";
import { VestingScheduler } from "./../contracts/VestingScheduler.sol";
import { FoundrySuperfluidTester } from "@superfluid-finance/ethereum-contracts/test/foundry/FoundrySuperfluidTester.t.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

/// @title VestingSchedulerTests
/// @notice Look at me , I am the captain now - Elvijs
contract VestingSchedulerTests is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    event VestingScheduleCreated(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint32 endDate,
        uint256 cliffAmount
    );

    event VestingScheduleUpdated(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 oldEndDate,
        uint32 endDate
    );

    event VestingScheduleDeleted(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver
    );

    event VestingCliffAndFlowExecuted(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 cliffAndFlowDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint256 flowDelayCompensation
    );

    event VestingEndExecuted(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 endDate,
        uint256 earlyEndCompensation,
        bool didCompensationFail
    );

    event VestingEndFailed(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 endDate
    );

    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @dev This is required by solidity for using the SuperTokenV1Library in the tester
    VestingScheduler internal vestingScheduler;

    /// @dev Constants for Testing
    uint32 immutable START_DATE = uint32(block.timestamp + 1);
    uint32 immutable CLIFF_DATE = uint32(block.timestamp + 10 days);
    int96 constant FLOW_RATE = 1000000000;
    uint256 constant CLIFF_TRANSFER_AMOUNT = 1 ether;
    uint32 immutable END_DATE = uint32(block.timestamp + 20 days);
    bytes constant EMPTY_CTX = "";
    uint256 internal _expectedTotalSupply = 0;

    constructor() FoundrySuperfluidTester(3) {
        vestingScheduler = new VestingScheduler(sf.host);
    }

    /// SETUP AND HELPERS
    function setUp() override public virtual {
        super.setUp();
    }

    function _setACL_AUTHORIZE_FULL_CONTROL(address user, int96 flowRate) private {
        vm.startPrank(user);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                superToken,
                address(vestingScheduler),
                FlowOperatorDefinitions.AUTHORIZE_FULL_CONTROL,
                flowRate,
                new bytes(0)
                )
            ),
            new bytes(0)
        );
        vm.stopPrank();
    }

    function _createVestingScheduleWithDefaultData(address sender, address receiver) private {
        vm.startPrank(sender);
        vestingScheduler.createVestingSchedule(
            superToken,
            receiver,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            EMPTY_CTX
        );
        vm.stopPrank();
    }

    /// TESTS

    function testCreateVestingSchedule() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT
        );
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        //assert storage data
        VestingScheduler.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE , "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE , "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE , "schedule.flowRate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT , "schedule.cliffAmount");
    }

    function testCannotCreateVestingScheduleWithWrongData() public {
        vm.startPrank(alice);
        // revert with superToken = 0
        vm.expectRevert(IVestingScheduler.ZeroAddress.selector);
        vestingScheduler.createVestingSchedule(
                ISuperToken(address(0)),
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                EMPTY_CTX
        );

        // revert with receivers = sender
        vm.expectRevert(IVestingScheduler.AccountInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                alice,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                EMPTY_CTX
        );

        // revert with receivers = address(0)
        vm.expectRevert(IVestingScheduler.AccountInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                address(0),
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                EMPTY_CTX
        );

        // revert with flowRate = 0
        vm.expectRevert(IVestingScheduler.FlowRateInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                0,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                EMPTY_CTX
        );

        // revert with startDate && cliffDate  = 0
        vm.expectRevert(IVestingScheduler.CliffInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            0,
            0,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            EMPTY_CTX
        );

        // revert with startDate && cliffDate  = 0
        vm.expectRevert(IVestingScheduler.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                0,
                0,
                FLOW_RATE,
                0,
                END_DATE,
                EMPTY_CTX
        );

        // revert with endDate = 0
        vm.expectRevert(IVestingScheduler.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                0,
                EMPTY_CTX
        );

        // revert with cliffAndFlowDate < block.timestamp
        vm.expectRevert(IVestingScheduler.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                uint32(block.timestamp) - 1,
                0,
                FLOW_RATE,
                0,
                END_DATE,
                EMPTY_CTX
        );

        // revert with cliffAndFlowDate >= endDate
        vm.expectRevert(IVestingScheduler.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                CLIFF_DATE,
                EMPTY_CTX
        );

        // revert with cliffAndFlowDate + startDateValidFor >= endDate - endDateValidBefore
        vm.expectRevert(IVestingScheduler.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                CLIFF_DATE,
                EMPTY_CTX
        );

        // revert with startDate > cliffDate
        vm.expectRevert(IVestingScheduler.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                CLIFF_DATE + 1,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                EMPTY_CTX
        );


        // revert with vesting duration < 7 days
        vm.expectRevert(IVestingScheduler.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                CLIFF_DATE + 2 days,
                EMPTY_CTX
        );
    }

    function testCannotCreateVestingScheduleIfDataExist() public {
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.expectRevert(IVestingScheduler.ScheduleAlreadyExists.selector);
        _createVestingScheduleWithDefaultData(alice, bob);
    }

    function testUpdateVestingSchedule() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT
        );
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);
        uint256 initialTimestamp = block.timestamp + 10 days + 1800;
        vm.warp(initialTimestamp);
        vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        vm.stopPrank();
        vm.startPrank(alice);
        vestingScheduler.updateVestingSchedule(superToken, bob, END_DATE + 1000, EMPTY_CTX);
        //assert storage data
        VestingScheduler.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == 0 , "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE + 1000 , "schedule.endDate");
    }

    function testCannotUpdateVestingScheduleIfNotRunning() public {
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        vm.expectRevert(IVestingScheduler.ScheduleNotFlowing.selector);
        vestingScheduler.updateVestingSchedule(superToken, bob, END_DATE, EMPTY_CTX);
    }

    function testCannotUpdateVestingScheduleIfDataDontExist() public {
        vm.startPrank(alice);
        vm.expectRevert(IVestingScheduler.ScheduleNotFlowing.selector);
        vestingScheduler.updateVestingSchedule(superToken, bob, END_DATE, EMPTY_CTX);
    }

    function testDeleteVestingSchedule() public {
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleDeleted(superToken, alice, bob);
        vestingScheduler.deleteVestingSchedule(superToken, bob, EMPTY_CTX);
    }

    function testCannotDeleteVestingScheduleIfDataDontExist() public {
        vm.startPrank(alice);
        vm.expectRevert(IVestingScheduler.ScheduleDoesNotExist.selector);
        vestingScheduler.deleteVestingSchedule(
            superToken,
            bob,
            EMPTY_CTX
        );
    }

    function testExecuteCliffAndFlowWithCliffAmount() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);
        uint256 initialTimestamp = block.timestamp + 10 days + 1800;
        vm.warp(initialTimestamp);
        uint256 flowDelayCompensation = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, CLIFF_TRANSFER_AMOUNT + flowDelayCompensation);
        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, flowDelayCompensation
        );
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(success, "executeVesting should return true");
        uint256 finalTimestamp = block.timestamp + 10 days - 3600;
        vm.warp(finalTimestamp);
        vm.expectEmit(true, true, true, true);
        uint256 timeDiffToEndDate = END_DATE > block.timestamp ? END_DATE - block.timestamp : 0;
        uint256 adjustedAmountClosing = timeDiffToEndDate * uint96(FLOW_RATE);
        emit Transfer(alice, bob, adjustedAmountClosing);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(
            superToken, alice, bob, END_DATE, adjustedAmountClosing, false
        );
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (END_DATE-CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT ;
        assertEq(aliceInitialBalance - aliceFinalBalance, aliceShouldStream, "(sender) wrong final balance");
        assertEq(bobFinalBalance, bobInitialBalance + aliceShouldStream, "(receiver) wrong final balance");
    }

    function testExecuteCliffAndFlowWithoutCliffAmountOrAdjustment() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                0,
                END_DATE,
                EMPTY_CTX
        );
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.warp(CLIFF_DATE);
        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, CLIFF_DATE, FLOW_RATE, 0, 0
        );
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(success, "executeVesting should return true");
        vm.warp(END_DATE);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, 0, false);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (END_DATE-CLIFF_DATE) * uint96(FLOW_RATE);
        assertEq(aliceInitialBalance - aliceFinalBalance, aliceShouldStream, "(sender) wrong final balance");
        assertEq(bobFinalBalance, bobInitialBalance + aliceShouldStream, "(receiver) wrong final balance");
    }

    function testExecuteCliffAndFlowWithUpdatedEndDate() public {
        uint32 NEW_END_DATE = END_DATE - 1000;
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);
        uint256 initialTimestamp = block.timestamp + 10 days + 1800;
        vm.warp(initialTimestamp);
        uint256 flowDelayCompensation = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, CLIFF_TRANSFER_AMOUNT + flowDelayCompensation);
        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, flowDelayCompensation
        );
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(success, "executeVesting should return true");
        vm.stopPrank();
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleUpdated(superToken, alice, bob, END_DATE, NEW_END_DATE);
        vestingScheduler.updateVestingSchedule(superToken, bob, NEW_END_DATE, EMPTY_CTX);
        uint256 finalTimestamp = block.timestamp + 10 days - 3600;
        vm.warp(finalTimestamp);
        vm.expectEmit(true, true, true, true);
        uint256 timeDiffToEndDate = NEW_END_DATE > block.timestamp ? NEW_END_DATE - block.timestamp : 0;
        uint256 adjustedAmountClosing = timeDiffToEndDate * uint96(FLOW_RATE);
        emit Transfer(alice, bob, adjustedAmountClosing);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(
            superToken, alice, bob, NEW_END_DATE, adjustedAmountClosing, false
        );
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (NEW_END_DATE-CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT ;
        assertEq(aliceInitialBalance - aliceFinalBalance, aliceShouldStream, "(sender) wrong final balance");
        assertEq(bobFinalBalance, bobInitialBalance + aliceShouldStream, "(receiver) wrong final balance");
    }

    function testExecuteCliffAndFlowRevertClosingTransfer() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);
        uint256 initialTimestamp = block.timestamp + 10 days + 1800;
        vm.warp(initialTimestamp);
        uint256 flowDelayCompensation = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, CLIFF_TRANSFER_AMOUNT + flowDelayCompensation);
        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, flowDelayCompensation
        );
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(success, "executeVesting should return true");
        vm.stopPrank();
        vm.startPrank(alice);
        superToken.transferAll(eve);
        vm.stopPrank();
        vm.startPrank(admin);
        uint256 finalTimestamp = block.timestamp + 10 days - 3600;
        vm.warp(finalTimestamp);
        uint256 timeDiffToEndDate = END_DATE > block.timestamp ? END_DATE - block.timestamp : 0;
        uint256 adjustedAmountClosing = timeDiffToEndDate * uint96(FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(
            superToken, alice, bob, END_DATE, adjustedAmountClosing, true
        );
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
    }

    function testCannotExecuteEndVestingBeforeTime() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);
        vm.expectRevert(IVestingScheduler.TimeWindowInvalid.selector);
        vestingScheduler.executeEndVesting(superToken, alice, bob);
    }

    function testCannotExecuteCliffAndFlowBeforeTime() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);
        vm.expectRevert(IVestingScheduler.TimeWindowInvalid.selector);
        vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
    }

    function testCannotExecuteEndWithoutStreamRunning() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);
        uint256 initialTimestamp = block.timestamp + 10 days + 1800;
        vm.warp(initialTimestamp);
        uint256 flowDelayCompensation = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, CLIFF_TRANSFER_AMOUNT + flowDelayCompensation);
        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, flowDelayCompensation
        );
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(success, "executeVesting should return true");
        vm.stopPrank();
        vm.startPrank(alice);
        superToken.deleteFlow(alice, bob);
        vm.stopPrank();
        vm.startPrank(admin);
        uint256 finalTimestamp = block.timestamp + 10 days - 3600;
        vm.warp(finalTimestamp);
        vm.expectEmit(true, true, true, true);
        emit VestingEndFailed(
            superToken, alice, bob, END_DATE
        );
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
    }
}