// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { FlowOperatorDefinitions, ISuperfluid, BatchOperation, ISuperApp } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IVestingSchedulerV2 } from "./../contracts/interface/IVestingSchedulerV2.sol";
import { VestingSchedulerV2 } from "./../contracts/VestingSchedulerV2.sol";
import { FoundrySuperfluidTester } from "@superfluid-finance/ethereum-contracts/test/foundry/FoundrySuperfluidTester.t.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "forge-std/console.sol";

/// @title VestingSchedulerTests
/// @notice Look at me , I am the captain now - Elvijs
contract VestingSchedulerV2Tests is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    event VestingScheduleCreated(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint32 endDate,
        uint256 cliffAmount,
        uint32 claimValidityDate,
        uint96 remainderAmount
    );

    event VestingScheduleUpdated(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 oldEndDate,
        uint32 endDate,
        uint96 remainderAmount
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

    event VestingClaimed(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        address claimer
    );

    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @dev This is required by solidity for using the SuperTokenV1Library in the tester
    VestingSchedulerV2 public vestingScheduler;

    /// @dev Constants for Testing
    uint256 immutable BLOCK_TIMESTAMP = 100;
    uint32 immutable START_DATE = uint32(BLOCK_TIMESTAMP + 1);
    uint32 immutable CLIFF_DATE = uint32(BLOCK_TIMESTAMP + 10 days);
    int96 constant FLOW_RATE = 1000000000;
    uint256 constant CLIFF_TRANSFER_AMOUNT = 1 ether;
    uint32 immutable CLAIM_VALIDITY_DATE = uint32(BLOCK_TIMESTAMP + 15 days);
    uint32 immutable END_DATE = uint32(BLOCK_TIMESTAMP + 20 days);
    bytes constant EMPTY_CTX = "";
    bytes constant NON_EMPTY_CTX = abi.encode(alice);
    uint256 internal _expectedTotalSupply = 0;

    constructor() FoundrySuperfluidTester(3) {
        vestingScheduler = new VestingSchedulerV2(sf.host);
    }

    /// SETUP AND HELPERS
    function setUp() override public virtual {
        super.setUp();
        vm.warp(BLOCK_TIMESTAMP);
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

    function _arrangeAllowances(address sender, int96 flowRate) private {
        // ## Superfluid ACL allowance and permissions
        _setACL_AUTHORIZE_FULL_CONTROL(sender, flowRate);

        // ## ERC-20 allowance for cliff and compensation transfers
        vm.startPrank(sender);
        superToken.approve(address(vestingScheduler), type(uint256).max);
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
            0,
            EMPTY_CTX
        );
        vm.stopPrank();
    }

    function _createClaimableVestingScheduleWithDefaultData(address sender, address receiver) private {
        vm.startPrank(sender);
        vestingScheduler.createVestingSchedule(
            superToken,
            receiver,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            CLAIM_VALIDITY_DATE,
            EMPTY_CTX
        );
        vm.stopPrank();
    }

        function _createClaimableVestingScheduleWithClaimDateAfterEndDate(address sender, address receiver, uint256 delayAfterEndDate) private {
        vm.startPrank(sender);
        vestingScheduler.createVestingSchedule(
            superToken,
            receiver,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            END_DATE + uint32(delayAfterEndDate),
            EMPTY_CTX
        );
        vm.stopPrank();
    }

    function assertAreScheduleCreationParamsEqual(
        IVestingSchedulerV2.ScheduleCreationParams memory params1,
        IVestingSchedulerV2.ScheduleCreationParams memory params2
    ) internal pure {
        require(params1.superToken == params2.superToken, "SuperToken mismatch");
        require(params1.receiver == params2.receiver, "Receiver mismatch");
        require(params1.startDate == params2.startDate, "StartDate mismatch");
        require(params1.claimValidityDate == params2.claimValidityDate, "ClaimValidityDate mismatch");
        require(params1.cliffDate == params2.cliffDate, "CliffDate mismatch");
        require(params1.flowRate == params2.flowRate, "FlowRate mismatch");
        require(params1.cliffAmount == params2.cliffAmount, "CliffAmount mismatch");
        require(params1.endDate == params2.endDate, "EndDate mismatch");
        require(params1.remainderAmount == params2.remainderAmount, "RemainderAmount mismatch");
    }

    function testAssertScheduleDoesNotExist(
        address superToken,
        address sender,
        address receiver
    ) public {
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(superToken, sender, receiver);
        VestingSchedulerV2.VestingSchedule memory deletedSchedule;

        assertEq(schedule.cliffAndFlowDate, deletedSchedule.cliffAndFlowDate, "cliffAndFlowDate mismatch");
        assertEq(schedule.endDate, deletedSchedule.endDate, "endDate mismatch");
        assertEq(schedule.flowRate, deletedSchedule.flowRate, "flowRate mismatch");
        assertEq(schedule.cliffAmount, deletedSchedule.cliffAmount, "cliffAmount mismatch");
        assertEq(schedule.remainderAmount, deletedSchedule.remainderAmount, "remainderAmount mismatch");
        assertEq(schedule.claimValidityDate, deletedSchedule.claimValidityDate, "claimValidityDate mismatch");
    }

    function _getExpectedSchedule(
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate
    ) public view returns (IVestingSchedulerV2.VestingSchedule memory expectedSchedule) {
        if (startDate == 0) {
            startDate = uint32(block.timestamp);
        }

        uint32 cliffAndFlowDate = cliffDate == 0 ? startDate : cliffDate;

        expectedSchedule = IVestingSchedulerV2.VestingSchedule({
            cliffAndFlowDate: cliffAndFlowDate,
            endDate: endDate,
            claimValidityDate: 0,
            flowRate: flowRate,
            cliffAmount: cliffAmount,
            remainderAmount: 0
        });
    }

    function _getExpectedScheduleFromAmountAndDuration(
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 cliffPeriod,
        uint32 startDate,
        uint32 claimPeriod
    ) public view returns (IVestingSchedulerV2.VestingSchedule memory expectedSchedule) {
        if (startDate == 0) {
            startDate = uint32(block.timestamp);
        }

        int96 flowRate = SafeCast.toInt96(SafeCast.toInt256(totalAmount / totalDuration));

        uint32 cliffDate;
        uint32 cliffAndFlowDate;
        uint256 cliffAmount;
        if (cliffPeriod > 0) {
            cliffDate = startDate + cliffPeriod;
            cliffAmount = cliffPeriod * SafeCast.toUint256(flowRate);
            cliffAndFlowDate = cliffDate;
        } else {
            cliffDate = 0;
            cliffAmount = 0;
            cliffAndFlowDate = startDate;
        }

        uint32 endDate = startDate + totalDuration;

        uint96 remainderAmount = SafeCast.toUint96(totalAmount - SafeCast.toUint256(flowRate) * totalDuration);

        expectedSchedule = IVestingSchedulerV2.VestingSchedule({
            cliffAndFlowDate: cliffAndFlowDate,
            endDate: endDate,
            flowRate: flowRate,
            cliffAmount: cliffAmount,
            remainderAmount: remainderAmount,
            claimValidityDate: claimPeriod == 0 ? 0 : startDate + claimPeriod
        });
    }

    /// TESTS

    function test_vesting_scheduler_is_superapp() public {
        assertTrue(sf.host.isApp(ISuperApp(address(new VestingSchedulerV2(sf.host)))));
    }

    function testCreateVestingSchedule() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0);

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            EMPTY_CTX
        );
        vm.stopPrank();

        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE , "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE , "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE , "schedule.flowRate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT , "schedule.cliffAmount");
    }

    function test_createVestingSchedule_v1_overload() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0);
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE , "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE , "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE , "schedule.flowRate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT , "schedule.cliffAmount");
    }

    function testCannotCreateVestingScheduleWithWrongData() public {
        vm.startPrank(alice);
        // revert with superToken = 0
        vm.expectRevert(IVestingSchedulerV2.ZeroAddress.selector);
        vestingScheduler.createVestingSchedule(
                ISuperToken(address(0)),
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                0,
                EMPTY_CTX
        );

        // revert with receivers = sender
        vm.expectRevert(IVestingSchedulerV2.AccountInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                alice,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                0,
                EMPTY_CTX
        );

        // revert with receivers = address(0)
        vm.expectRevert(IVestingSchedulerV2.AccountInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                address(0),
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                0,
                EMPTY_CTX
        );

        // revert with flowRate = 0
        vm.expectRevert(IVestingSchedulerV2.FlowRateInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                0,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                0,
                EMPTY_CTX
        );

        // revert with cliffDate = 0 but cliffAmount != 0
        vm.expectRevert(IVestingSchedulerV2.CliffInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            0,
            0,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            0,
            EMPTY_CTX
        );

        // revert with startDate < block.timestamp && cliffDate = 0
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                uint32(block.timestamp - 1),
                0,
                FLOW_RATE,
                0,
                END_DATE,
                0,
                EMPTY_CTX
        );

        // revert with endDate = 0
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                0,
                0,
                EMPTY_CTX
        );

        // revert with cliffAndFlowDate < block.timestamp
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                0,
                uint32(block.timestamp) - 1,
                FLOW_RATE,
                0,
                END_DATE,
                0,
                EMPTY_CTX
        );

        // revert with cliffAndFlowDate >= endDate
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                CLIFF_DATE,
                0,
                EMPTY_CTX
        );

        // revert with cliffAndFlowDate + startDateValidFor >= endDate - endDateValidBefore
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                CLIFF_DATE,
                0,
                EMPTY_CTX
        );

        // revert with startDate > cliffDate
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                CLIFF_DATE + 1,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                0,
                EMPTY_CTX
        );


        // revert with vesting duration < 7 days
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                CLIFF_DATE + 2 days,
                0,
                EMPTY_CTX
        );
    }

    function testCannotCreateVestingScheduleIfDataExist() public {
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.expectRevert(IVestingSchedulerV2.ScheduleAlreadyExists.selector);
        _createVestingScheduleWithDefaultData(alice, bob);
    }

    function testUpdateVestingSchedule() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0);
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
        IVestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == 0 , "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE + 1000 , "schedule.endDate");
    }

    function test_updateVestingSchedule_invalidEndDate() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0);
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);
        uint256 initialTimestamp = block.timestamp + 10 days + 1800;
        vm.warp(initialTimestamp);
        vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        vm.stopPrank();
        vm.startPrank(alice);

        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.updateVestingSchedule(superToken, bob, uint32(initialTimestamp - 1), EMPTY_CTX);

        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.updateVestingSchedule(superToken, bob, uint32(initialTimestamp), EMPTY_CTX);


    }

    function testCannotUpdateVestingScheduleIfNotRunning() public {
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        vm.expectRevert(IVestingSchedulerV2.ScheduleNotFlowing.selector);
        vestingScheduler.updateVestingSchedule(superToken, bob, END_DATE, EMPTY_CTX);
    }

    function testCannotUpdateVestingScheduleIfDataDontExist() public {
        vm.startPrank(alice);
        vm.expectRevert(IVestingSchedulerV2.ScheduleNotFlowing.selector);
        vestingScheduler.updateVestingSchedule(superToken, bob, END_DATE, EMPTY_CTX);
    }

    function testDeleteVestingSchedule() public {
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleDeleted(superToken, alice, bob);
        vestingScheduler.deleteVestingSchedule(superToken, bob, EMPTY_CTX);
        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function testCannotDeleteVestingScheduleIfDataDontExist() public {
        vm.startPrank(alice);
        vm.expectRevert(IVestingSchedulerV2.ScheduleDoesNotExist.selector);
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

        vm.expectRevert(IVestingSchedulerV2.AlreadyExecuted.selector);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);

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
                0,
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
        emit VestingScheduleUpdated(superToken, alice, bob, END_DATE, NEW_END_DATE, 0);
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
        uint256 earlyEndTimestamp = block.timestamp + 10 days - 3600;
        vm.warp(earlyEndTimestamp);

        vm.expectRevert();
        vestingScheduler.executeEndVesting(superToken, alice, bob);

        uint256 finalTimestamp = END_DATE + 1;
        vm.warp(finalTimestamp);

        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(
            superToken, alice, bob, END_DATE, 0, true
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
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.executeEndVesting(superToken, alice, bob);
    }

    function testCannotExecuteCliffAndFlowBeforeTime() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
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

    // # Vesting Scheduler V2 tests

    function testCreateAndExecuteImmediately() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        // # Create schedule
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        uint32 startAndCliffDate = uint32(block.timestamp);

        vm.expectEmit();
        emit VestingScheduleCreated(superToken, alice, bob, startAndCliffDate, startAndCliffDate, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0);

        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            startAndCliffDate,
            startAndCliffDate,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            0,
            EMPTY_CTX
        );
        // ---

        // # Execute start
        vm.expectEmit();
        emit Transfer(alice, bob, CLIFF_TRANSFER_AMOUNT);

        vm.expectEmit();
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, startAndCliffDate, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, uint256(0)
        );
        vm.stopPrank();

        vm.startPrank(admin);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        vm.stopPrank();

        assertTrue(success, "executeVesting should return true");
        // ---

        // # Execute end
        uint256 finalTimestamp = END_DATE - 3600;
        vm.warp(finalTimestamp);

        uint256 timeDiffToEndDate = END_DATE > block.timestamp ? END_DATE - block.timestamp : 0;
        uint256 adjustedAmountClosing = timeDiffToEndDate * uint96(FLOW_RATE);

        vm.expectEmit();
        emit Transfer(alice, bob, adjustedAmountClosing);

        vm.expectEmit();
        emit VestingEndExecuted(
            superToken, alice, bob, END_DATE, adjustedAmountClosing, false
        );
        vm.startPrank(admin);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        vm.stopPrank();
        assertTrue(success, "executeCloseVesting should return true");

        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (END_DATE - startAndCliffDate) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;
        assertEq(aliceInitialBalance - aliceFinalBalance, aliceShouldStream, "(sender) wrong final balance");
        assertEq(bobFinalBalance, bobInitialBalance + aliceShouldStream, "(receiver) wrong final balance");
        // ---
    }

    function test_createScheduleFromAmountAndDuration_reverts() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.expectRevert(IVestingSchedulerV2.FlowRateInvalid.selector);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            0, // amount
            1209600, // duration
            uint32(block.timestamp), // startDate
            604800, // cliffPeriod
            0, // claimPeriod
            EMPTY_CTX
        );

        console.log("Revert with cliff and start in history.");
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            1 ether, // amount
            1209600, // duration
            uint32(block.timestamp - 1), // startDate
            0, // cliffPeriod
            0, // claimPeriod
            EMPTY_CTX
        );

        console.log("Revert with overflow.");
        vm.expectRevert("SafeCast: value doesn't fit in 96 bits");
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            type(uint256).max, // amount
            1209600, // duration
            uint32(block.timestamp), // startDate
            0, // cliffPeriod
            0, // claimPeriod
            EMPTY_CTX
        );

        console.log("Revert with underflow/overflow.");
        vm.expectRevert(); // todo: the right error
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            1 ether, // amount
            type(uint32).max, // duration
            uint32(block.timestamp), // startDate
            0, // cliffPeriod
            0, // claimPeriod
            EMPTY_CTX
        );

        console.log("Revert with start date in history.");
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            1 ether, // amount
            1209600, // duration
            uint32(block.timestamp - 1), // startDate
            604800, // cliffPeriod
            0, // claimPeriod
            EMPTY_CTX
        );
    }

    function testNewFunctionScheduleCreationWithoutCliff(uint8 randomizer) public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();

        uint32 startDate = uint32(block.timestamp);
        uint256 totalVestedAmount = 105_840_000; // a value perfectly divisible by a week
        uint32 vestingDuration = 1 weeks;
        int96 expectedFlowRate = 175; // totalVestedAmount / vestingDuration
        uint32 expectedEndDate = startDate + vestingDuration;

        vm.expectEmit();
        emit VestingScheduleCreated(superToken, alice, bob, startDate, 0, expectedFlowRate, expectedEndDate, 0, 0, 0);

        vm.startPrank(alice);
        bool useCtx = randomizer % 2 == 0;
        if (useCtx) {
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalVestedAmount,
                vestingDuration,
                startDate, 
                0, // cliffPeriod
                0, // claimPeriod
                EMPTY_CTX
            );
        } else {
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalVestedAmount,
                vestingDuration,
                startDate,
                0, // cliffPeriod
                0 // claimPeriod
            );
        }
        vm.stopPrank();
    }

    function testNewFunctionScheduleCreationWithCliff(uint8 randomizer) public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();

        uint32 startDate = uint32(block.timestamp);
        uint256 totalVestedAmount = 103_680_000; // a value perfectly divisible
        uint32 vestingDuration = 1 weeks + 1 days;
        uint32 cliffPeriod = 1 days;

        int96 expectedFlowRate = 150; // (totalVestedAmount - cliffAmount) / (vestingDuration - cliffPeriod)
        uint256 expectedCliffAmount = 12960000;
        uint32 expectedCliffDate = startDate + cliffPeriod;
        uint32 expectedEndDate = startDate + vestingDuration;

        vm.expectEmit();
        emit VestingScheduleCreated(superToken, alice, bob, startDate, expectedCliffDate, expectedFlowRate, expectedEndDate, expectedCliffAmount, 0, 0);

        vm.startPrank(alice);
        bool useCtx = randomizer % 2 == 0;
        if (useCtx) {
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalVestedAmount,
                vestingDuration,
                startDate,
                cliffPeriod,
                0,
                EMPTY_CTX
            );
        } else {
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalVestedAmount,
                vestingDuration,
                startDate,
                cliffPeriod,
                0
            );
        }
        vm.stopPrank();
    }

    struct BigTestData {
        uint256 beforeSenderBalance;
        uint256 beforeReceiverBalance;
        uint256 afterSenderBalance;
        uint256 afterReceiverBalance;
        uint32 expectedCliffDate;
        uint32 expectedStartDate;
        address claimer;
        IVestingSchedulerV2.VestingSchedule expectedSchedule;
    }

    // Claimable Vesting Schedules tests
    function test_createScheduleFromAmountAndDuration_executeCliffAndFlow_executeEndVesting_withClaim(
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 cliffPeriod,
        uint32 startDate,
        uint32 claimPeriod,
        uint8 randomizer
    ) public {
        // Assume
        randomizer = SafeCast.toUint8(bound(randomizer, 1, type(uint8).max));
        
        if (startDate != 0) {
            startDate = SafeCast.toUint32(bound(startDate, block.timestamp, 2524600800));
        }

        totalDuration = SafeCast.toUint32(bound(totalDuration, vestingScheduler.MIN_VESTING_DURATION(), 9125 days));
        vm.assume(cliffPeriod <= totalDuration - vestingScheduler.MIN_VESTING_DURATION());

        claimPeriod = SafeCast.toUint32(bound(claimPeriod, 1, 9125 days));
        vm.assume(claimPeriod > (cliffPeriod > 0 ? startDate + cliffPeriod : startDate));
        vm.assume(claimPeriod < totalDuration - vestingScheduler.END_DATE_VALID_BEFORE());

        BigTestData memory $;

        $.beforeSenderBalance = superToken.balanceOf(alice);
        $.beforeReceiverBalance = superToken.balanceOf(bob);

        totalAmount = bound(totalAmount, 1, $.beforeSenderBalance);
        vm.assume(totalAmount >= totalDuration);
        vm.assume(totalAmount / totalDuration <= SafeCast.toUint256(type(int96).max));

        assertTrue(vestingScheduler.getVestingSchedule(address(superToken), alice, bob).endDate == 0, "Schedule should not exist");

        // Arrange
        $.expectedSchedule = _getExpectedScheduleFromAmountAndDuration(
            totalAmount,
            totalDuration,
            cliffPeriod,
            startDate,
            claimPeriod
        );
        $.expectedCliffDate = cliffPeriod == 0 ? 0 : $.expectedSchedule.cliffAndFlowDate;
        $.expectedStartDate = startDate == 0 ? uint32(block.timestamp) : startDate;

        // Assume we're not getting liquidated at the end:
        vm.assume($.beforeSenderBalance >= totalAmount + vestingScheduler.END_DATE_VALID_BEFORE() * SafeCast.toUint256($.expectedSchedule.flowRate));

        console.log("Total amount: %s", totalAmount);
        console.log("Total duration: %s", totalDuration);
        console.log("Cliff period: %s", cliffPeriod);
        console.log("Claim period: %s", claimPeriod);
        console.log("Start date: %s", startDate);
        console.log("Randomizer: %s", randomizer);
        console.log("Expected start date: %s", $.expectedStartDate);
        console.log("Expected claim date: %s", $.expectedSchedule.claimValidityDate);
        console.log("Expected cliff date: %s", $.expectedCliffDate);
        console.log("Expected cliff & flow date: %s", $.expectedSchedule.cliffAndFlowDate);
        console.log("Expected end date: %s", $.expectedSchedule.endDate);
        console.log("Expected flow rate: %s", SafeCast.toUint256($.expectedSchedule.flowRate));
        console.log("Expected cliff amount: %s", $.expectedSchedule.cliffAmount);
        console.log("Expected remainder amount: %s", $.expectedSchedule.remainderAmount);
        console.log("Sender balance: %s", $.beforeSenderBalance);

        // Arrange allowance
        assertTrue(superToken.allowance(alice, address(vestingScheduler)) == 0, "Let's start without any allowance");

        vm.startPrank(alice);
        superToken.revokeFlowPermissions(address(vestingScheduler));
        superToken.setFlowPermissions(
            address(vestingScheduler),
            true, // allowCreate
            false, // allowUpdate
            true, // allowDelete,
            $.expectedSchedule.flowRate
        );
        superToken.approve(address(vestingScheduler), vestingScheduler.getMaximumNeededTokenAllowance($.expectedSchedule));
        vm.stopPrank();

        // Intermediary `mapCreateVestingScheduleParams` test
        assertAreScheduleCreationParamsEqual(
            IVestingSchedulerV2.ScheduleCreationParams(
                superToken,
                alice,
                bob,
                $.expectedStartDate,
                $.expectedSchedule.claimValidityDate,
                $.expectedCliffDate,
                $.expectedSchedule.flowRate,
                $.expectedSchedule.cliffAmount,
                $.expectedSchedule.endDate,
                $.expectedSchedule.remainderAmount
            ), 
            vestingScheduler.mapCreateVestingScheduleParams(superToken, alice, bob, totalAmount, totalDuration, $.expectedStartDate, cliffPeriod, claimPeriod));

        vm.expectEmit();
        emit VestingScheduleCreated(superToken, alice, bob, $.expectedStartDate, $.expectedCliffDate, $.expectedSchedule.flowRate, $.expectedSchedule.endDate, $.expectedSchedule.cliffAmount, $.expectedSchedule.claimValidityDate, $.expectedSchedule.remainderAmount);

        // Act
        vm.startPrank(alice);
        if (randomizer % 3 == 0) {
            console.log("Using the overload without superfluid context.");
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalAmount,
                totalDuration,
                startDate,
                cliffPeriod,
                claimPeriod
            );
        } else {
            console.log("Using the overload with superfluid context.");
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalAmount,
                totalDuration,
                startDate,
                cliffPeriod,
                claimPeriod,
                EMPTY_CTX
            );
        }
        vm.stopPrank();

        // Assert
        IVestingSchedulerV2.VestingSchedule memory actualSchedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertEq(actualSchedule.cliffAndFlowDate, $.expectedSchedule.cliffAndFlowDate, "schedule created: cliffAndFlowDate not expected");
        assertEq(actualSchedule.flowRate, $.expectedSchedule.flowRate, "schedule created: flowRate not expected");
        assertEq(actualSchedule.cliffAmount, $.expectedSchedule.cliffAmount, "schedule created: cliffAmount not expected");
        assertEq(actualSchedule.endDate, $.expectedSchedule.endDate, "schedule created: endDate not expected");
        assertEq(actualSchedule.remainderAmount, $.expectedSchedule.remainderAmount, "schedule created: remainderAmount not expected");
        assertEq(actualSchedule.claimValidityDate, $.expectedSchedule.claimValidityDate, "schedule created: claimValidityDate not expected");

        // Act
        console.log("Executing cliff and flow.");
        uint32 randomFlowDelay = ($.expectedSchedule.claimValidityDate - $.expectedSchedule.cliffAndFlowDate);
        vm.warp($.expectedSchedule.cliffAndFlowDate + randomFlowDelay);

        $.claimer = randomizer % 2 == 0 ? bob : alice;

        vm.prank($.claimer);
        vm.expectEmit();
        emit VestingClaimed(
            superToken, alice, bob, $.claimer
        );
        vm.expectEmit();
        emit VestingCliffAndFlowExecuted(superToken, alice, bob, $.expectedSchedule.cliffAndFlowDate, $.expectedSchedule.flowRate, $.expectedSchedule.cliffAmount, randomFlowDelay * SafeCast.toUint256($.expectedSchedule.flowRate));
        assertTrue(vestingScheduler.executeCliffAndFlow(superToken, alice, bob));
        vm.stopPrank();

        // Assert
        actualSchedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertEq(actualSchedule.cliffAndFlowDate, 0, "schedule started: cliffAndFlowDate not expected");
        assertEq(actualSchedule.cliffAmount, 0, "schedule started: cliffAmount not expected");
        assertEq(actualSchedule.flowRate, $.expectedSchedule.flowRate, "schedule started: flowRate not expected");
        assertEq(actualSchedule.endDate, $.expectedSchedule.endDate, "schedule started: endDate not expected");
        assertEq(actualSchedule.remainderAmount, $.expectedSchedule.remainderAmount, "schedule started: remainderAmount not expected");

        if (randomizer % 7 != 0) {
            // # Test end execution on time.

            console.log("Executing end vesting early.");
            uint32 randomEarlyEndTime = (vestingScheduler.END_DATE_VALID_BEFORE() - (vestingScheduler.END_DATE_VALID_BEFORE() / randomizer));
            vm.warp($.expectedSchedule.endDate - randomEarlyEndTime);
            vm.expectEmit();
            uint256 earlyEndCompensation = randomEarlyEndTime * SafeCast.toUint256($.expectedSchedule.flowRate) + $.expectedSchedule.remainderAmount;
            emit VestingEndExecuted(superToken, alice, bob, $.expectedSchedule.endDate, earlyEndCompensation, false);

            // Act
            assertTrue(vestingScheduler.executeEndVesting(superToken, alice, bob));

            // Assert
            $.afterSenderBalance = superToken.balanceOf(alice);
            $.afterReceiverBalance = superToken.balanceOf(bob);

            assertEq($.afterSenderBalance, $.beforeSenderBalance - totalAmount, "Sender balance should decrease by totalAmount");
            assertEq($.afterReceiverBalance, $.beforeReceiverBalance + totalAmount, "Receiver balance should increase by totalAmount");
        } else {
            // # Test end execution delayed.

            console.log("Executing end vesting late.");
            uint32 randomLateEndDelay = (totalDuration / randomizer);
            vm.warp($.expectedSchedule.endDate + randomLateEndDelay); // There is some chance of overflow here.

            if (randomizer % 13 == 0) {
                vm.startPrank(alice);
                superToken.deleteFlow(alice, bob);
                vm.stopPrank();

                vm.expectEmit();
                emit VestingEndFailed(superToken, alice, bob, $.expectedSchedule.endDate);
            } else {
                vm.expectEmit();
                emit VestingEndExecuted(superToken, alice, bob, $.expectedSchedule.endDate, 0, true);
            }

            // Act
            assertTrue(vestingScheduler.executeEndVesting(superToken, alice, bob));

            // Assert
            $.afterSenderBalance = superToken.balanceOf(alice);
            $.afterReceiverBalance = superToken.balanceOf(bob);

            assertLt($.afterSenderBalance, $.beforeSenderBalance - totalAmount + $.expectedSchedule.remainderAmount, "Sender balance should decrease by at least totalAmount");
            assertGt($.afterReceiverBalance, $.beforeReceiverBalance + totalAmount - $.expectedSchedule.remainderAmount, "Receiver balance should increase by at least totalAmount");
        }

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);

        vm.warp(type(uint32).max);
        assertEq($.afterSenderBalance, superToken.balanceOf(alice), "After the schedule has ended, the sender's balance should never change.");
    }

    function test_createScheduleFromAmountAndDuration_executeCliffAndFlow_executeEndVesting_withClaim_withSingleTransfer(
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 cliffPeriod,
        uint32 startDate,
        uint32 claimPeriod,
        uint8 randomizer
    ) public {
        // Assume
        randomizer = SafeCast.toUint8(bound(randomizer, 1, type(uint8).max));
        
        if (startDate != 0) {
            startDate = SafeCast.toUint32(bound(startDate, block.timestamp, 2524600800));
        }

        totalDuration = SafeCast.toUint32(bound(totalDuration, vestingScheduler.MIN_VESTING_DURATION(), 9125 days));
        vm.assume(cliffPeriod <= totalDuration - vestingScheduler.MIN_VESTING_DURATION());

        claimPeriod = SafeCast.toUint32(bound(claimPeriod, 1, 9125 days));
        vm.assume(claimPeriod > (startDate + totalDuration - vestingScheduler.END_DATE_VALID_BEFORE()));

        BigTestData memory $;

        $.beforeSenderBalance = superToken.balanceOf(alice);
        $.beforeReceiverBalance = superToken.balanceOf(bob);

        totalAmount = bound(totalAmount, 1, $.beforeSenderBalance);
        vm.assume(totalAmount >= totalDuration);
        vm.assume(totalAmount / totalDuration <= SafeCast.toUint256(type(int96).max));

        assertTrue(vestingScheduler.getVestingSchedule(address(superToken), alice, bob).endDate == 0, "Schedule should not exist");

        // Arrange
        $.expectedSchedule = _getExpectedScheduleFromAmountAndDuration(
            totalAmount,
            totalDuration,
            cliffPeriod,
            startDate,
            claimPeriod
        );
        $.expectedCliffDate = cliffPeriod == 0 ? 0 : $.expectedSchedule.cliffAndFlowDate;
        $.expectedStartDate = startDate == 0 ? uint32(block.timestamp) : startDate;

        // Assume we're not getting liquidated at the end:
        vm.assume($.beforeSenderBalance >= totalAmount + vestingScheduler.END_DATE_VALID_BEFORE() * SafeCast.toUint256($.expectedSchedule.flowRate));

        console.log("Total amount: %s", totalAmount);
        console.log("Total duration: %s", totalDuration);
        console.log("Cliff period: %s", cliffPeriod);
        console.log("Claim period: %s", claimPeriod);
        console.log("Start date: %s", startDate);
        console.log("Randomizer: %s", randomizer);
        console.log("Expected start date: %s", $.expectedStartDate);
        console.log("Expected claim date: %s", $.expectedSchedule.claimValidityDate);
        console.log("Expected cliff date: %s", $.expectedCliffDate);
        console.log("Expected cliff & flow date: %s", $.expectedSchedule.cliffAndFlowDate);
        console.log("Expected end date: %s", $.expectedSchedule.endDate);
        console.log("Expected flow rate: %s", SafeCast.toUint256($.expectedSchedule.flowRate));
        console.log("Expected cliff amount: %s", $.expectedSchedule.cliffAmount);
        console.log("Expected remainder amount: %s", $.expectedSchedule.remainderAmount);
        console.log("Sender balance: %s", $.beforeSenderBalance);

        // Arrange allowance
        assertTrue(superToken.allowance(alice, address(vestingScheduler)) == 0, "Let's start without any allowance");

        vm.startPrank(alice);
        superToken.revokeFlowPermissions(address(vestingScheduler));
        superToken.approve(address(vestingScheduler), vestingScheduler.getMaximumNeededTokenAllowance($.expectedSchedule));
        vm.stopPrank();

        // Intermediary `mapCreateVestingScheduleParams` test
        assertAreScheduleCreationParamsEqual(
            IVestingSchedulerV2.ScheduleCreationParams(
                superToken,
                alice,
                bob,
                $.expectedStartDate,
                $.expectedSchedule.claimValidityDate,
                $.expectedCliffDate,
                $.expectedSchedule.flowRate,
                $.expectedSchedule.cliffAmount,
                $.expectedSchedule.endDate,
                $.expectedSchedule.remainderAmount
            ), 
            vestingScheduler.mapCreateVestingScheduleParams(superToken, alice, bob, totalAmount, totalDuration, $.expectedStartDate, cliffPeriod, claimPeriod));

        vm.expectEmit();
        emit VestingScheduleCreated(superToken, alice, bob, $.expectedStartDate, $.expectedCliffDate, $.expectedSchedule.flowRate, $.expectedSchedule.endDate, $.expectedSchedule.cliffAmount, $.expectedSchedule.claimValidityDate, $.expectedSchedule.remainderAmount);

        // Act
        vm.startPrank(alice);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            totalAmount,
            totalDuration,
            startDate,
            cliffPeriod,
            claimPeriod,
            EMPTY_CTX
        );
        vm.stopPrank();

        // Assert
        IVestingSchedulerV2.VestingSchedule memory actualSchedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertEq(actualSchedule.cliffAndFlowDate, $.expectedSchedule.cliffAndFlowDate, "schedule created: cliffAndFlowDate not expected");
        assertEq(actualSchedule.flowRate, $.expectedSchedule.flowRate, "schedule created: flowRate not expected");
        assertEq(actualSchedule.cliffAmount, $.expectedSchedule.cliffAmount, "schedule created: cliffAmount not expected");
        assertEq(actualSchedule.endDate, $.expectedSchedule.endDate, "schedule created: endDate not expected");
        assertEq(actualSchedule.remainderAmount, $.expectedSchedule.remainderAmount, "schedule created: remainderAmount not expected");
        assertEq(actualSchedule.claimValidityDate, $.expectedSchedule.claimValidityDate, "schedule created: claimValidityDate not expected");

        // Act
        console.log("Executing cliff and flow.");
        vm.warp($.expectedSchedule.endDate - vestingScheduler.END_DATE_VALID_BEFORE() + 
            /* random delay: */ ($.expectedSchedule.claimValidityDate - ($.expectedSchedule.endDate - vestingScheduler.END_DATE_VALID_BEFORE())) / randomizer
        );

        $.claimer = randomizer % 2 == 0 ? bob : alice;

        vm.prank($.claimer);

        vm.expectEmit();
        emit VestingClaimed(
            superToken, alice, bob, $.claimer
        );
        vm.expectEmit();
        emit VestingCliffAndFlowExecuted(superToken, alice, bob, $.expectedSchedule.cliffAndFlowDate, 0, $.expectedSchedule.cliffAmount, totalAmount - $.expectedSchedule.cliffAmount);

        vm.expectEmit();
        emit VestingEndExecuted(superToken, alice, bob, $.expectedSchedule.endDate, 0, false);

        assertTrue(vestingScheduler.executeCliffAndFlow(superToken, alice, bob));
        vm.stopPrank();

        $.afterSenderBalance = superToken.balanceOf(alice);
        $.afterReceiverBalance = superToken.balanceOf(bob);

        assertEq($.afterSenderBalance, $.beforeSenderBalance - totalAmount, "Sender balance should decrease by totalAmount");
        assertEq($.afterReceiverBalance, $.beforeReceiverBalance + totalAmount, "Receiver balance should increase by totalAmount");

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);

        vm.warp(type(uint32).max);
        assertEq($.afterSenderBalance, superToken.balanceOf(alice), "After the schedule has ended, the sender's balance should never change.");
    }

    function test_createAndExecuteVestingScheduleFromAmountAndDuration(uint256 _totalAmount,  uint32 _totalDuration) public {

        _totalDuration = SafeCast.toUint32(bound(_totalDuration, uint32(7 days), uint32(365 days)));
        _totalAmount = bound(_totalAmount, 1 ether, 100 ether);

        int96 flowRate = SafeCast.toInt96(
            SafeCast.toInt256(_totalAmount / _totalDuration)
        );

        uint96 remainderAmount = SafeCast.toUint96(
            _totalAmount - (SafeCast.toUint256(flowRate) * _totalDuration)
        );

        _setACL_AUTHORIZE_FULL_CONTROL(alice, flowRate);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, uint32(block.timestamp), 0, flowRate, uint32(block.timestamp) + _totalDuration, 0, 0, remainderAmount);

        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(superToken, alice, bob, uint32(block.timestamp), flowRate, 0, 0);

        vestingScheduler.createAndExecuteVestingScheduleFromAmountAndDuration(superToken, bob, _totalAmount, _totalDuration, EMPTY_CTX);

        vm.stopPrank();
    }

    function test_createAndExecuteVestingScheduleFromAmountAndDuration_noCtx(uint256 _totalAmount,  uint32 _totalDuration) public {
        _totalDuration = SafeCast.toUint32(bound(_totalDuration, uint32(7 days), uint32(365 days)));
        _totalAmount = bound(_totalAmount, 1 ether, 100 ether);

        int96 flowRate = SafeCast.toInt96(
            SafeCast.toInt256(_totalAmount / _totalDuration)
        );

        uint96 remainderAmount = SafeCast.toUint96(
            _totalAmount - (SafeCast.toUint256(flowRate) * _totalDuration)
        );

        _setACL_AUTHORIZE_FULL_CONTROL(alice, flowRate);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, uint32(block.timestamp), 0, flowRate, uint32(block.timestamp) + _totalDuration, 0, 0, remainderAmount);

        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(superToken, alice, bob, uint32(block.timestamp), flowRate, 0, 0);

        vestingScheduler.createAndExecuteVestingScheduleFromAmountAndDuration(superToken, bob, _totalAmount, _totalDuration);

        vm.stopPrank();
    }

 
    function test_createClaimableVestingSchedule() public {

        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, CLAIM_VALIDITY_DATE, 0);

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            CLAIM_VALIDITY_DATE,
            EMPTY_CTX
        );
        vm.stopPrank();

        vm.startPrank(alice);
        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE , "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE , "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE , "schedule.flowRate");
        assertTrue(schedule.claimValidityDate ==  CLAIM_VALIDITY_DATE, "schedule.claimValidityDate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT , "schedule.cliffAmount");
    }

    function test_createClaimableVestingSchedule_claimValidity() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, CLAIM_VALIDITY_DATE, 0);

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            CLAIM_VALIDITY_DATE,
            EMPTY_CTX
        );
        vm.stopPrank();

        vm.startPrank(alice);
        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE , "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE , "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE , "schedule.flowRate");
        assertTrue(schedule.claimValidityDate ==  CLAIM_VALIDITY_DATE, "schedule.claimValidityDate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT , "schedule.cliffAmount");
    }

    function test_createClaimableVestingSchedule_noCtx() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, CLAIM_VALIDITY_DATE, 0);

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            CLAIM_VALIDITY_DATE
        );
        vm.stopPrank();

        vm.startPrank(alice);
        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE , "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE , "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE , "schedule.flowRate");
        assertTrue(schedule.claimValidityDate == CLAIM_VALIDITY_DATE, "schedule.flowRate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT , "schedule.cliffAmount");
    }

    function test_createClaimableVestingSchedule_wrongData() public {
        vm.startPrank(alice);
        // revert with superToken = 0
        vm.expectRevert(IVestingSchedulerV2.ZeroAddress.selector);
        vestingScheduler.createVestingSchedule(
                ISuperToken(address(0)),
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with receivers = sender
        vm.expectRevert(IVestingSchedulerV2.AccountInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                alice,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with receivers = address(0)
        vm.expectRevert(IVestingSchedulerV2.AccountInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                address(0),
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with flowRate = 0
        vm.expectRevert(IVestingSchedulerV2.FlowRateInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                0,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with cliffDate = 0 but cliffAmount != 0
        vm.expectRevert(IVestingSchedulerV2.CliffInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            0,
            0,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            CLAIM_VALIDITY_DATE,
            EMPTY_CTX
        );

        // revert with startDate < block.timestamp && cliffDate = 0
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                uint32(block.timestamp - 1),
                0,
                FLOW_RATE,
                0,
                END_DATE,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with endDate = 0
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                0,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with cliffAndFlowDate < block.timestamp
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                0,
                uint32(block.timestamp) - 1,
                FLOW_RATE,
                0,
                END_DATE,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with cliffAndFlowDate >= endDate
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                CLIFF_DATE,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with cliffAndFlowDate + startDateValidFor >= endDate - endDateValidBefore
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                CLIFF_DATE,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with startDate > cliffDate
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                CLIFF_DATE + 1,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );


        // revert with vesting duration < 7 days
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                CLIFF_DATE + 2 days,
                CLAIM_VALIDITY_DATE,
                EMPTY_CTX
        );

        // revert with invalid claim validity date (before schedule/cliff start)
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
                superToken,
                bob,
                START_DATE,
                CLIFF_DATE,
                FLOW_RATE,
                CLIFF_TRANSFER_AMOUNT,
                END_DATE,
                CLIFF_DATE - 1,
                EMPTY_CTX
        );
    }

    function test_createClaimableVestingSchedule_dataExists() public {
        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            CLAIM_VALIDITY_DATE,
            EMPTY_CTX
        );
        vm.stopPrank();

        vm.expectRevert(IVestingSchedulerV2.ScheduleAlreadyExists.selector);

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            CLAIM_VALIDITY_DATE,
            EMPTY_CTX
        );
        vm.stopPrank();

    }

    function test_createClaimableVestingScheduleFromAmountAndDuration_withoutCliff(uint8 randomizer) public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();

        uint32 startDate = uint32(block.timestamp);
        uint256 totalVestedAmount = 105_840_000; // a value perfectly divisible by a week
        uint32 vestingDuration = 1 weeks;
        uint32 claimPeriod = 1 days;
        int96 expectedFlowRate = 175; // totalVestedAmount / vestingDuration
        uint32 expectedEndDate = startDate + vestingDuration;

        vm.expectEmit();
        emit VestingScheduleCreated(superToken, alice, bob, startDate, 0, expectedFlowRate, expectedEndDate, 0, startDate + claimPeriod, 0);
        vm.startPrank(alice);
        bool useCtx = randomizer % 2 == 0;
        if (useCtx) {
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalVestedAmount,
                vestingDuration,
                startDate,
                0, // cliffPeriod
                claimPeriod,
                EMPTY_CTX
            );
        } else {
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalVestedAmount,
                vestingDuration,
                startDate,
                0, // cliffPeriod
                claimPeriod
            );
        }
        vm.stopPrank();
    }

    function test_createClaimableVestingScheduleFromAmountAndDuration_withoutCliff_noStartDate() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();

        uint256 totalVestedAmount = 105_840_000; // a value perfectly divisible by a week
        uint32 vestingDuration = 1 weeks;
        uint32 claimPeriod = 2 days;
        int96 expectedFlowRate = 175; // totalVestedAmount / vestingDuration
        uint32 expectedEndDate = uint32(block.timestamp) + vestingDuration;

        vm.expectEmit();
        emit VestingScheduleCreated(
            superToken, 
            alice, 
            bob, 
            uint32(block.timestamp), 
            0, 
            expectedFlowRate, 
            expectedEndDate, 
            0, 
            uint32(block.timestamp) + claimPeriod, 
            0
        );

        vm.startPrank(alice);

        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            totalVestedAmount,
            vestingDuration,
            0,
            0,
            claimPeriod
        );
        vm.stopPrank();
    }

    function test_createClaimableVestingScheduleFromAmountAndDuration_withCliff(uint8 randomizer) public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();

        uint32 startDate = uint32(block.timestamp);
        uint256 totalVestedAmount = 103_680_000; // a value perfectly divisible
        uint32 vestingDuration = 1 weeks + 1 days;
        uint32 cliffPeriod = 1 days;
        uint32 claimPeriod = cliffPeriod + 1 days;

        int96 expectedFlowRate = 150; // (totalVestedAmount - cliffAmount) / (vestingDuration - cliffPeriod)

        vm.expectEmit();
        emit VestingScheduleCreated(superToken, alice, bob, startDate, startDate + cliffPeriod, expectedFlowRate, startDate + vestingDuration, 12960000, startDate + claimPeriod, 0);

        vm.startPrank(alice);
        bool useCtx = randomizer % 2 == 0;
        if (useCtx) {
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalVestedAmount,
                vestingDuration,
                startDate,
                cliffPeriod,
                claimPeriod,
                EMPTY_CTX
            );
        } else {
            vestingScheduler.createVestingScheduleFromAmountAndDuration(
                superToken,
                bob,
                totalVestedAmount,
                vestingDuration,
                startDate,
                cliffPeriod,
                claimPeriod
            );
        }
        vm.stopPrank();
    }
    
    function test_createClaimableVestingScheduleFromAmountAndDuration_withCliff_noStartDate() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();

        uint256 totalVestedAmount = 103_680_000; // a value perfectly divisible
        uint32 vestingDuration = 1 weeks + 1 days;
        uint32 cliffPeriod = 1 days;

        int96 expectedFlowRate = 150; // (totalVestedAmount - cliffAmount) / (vestingDuration - cliffPeriod)
        uint256 expectedCliffAmount = 12960000;
        uint32 expectedCliffDate = uint32(block.timestamp) + cliffPeriod;
        uint32 claimPeriod = expectedCliffDate + 1 days;
        uint32 expectedEndDate = uint32(block.timestamp) + vestingDuration;

        vm.expectEmit();
        emit VestingScheduleCreated(superToken, alice, bob, uint32(block.timestamp), expectedCliffDate, expectedFlowRate, expectedEndDate, expectedCliffAmount, uint32(block.timestamp) + claimPeriod, 0);

        vm.startPrank(alice);

        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            totalVestedAmount,
            vestingDuration,
            0,
            cliffPeriod,
            claimPeriod
        );

        vm.stopPrank();
    }

    function test_createClaimableScheduleFromAmountAndDuration_wrongData() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.expectRevert(IVestingSchedulerV2.FlowRateInvalid.selector);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            0, // amount 
            1209600, // duration
            uint32(block.timestamp), // startDate
            604800, // cliffPeriod
            15 days, // claimPeriod
            EMPTY_CTX
        );

        console.log("Revert with cliff and start in history.");
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            1 ether, // amount
            1209600, // duration
            uint32(block.timestamp - 1), // startDate
            0, // cliffPeriod
            15 days, // claimPeriod
            EMPTY_CTX
        );

        console.log("Revert with overflow.");
        vm.expectRevert("SafeCast: value doesn't fit in 96 bits"); 
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            type(uint256).max, // amount
            1209600, // duration
            uint32(block.timestamp), // startDate
            0, // cliffPeriod
            15 days, // claimPeriod
            EMPTY_CTX
        );

        console.log("Revert with underflow/overflow.");
        vm.expectRevert(); // todo: the right error
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            1 ether, // amount
            type(uint32).max, // duration
            uint32(block.timestamp), // startDate
            0, // cliffPeriod
            15 days, // claimPeriod
            EMPTY_CTX
        );

        console.log("Revert with start date in history.");
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            1 ether, // amount
            1209600, // duration
            uint32(block.timestamp - 1), // startDate
            604800, // cliffPeriod
            15 days, // claimPeriod
            EMPTY_CTX
        );
    }

    function test_executeCliffAndFlow_claimableScheduleWithCliffAmount_receiverClaim() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createClaimableVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        uint256 initialTimestamp = block.timestamp + 10 days + 1800;
        vm.warp(initialTimestamp);
        uint256 flowDelayCompensation = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, CLIFF_TRANSFER_AMOUNT + flowDelayCompensation);
        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, flowDelayCompensation
        );

        vm.prank(bob);
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

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function test_executeCliffAndFlow_claimAfterEndDate(uint256 delayAfterEndDate, uint256 claimDate, uint8 randomizer) public {
        randomizer = SafeCast.toUint8(bound(randomizer, 1, type(uint8).max));

        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        uint256 totalExpectedAmount = CLIFF_TRANSFER_AMOUNT +
            (END_DATE - CLIFF_DATE) * 
            SafeCast.toUint256(FLOW_RATE);

        delayAfterEndDate = bound(delayAfterEndDate, 1, 1e8);
        claimDate = bound(claimDate, END_DATE - vestingScheduler.END_DATE_VALID_BEFORE(), END_DATE + delayAfterEndDate);

        _createClaimableVestingScheduleWithClaimDateAfterEndDate(alice, bob, delayAfterEndDate);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        
        vm.warp(claimDate);

        address claimer = randomizer % 2 == 0 ? bob : alice;
        vm.expectEmit(true, true, true, false);
        emit VestingClaimed(
            superToken, alice, bob, claimer
        );

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, totalExpectedAmount);

        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, CLIFF_DATE, 0, CLIFF_TRANSFER_AMOUNT, totalExpectedAmount - CLIFF_TRANSFER_AMOUNT
        );

        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(
            superToken, alice, bob, END_DATE, 0, false
        );

        IVestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertEq(vestingScheduler.getMaximumNeededTokenAllowance(schedule), totalExpectedAmount);

        vm.prank(claimer);
        assertTrue(vestingScheduler.executeCliffAndFlow(superToken, alice, bob));

        assertEq(superToken.balanceOf(alice), aliceInitialBalance - totalExpectedAmount);
        assertEq(superToken.balanceOf(bob), bobInitialBalance + totalExpectedAmount);

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function test_executeCliffAndFlow_claimableScheduleWithCliffAmount_senderClaim() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createClaimableVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
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
        vm.stopPrank();
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

    function test_executeCliffAndFlow_claimableScheduleWithCliffAmount_cannotClaimOnBehalf(address _claimer) public {
        vm.assume(_claimer != address(0) && _claimer != alice && _claimer != bob);
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createClaimableVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        uint256 initialTimestamp = block.timestamp + 10 days + 1800;
        vm.warp(initialTimestamp);
        vm.prank(_claimer);
        vm.expectRevert(IVestingSchedulerV2.CannotClaimScheduleOnBehalf.selector);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertEq(success, false);
    }

    function test_executeCliffAndFlow_claimableScheduleWithCliffAmount_claimBeforeStart() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createClaimableVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        uint256 startTimestamp = vestingScheduler.getVestingSchedule(address(superToken), alice, bob).cliffAndFlowDate; 
        vm.warp(startTimestamp - 1);

        vm.prank(bob);
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertEq(success, false);
    }

    function test_executeCliffAndFlow_claimableScheduleWithCliffAmount_claimAfterValidityDate() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createClaimableVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.warp(CLAIM_VALIDITY_DATE + 1);
        vm.prank(bob);
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertEq(success, false);
    }

    function test_executeCliffAndFlow_cannotReexecute() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createClaimableVestingScheduleWithDefaultData(alice, bob);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.warp(CLAIM_VALIDITY_DATE - 1);
        vm.startPrank(bob);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertEq(success, true);
        vm.expectRevert(IVestingSchedulerV2.AlreadyExecuted.selector);
        success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertEq(success, false);
        vm.stopPrank();
    }

    function test_getMaximumNeededTokenAllowance_should_end_with_zero_if_extreme_ranges_are_used(
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 cliffPeriod,
        uint32 startDate,
        uint8 randomizer
    ) public {
        // Assume
        randomizer = SafeCast.toUint8(bound(randomizer, 1, type(uint8).max));
        
        if (startDate != 0) {
            startDate = SafeCast.toUint32(bound(startDate, block.timestamp, 2524600800));
        }

        totalDuration = SafeCast.toUint32(bound(totalDuration, vestingScheduler.MIN_VESTING_DURATION(), 18250 days));
        vm.assume(cliffPeriod <= totalDuration - vestingScheduler.MIN_VESTING_DURATION());

        uint256 beforeSenderBalance = superToken.balanceOf(alice);

        totalAmount = bound(totalAmount, 1, beforeSenderBalance);
        vm.assume(totalAmount >= totalDuration);
        vm.assume(totalAmount / totalDuration <= SafeCast.toUint256(type(int96).max));

        // Arrange
        IVestingSchedulerV2.VestingSchedule memory expectedSchedule = _getExpectedScheduleFromAmountAndDuration(
            totalAmount,
            totalDuration,
            cliffPeriod,
            startDate,
            0
        );

        // Assume we're not getting liquidated at the end:
        vm.assume(beforeSenderBalance >= totalAmount + vestingScheduler.END_DATE_VALID_BEFORE() * SafeCast.toUint256(expectedSchedule.flowRate));

        // Arrange allowance
        vm.assume(superToken.allowance(alice, address(vestingScheduler)) == 0);

        vm.startPrank(alice);
        superToken.revokeFlowPermissions(address(vestingScheduler));
        superToken.setFlowPermissions(
            address(vestingScheduler),
            true, // allowCreate
            false, // allowUpdate
            true, // allowDelete,
            expectedSchedule.flowRate
        );
        superToken.approve(address(vestingScheduler), vestingScheduler.getMaximumNeededTokenAllowance(expectedSchedule));
        vm.stopPrank();

        // Act
        vm.startPrank(alice);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            totalAmount,
            totalDuration,
            startDate,
            cliffPeriod,
            0,
            EMPTY_CTX
        );
        vm.stopPrank();

        // Act
        vm.warp(expectedSchedule.cliffAndFlowDate + (vestingScheduler.START_DATE_VALID_AFTER()));
        assertTrue(vestingScheduler.executeCliffAndFlow(superToken, alice, bob));

        if (randomizer % 2 == 0) {
            // Let's set the allowance again half-way through.
            vm.startPrank(alice);
            superToken.approve(address(vestingScheduler), vestingScheduler.getMaximumNeededTokenAllowance(vestingScheduler.getVestingSchedule(address(superToken), alice, bob)));
            vm.stopPrank();
        }

        // Act
        vm.warp(expectedSchedule.endDate - (vestingScheduler.END_DATE_VALID_BEFORE()));
        assertTrue(vestingScheduler.executeEndVesting(superToken, alice, bob));

        // Assert
        assertEq(superToken.allowance(alice, address(vestingScheduler)), 0, "No allowance should be left");
        (,,,int96 flowRateAllowance) = superToken.getFlowPermissions(alice, address(vestingScheduler));
        assertEq(flowRateAllowance, 0, "No flow rate allowance should be left");

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function test_executeEndVesting_scheduleNotClaimed() public {
        _createClaimableVestingScheduleWithDefaultData(alice, bob);
        vm.expectRevert(IVestingSchedulerV2.ScheduleNotClaimed.selector);
        vestingScheduler.executeEndVesting(superToken, alice, bob);
    }

    function test_getMaximumNeededTokenAllowance_with_claim_should_end_with_zero_if_extreme_ranges_are_used(
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 cliffPeriod,
        uint32 startDate,
        uint32 claimPeriod,
        uint8 randomizer
    ) public {
        // Assume
        randomizer = SafeCast.toUint8(bound(randomizer, 1, type(uint8).max));
        
        if (startDate != 0) {
            startDate = SafeCast.toUint32(bound(startDate, block.timestamp, 2524600800));
        }

        claimPeriod = SafeCast.toUint32(bound(claimPeriod, 1, 18250 days));
        vm.assume(claimPeriod >= cliffPeriod);

        totalDuration = SafeCast.toUint32(bound(totalDuration, vestingScheduler.MIN_VESTING_DURATION(), 18250 days));
        vm.assume(cliffPeriod <= totalDuration - vestingScheduler.MIN_VESTING_DURATION());

        uint256 beforeSenderBalance = superToken.balanceOf(alice);

        totalAmount = bound(totalAmount, 1, beforeSenderBalance);
        vm.assume(totalAmount >= totalDuration);
        vm.assume(totalAmount / totalDuration <= SafeCast.toUint256(type(int96).max));

        // Arrange
        IVestingSchedulerV2.VestingSchedule memory expectedSchedule = _getExpectedScheduleFromAmountAndDuration(
            totalAmount,
            totalDuration,
            cliffPeriod,
            startDate,
            claimPeriod
        );

        // Assume we're not getting liquidated at the end:
        vm.assume(beforeSenderBalance >= totalAmount + vestingScheduler.END_DATE_VALID_BEFORE() * SafeCast.toUint256(expectedSchedule.flowRate));

        // Arrange allowance
        vm.assume(superToken.allowance(alice, address(vestingScheduler)) == 0);

        vm.startPrank(alice);
        superToken.revokeFlowPermissions(address(vestingScheduler));
        bool willThereBeFullTransfer = expectedSchedule.claimValidityDate >= expectedSchedule.endDate - vestingScheduler.END_DATE_VALID_BEFORE();
        if (!willThereBeFullTransfer) {
            // No flow needed in this case.
            superToken.setFlowPermissions(
                address(vestingScheduler),
                true, // allowCreate
                false, // allowUpdate
                true, // allowDelete,
                expectedSchedule.flowRate
            );
        }
        superToken.approve(address(vestingScheduler), vestingScheduler.getMaximumNeededTokenAllowance(expectedSchedule));
        vm.stopPrank();

        // Act
        vm.startPrank(alice);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            totalAmount,
            totalDuration,
            startDate,
            cliffPeriod,
            claimPeriod,
            EMPTY_CTX
        );
        vm.stopPrank();

        // Act
        vm.warp(expectedSchedule.claimValidityDate);
        vm.startPrank(randomizer % 3 == 0 ? alice : bob); // Both sender and receiver can execute
        assertTrue(vestingScheduler.executeCliffAndFlow(superToken, alice, bob));
        vm.stopPrank();

        if (randomizer % 2 == 0) {
            // Let's set the allowance again half-way through.
            vm.startPrank(alice);
            superToken.approve(address(vestingScheduler), vestingScheduler.getMaximumNeededTokenAllowance(vestingScheduler.getVestingSchedule(address(superToken), alice, bob)));
            vm.stopPrank();
        }

        // Act
        if (!willThereBeFullTransfer) {
            vm.warp(expectedSchedule.endDate - vestingScheduler.END_DATE_VALID_BEFORE());
            assertTrue(vestingScheduler.executeEndVesting(superToken, alice, bob));
        }

        // Assert
        assertEq(superToken.allowance(alice, address(vestingScheduler)), 0, "No allowance should be left");
        (,,,int96 flowRateAllowance) = superToken.getFlowPermissions(alice, address(vestingScheduler));
        assertEq(flowRateAllowance, 0, "No flow rate allowance should be left");

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function test_getSender_throws_when_invalid_host() public {
        vm.expectRevert(IVestingSchedulerV2.HostInvalid.selector);

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            0,
            NON_EMPTY_CTX
        );
        vm.stopPrank();
    }

    function test_getSender_works_in_a_batch_call() public {
        // Create a vesting schedule to update with a batch call that uses the context
        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            0,
            EMPTY_CTX
        );
        _arrangeAllowances(alice, FLOW_RATE); 
        vm.stopPrank();

        vm.warp(CLIFF_DATE != 0 ? CLIFF_DATE : START_DATE);
        vestingScheduler.executeCliffAndFlow(superToken, alice, bob);

        uint32 newEndDate = type(uint32).max - 1234;

        // Setting up a batch call. Superfluid Protocol will replace the emtpy context with data about the sender. That's where the sender is retrieved from.
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_APP_ACTION,
            target: address(vestingScheduler),
            data: abi.encodeCall(vestingScheduler.updateVestingSchedule, (superToken, bob, newEndDate, EMPTY_CTX))
        });

        // Act
        vm.prank(alice);
        sf.host.batchCall(ops);
        vm.stopPrank();

        // Assert
        IVestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertEq(schedule.endDate, newEndDate);
    }
}
