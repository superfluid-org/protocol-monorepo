// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {
    FlowOperatorDefinitions,
    ISuperfluid,
    BatchOperation,
    ISuperApp
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IVestingSchedulerV2} from "./../contracts/interface/IVestingSchedulerV2.sol";
import {IVestingSchedulerV3} from "./../contracts/interface/IVestingSchedulerV3.sol";
import {VestingSchedulerV3} from "./../contracts/VestingSchedulerV3.sol";
import {FoundrySuperfluidTester} from
    "@superfluid-finance/ethereum-contracts/test/foundry/FoundrySuperfluidTester.t.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "forge-std/console.sol";

/// @title VestingSchedulerTests
/// @notice Look at me , I am the captain now - Elvijs
contract VestingSchedulerV3Tests is FoundrySuperfluidTester {
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
        uint32 endDate,
        uint96 remainderAmount,
        int96 flowRate,
        uint256 totalAmount,
        uint256 settledAmount
    );

    event VestingScheduleDeleted(ISuperToken indexed superToken, address indexed sender, address indexed receiver);

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
        ISuperToken indexed superToken, address indexed sender, address indexed receiver, uint32 endDate
    );

    event VestingClaimed(
        ISuperToken indexed superToken, address indexed sender, address indexed receiver, address claimer
    );

    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @dev This is required by solidity for using the SuperTokenV1Library in the tester
    VestingSchedulerV3 public vestingScheduler;

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
        vestingScheduler = new VestingSchedulerV3(sf.host);
    }

    /// SETUP AND HELPERS
    function setUp() public virtual override {
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
            superToken, receiver, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, 0
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
            CLAIM_VALIDITY_DATE
        );
        vm.stopPrank();
    }

    function _createClaimableVestingScheduleWithClaimDateAfterEndDate(
        address sender,
        address receiver,
        uint256 delayAfterEndDate
    ) private {
        vm.startPrank(sender);
        vestingScheduler.createVestingSchedule(
            superToken,
            receiver,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            CLIFF_TRANSFER_AMOUNT,
            END_DATE,
            END_DATE + uint32(delayAfterEndDate)
        );
        vm.stopPrank();
    }

    function assertAreScheduleCreationParamsEqual(
        IVestingSchedulerV3.ScheduleCreationParams memory params1,
        IVestingSchedulerV3.ScheduleCreationParams memory params2
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

    function testAssertScheduleDoesNotExist(address superToken, address sender, address receiver) public view {
        VestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(superToken, sender, receiver);
        VestingSchedulerV3.VestingSchedule memory deletedSchedule;

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
    ) public view returns (IVestingSchedulerV3.VestingSchedule memory expectedSchedule) {
        if (startDate == 0) {
            startDate = uint32(block.timestamp);
        }

        uint32 cliffAndFlowDate = cliffDate == 0 ? startDate : cliffDate;

        expectedSchedule = IVestingSchedulerV3.VestingSchedule({
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
    ) public view returns (IVestingSchedulerV3.VestingSchedule memory expectedSchedule) {
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

        expectedSchedule = IVestingSchedulerV3.VestingSchedule({
            cliffAndFlowDate: cliffAndFlowDate,
            endDate: endDate,
            flowRate: flowRate,
            cliffAmount: cliffAmount,
            remainderAmount: remainderAmount,
            claimValidityDate: claimPeriod == 0 ? 0 : startDate + claimPeriod
        });
    }

    /// TESTS

    function testCreateVestingSchedule() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0
        );

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE
        );
        vm.stopPrank();

        //assert storage data
        VestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE, "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE, "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE, "schedule.flowRate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT, "schedule.cliffAmount");
    }

    function test_createVestingSchedule_v1_overload() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0
        );
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        //assert storage data
        VestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE, "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE, "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE, "schedule.flowRate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT, "schedule.cliffAmount");
    }

    function testCannotCreateVestingScheduleWithWrongData() public {
        vm.startPrank(alice);
        // revert with superToken = 0
        vm.expectRevert(IVestingSchedulerV2.ZeroAddress.selector);
        vestingScheduler.createVestingSchedule(
            ISuperToken(address(0)), bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, 0
        );

        // revert with receivers = sender
        vm.expectRevert(IVestingSchedulerV2.AccountInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, alice, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, 0
        );

        // revert with receivers = address(0)
        vm.expectRevert(IVestingSchedulerV2.AccountInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, address(0), START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, 0
        );

        // revert with flowRate = 0
        vm.expectRevert(IVestingSchedulerV2.FlowRateInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, 0, CLIFF_TRANSFER_AMOUNT, END_DATE, 0
        );

        // revert with cliffDate = 0 but cliffAmount != 0
        vm.expectRevert(IVestingSchedulerV2.CliffInvalid.selector);
        vestingScheduler.createVestingSchedule(superToken, bob, 0, 0, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, 0);

        // revert with startDate < block.timestamp && cliffDate = 0
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, uint32(block.timestamp - 1), 0, FLOW_RATE, 0, END_DATE, 0
        );

        // revert with endDate = 0
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, 0, 0
        );

        // revert with cliffAndFlowDate < block.timestamp
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, 0, uint32(block.timestamp) - 1, FLOW_RATE, 0, END_DATE, 0
        );

        // revert with cliffAndFlowDate >= endDate
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, CLIFF_DATE, 0
        );

        // revert with cliffAndFlowDate + startDateValidFor >= endDate - endDateValidBefore
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, CLIFF_DATE, 0
        );

        // revert with startDate > cliffDate
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, CLIFF_DATE + 1, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, 0
        );

        // revert with vesting duration < 7 days
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, CLIFF_DATE + 2 days, 0
        );
    }

    function testCannotCreateVestingScheduleIfDataExist() public {
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.expectRevert(IVestingSchedulerV2.ScheduleAlreadyExists.selector);
        _createVestingScheduleWithDefaultData(alice, bob);
    }

    function testUdateVestingScheduleFlowRateFromAmountAndEndDate() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, type(int96).max);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0
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
        vestingScheduler.updateVestingScheduleFlowRateFromAmountAndEndDate(
            superToken, bob, CLIFF_TRANSFER_AMOUNT * 2, uint32(END_DATE + 1000)
        );

        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

        int96 expectedFlowRate = SafeCast.toInt96(
            SafeCast.toInt256((CLIFF_TRANSFER_AMOUNT * 2 - CLIFF_TRANSFER_AMOUNT) / (END_DATE + 1000 - block.timestamp))
        );
        //assert storage data
        assertTrue(schedule.cliffAndFlowDate == 0, "schedule.cliffAndFlowDate");
        assertApproxEqAbs(schedule.flowRate, expectedFlowRate, 1e10, "schedule.flowRate");
        assertTrue(schedule.endDate == END_DATE + 1000, "schedule.endDate");
    }

    function testUpdateVestingScheduleFlowRateFromEndDate() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0
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
        vestingScheduler.updateVestingScheduleFlowRateFromEndDate(superToken, bob, uint32(END_DATE + 1000));
        //assert storage data
        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == 0, "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE + 1000, "schedule.endDate");
    }

    function test_updateVestingScheduleFlowRateFromEndDate_invalidTimeWindow() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, CLAIM_VALIDITY_DATE, 0
        );
        _createClaimableVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        uint256 beforeCliffAndFlowDate = CLIFF_DATE - 30 minutes;
        vm.warp(beforeCliffAndFlowDate);

        // Schedule update is not allowed if : "the cliff and flow date is in the future"
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.updateVestingScheduleFlowRateFromEndDate(superToken, bob, END_DATE + 1 hours);

        uint256 afterCliffAndFlowDate = CLIFF_DATE + 30 minutes;
        vm.warp(afterCliffAndFlowDate);

        // Schedule update is not allowed if : "the new end date is in the past"
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.updateVestingScheduleFlowRateFromEndDate(superToken, bob, uint32(afterCliffAndFlowDate - 1));

        uint256 afterEndDate = END_DATE + 1 hours;
        vm.warp(afterEndDate);

        // Schedule update is not allowed if : "the current end date has passed"
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.updateVestingScheduleFlowRateFromEndDate(superToken, bob, uint32(afterEndDate));

        // Schedule update is not allowed if : "the current claim validity date has passed"
        uint256 afterClaimValidityDate = CLAIM_VALIDITY_DATE + 1 hours;
        vm.warp(afterClaimValidityDate);
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.updateVestingScheduleFlowRateFromEndDate(superToken, bob, uint32(afterClaimValidityDate));

        vm.stopPrank();
    }

    function test_updateVestingScheduleFlowRateFromAmount_invalidParameters() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0
        );
        _createVestingScheduleWithDefaultData(alice, bob);

        uint256 newAmount = CLIFF_TRANSFER_AMOUNT + (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE) + 10 ether;

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        uint256 beforeCliffAndFlowDate = CLIFF_DATE - 30 minutes;
        vm.warp(beforeCliffAndFlowDate);

        // Schedule update is not allowed if : "the cliff and flow date is in the future"
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, newAmount);

        uint256 afterCliffAndFlowDate = CLIFF_DATE + 30 minutes;
        vm.warp(afterCliffAndFlowDate);

        // Amount is invalid if it is less than the already vested amount
        uint256 invalidNewAmount = CLIFF_TRANSFER_AMOUNT;
        vm.expectRevert(IVestingSchedulerV3.InvalidNewTotalAmount.selector);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, invalidNewAmount);

        uint256 afterEndDate = END_DATE + 1 hours;
        vm.warp(afterEndDate);

        // Schedule update is not allowed if : "the current end date has passed"
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, newAmount);

        vm.stopPrank();
    }

    function testCannotUpdateVestingScheduleIfDataDontExist(uint256 newAmount) public {
        vm.startPrank(alice);
        vm.expectRevert(IVestingSchedulerV2.ScheduleDoesNotExist.selector);
        vestingScheduler.updateVestingScheduleFlowRateFromEndDate(superToken, bob, END_DATE);

        newAmount = bound(newAmount, 1, type(uint256).max);
        vm.expectRevert(IVestingSchedulerV2.ScheduleDoesNotExist.selector);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, newAmount);
        vm.stopPrank();
    }

    function testUpdateVestingSchedule() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken, alice, bob, START_DATE, CLIFF_DATE, FLOW_RATE, END_DATE, CLIFF_TRANSFER_AMOUNT, 0, 0
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
        vestingScheduler.updateVestingScheduleFlowRateFromEndDate(superToken, bob, END_DATE + 1000);
        //assert storage data
        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == 0, "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE + 1000, "schedule.endDate");
    }

    function testDeleteVestingSchedule() public {
        _createVestingScheduleWithDefaultData(alice, bob);
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleDeleted(superToken, alice, bob);
        vestingScheduler.deleteVestingSchedule(superToken, bob);
        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function testCannotDeleteVestingScheduleIfDataDontExist() public {
        vm.startPrank(alice);
        vm.expectRevert(IVestingSchedulerV2.ScheduleDoesNotExist.selector);
        vestingScheduler.deleteVestingSchedule(superToken, bob);
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
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, adjustedAmountClosing, false);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;
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
        vestingScheduler.createVestingSchedule(superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, 0, END_DATE, 0);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(admin);
        vm.warp(CLIFF_DATE);
        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(superToken, alice, bob, CLIFF_DATE, FLOW_RATE, 0, 0);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(success, "executeVesting should return true");
        vm.warp(END_DATE);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, 0, false);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE);
        assertEq(aliceInitialBalance - aliceFinalBalance, aliceShouldStream, "(sender) wrong final balance");
        assertEq(bobFinalBalance, bobInitialBalance + aliceShouldStream, "(receiver) wrong final balance");
    }

    function testExecuteCliffAndFlowWithUpdatedEndDate_longerDuration() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        _setACL_AUTHORIZE_FULL_CONTROL(alice, type(int96).max);
        _createVestingScheduleWithDefaultData(alice, bob);
        uint256 totalAmount = (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;

        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);

        vm.warp(block.timestamp + CLIFF_DATE + 30 minutes);

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

        uint32 NEW_END_DATE = END_DATE + 4 hours;

        vm.warp(block.timestamp + 2 days);

        uint256 timeLeftToVest = NEW_END_DATE - block.timestamp;
        uint256 settledAmount = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;
        int96 newFlowRate =
            SafeCast.toInt96(SafeCast.toInt256(totalAmount - settledAmount) / SafeCast.toInt256(timeLeftToVest));

        uint96 expectedRemainder =
            SafeCast.toUint96((totalAmount - settledAmount) - (uint96(newFlowRate) * timeLeftToVest));

        vm.expectEmit(true, true, true, true);
        emit VestingScheduleUpdated(superToken, alice, bob, NEW_END_DATE, expectedRemainder, newFlowRate, totalAmount, settledAmount);

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromEndDate(superToken, bob, NEW_END_DATE);

        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

        uint256 earlyEndDelay = 1 hours;
        vm.warp(schedule.endDate - earlyEndDelay);

        uint256 adjustedAmountClosing = uint96(schedule.flowRate) * earlyEndDelay + schedule.remainderAmount;

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, adjustedAmountClosing);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(superToken, alice, bob, NEW_END_DATE, adjustedAmountClosing, false);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");

        assertEq(aliceInitialBalance - superToken.balanceOf(alice), totalAmount, "(sender) wrong final balance");
        assertEq(superToken.balanceOf(bob), bobInitialBalance + totalAmount, "(receiver) wrong final balance");
    }

    function testExecuteCliffAndFlowWithUpdatedEndDate_shorterDuration() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        _setACL_AUTHORIZE_FULL_CONTROL(alice, type(int96).max);
        _createVestingScheduleWithDefaultData(alice, bob);
        uint256 totalAmount = (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;

        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);

        vm.warp(block.timestamp + CLIFF_DATE + 30 minutes);

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

        uint32 NEW_END_DATE = END_DATE - 4 hours;

        vm.warp(block.timestamp + 2 days);

        uint256 timeLeftToVest = NEW_END_DATE - block.timestamp;
        uint256 settledAmount = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;
        int96 newFlowRate =
            SafeCast.toInt96(SafeCast.toInt256(totalAmount - settledAmount) / SafeCast.toInt256(timeLeftToVest));

        uint96 expectedRemainder =
            SafeCast.toUint96((totalAmount - settledAmount) - (uint96(newFlowRate) * timeLeftToVest));

        vm.expectEmit(true, true, true, true);
        emit VestingScheduleUpdated(superToken, alice, bob, NEW_END_DATE, expectedRemainder, newFlowRate, totalAmount, settledAmount);

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromEndDate(superToken, bob, NEW_END_DATE);

        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

        uint256 earlyEndDelay = 1 hours;
        vm.warp(schedule.endDate - earlyEndDelay);

        uint256 adjustedAmountClosing = uint96(schedule.flowRate) * earlyEndDelay + schedule.remainderAmount;

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, adjustedAmountClosing);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(superToken, alice, bob, NEW_END_DATE, adjustedAmountClosing, false);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");

        assertEq(aliceInitialBalance - superToken.balanceOf(alice), totalAmount, "(sender) wrong final balance");
        assertEq(superToken.balanceOf(bob), bobInitialBalance + totalAmount, "(receiver) wrong final balance");
    }

    function testExecuteCliffAndFlowWithUpdatedAmount_largerAmount() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        _setACL_AUTHORIZE_FULL_CONTROL(alice, type(int96).max);
        _createVestingScheduleWithDefaultData(alice, bob);
        uint256 totalAmount = (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;

        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);

        vm.warp(block.timestamp + CLIFF_DATE + 30 minutes);

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

        uint256 newTotalAmount = totalAmount + (totalAmount / 2);

        vm.warp(block.timestamp + 2 days);

        uint256 timeLeftToVest = END_DATE - block.timestamp;
        uint256 settledAmount = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;
        int96 newFlowRate = SafeCast.toInt96(
            SafeCast.toInt256(newTotalAmount - settledAmount) / SafeCast.toInt256(timeLeftToVest)
        );

        uint96 expectedRemainder =
            SafeCast.toUint96((newTotalAmount - settledAmount) - (uint96(newFlowRate) * timeLeftToVest));

        vm.expectEmit(true, true, true, true);
        emit VestingScheduleUpdated(superToken, alice, bob, END_DATE, expectedRemainder, newFlowRate, newTotalAmount, settledAmount);

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, newTotalAmount);

        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

        uint256 earlyEndDelay = 1 hours;
        vm.warp(schedule.endDate - earlyEndDelay);

        uint256 adjustedAmountClosing = uint96(schedule.flowRate) * earlyEndDelay + schedule.remainderAmount;

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, adjustedAmountClosing);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, adjustedAmountClosing, false);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");

        uint256 expectedTotalAmountTransferred =
            settledAmount + (timeLeftToVest * uint96(newFlowRate)) + schedule.remainderAmount;

        assertEq(
            aliceInitialBalance - superToken.balanceOf(alice),
            expectedTotalAmountTransferred,
            "(sender) wrong final balance"
        );
        assertEq(
            superToken.balanceOf(bob),
            bobInitialBalance + expectedTotalAmountTransferred,
            "(receiver) wrong final balance"
        );
    }

    function testExecuteCliffAndFlowWithUpdatedAmount_smallerAmount() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        _setACL_AUTHORIZE_FULL_CONTROL(alice, type(int96).max);
        _createVestingScheduleWithDefaultData(alice, bob);
        uint256 totalAmount = (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;

        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.startPrank(admin);

        vm.warp(block.timestamp + CLIFF_DATE + 30 minutes);

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

        uint256 newTotalAmount = totalAmount - (totalAmount / 10000);

        vm.warp(block.timestamp + 2 days);
        uint256 timeLeftToVest = END_DATE - block.timestamp;

        uint256 settledAmount = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;

        int96 newFlowRate = SafeCast.toInt96(
            SafeCast.toInt256(newTotalAmount - settledAmount) / SafeCast.toInt256(timeLeftToVest)
        );

        uint96 expectedRemainder =
            SafeCast.toUint96((newTotalAmount - settledAmount) - (uint96(newFlowRate) * timeLeftToVest));

        vm.expectEmit(true, true, true, true);
        emit VestingScheduleUpdated(superToken, alice, bob, END_DATE, expectedRemainder, newFlowRate, newTotalAmount, settledAmount);

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, newTotalAmount);

        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

        uint256 earlyEndDelay = 1 hours;
        vm.warp(schedule.endDate - earlyEndDelay);

        uint256 adjustedAmountClosing = uint96(schedule.flowRate) * earlyEndDelay + schedule.remainderAmount;

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, adjustedAmountClosing);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, adjustedAmountClosing, false);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");

        uint256 expectedTotalAmountTransferred =
            settledAmount + (timeLeftToVest * uint96(newFlowRate)) + schedule.remainderAmount;

        assertEq(
            aliceInitialBalance - superToken.balanceOf(alice),
            expectedTotalAmountTransferred,
            "(sender) wrong final balance"
        );
        assertEq(
            superToken.balanceOf(bob),
            bobInitialBalance + expectedTotalAmountTransferred,
            "(receiver) wrong final balance"
        );
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
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, 0, true);
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

        // Create Vesting Schedule
        _createVestingScheduleWithDefaultData(alice, bob);

        // Sender increase allowance to vesting scheduler
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        // Move time to 30 minutes after the `cliffAndFlowDate`
        uint256 initialTimestamp = block.timestamp + CLIFF_DATE + 30 minutes;
        vm.warp(initialTimestamp);

        uint256 flowDelayCompensation = (block.timestamp - CLIFF_DATE) * uint96(FLOW_RATE);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, CLIFF_TRANSFER_AMOUNT + flowDelayCompensation);

        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, flowDelayCompensation
        );

        vm.prank(admin);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(success, "executeVesting should return true");
        vm.startPrank(alice);
        superToken.deleteFlow(alice, bob);
        vm.stopPrank();
        vm.startPrank(admin);
        uint256 finalTimestamp = block.timestamp + 10 days - 3600;
        vm.warp(finalTimestamp);
        vm.expectEmit(true, true, true, true);
        emit VestingEndFailed(superToken, alice, bob, END_DATE);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
    }

    // # Vesting Scheduler V2 tests

    function testCreateAndExecuteImmediately() public {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        // Create schedule
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        uint32 startAndCliffDate = uint32(block.timestamp);

        vm.expectEmit();
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            startAndCliffDate,
            startAndCliffDate,
            FLOW_RATE,
            END_DATE,
            CLIFF_TRANSFER_AMOUNT,
            0,
            0
        );

        vestingScheduler.createVestingSchedule(
            superToken, bob, startAndCliffDate, startAndCliffDate, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, 0
        );
        vm.stopPrank();

        // Execute start
        vm.expectEmit();
        emit Transfer(alice, bob, CLIFF_TRANSFER_AMOUNT);

        vm.expectEmit();
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, startAndCliffDate, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, uint256(0)
        );

        vm.prank(admin);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);

        assertTrue(success, "executeVesting should return true");

        // Execute end
        vm.warp(END_DATE - 1 hours);

        uint256 totalAmount = CLIFF_TRANSFER_AMOUNT + ((END_DATE - startAndCliffDate) * uint96(FLOW_RATE));
        uint256 adjustedAmountClosing =
            totalAmount - CLIFF_TRANSFER_AMOUNT - ((block.timestamp - startAndCliffDate) * uint96(FLOW_RATE));

        vm.expectEmit();
        emit Transfer(alice, bob, adjustedAmountClosing);

        vm.expectEmit();
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, adjustedAmountClosing, false);

        vm.prank(admin);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);

        assertTrue(success, "executeCloseVesting should return true");

        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (END_DATE - startAndCliffDate) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;
        assertEq(aliceInitialBalance - aliceFinalBalance, aliceShouldStream, "(sender) wrong final balance");
        assertEq(bobFinalBalance, bobInitialBalance + aliceShouldStream, "(receiver) wrong final balance");
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
            0 // claimPeriod
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
            0 // claimPeriod
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
            0 // claimPeriod
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
            0 // claimPeriod
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
            0 // claimPeriod
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
                0 // claimPeriod
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

    function testNewFunctionScheduleCreationWithCliff() public {
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
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            startDate,
            expectedCliffDate,
            expectedFlowRate,
            expectedEndDate,
            expectedCliffAmount,
            0,
            0
        );

        vm.startPrank(alice);

        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken, bob, totalVestedAmount, vestingDuration, startDate, cliffPeriod, 0
        );
        vm.stopPrank();
    }

    function test_createVestingScheduleFromAmountAndDuration_nonLinearCliff() public {
        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();

        uint32 startDate = uint32(block.timestamp);
        uint256 totalVestedAmount = 200_000_000; // a value perfectly divisible
        uint256 cliffAmount = 150_000_000; // Cliff account of 75% of the total amount
        uint32 vestingDuration = 1 weeks + 1 days;
        uint32 cliffPeriod = 1 days;

        int96 expectedFlowRate =
            SafeCast.toInt96(SafeCast.toInt256((totalVestedAmount - cliffAmount) / (vestingDuration - cliffPeriod)));
        uint96 expectedRemainderAmount = SafeCast.toUint96(
            (totalVestedAmount - cliffAmount) - (SafeCast.toUint256(expectedFlowRate) * (vestingDuration - cliffPeriod))
        );
        vm.expectEmit();
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            startDate,
            startDate + cliffPeriod, // expected cliff date
            expectedFlowRate,
            startDate + vestingDuration, // expected end date
            cliffAmount,
            0,
            expectedRemainderAmount
        );

        vm.startPrank(alice);

        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken, bob, totalVestedAmount, vestingDuration, startDate, cliffPeriod, 0, cliffAmount
        );
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
        IVestingSchedulerV3.VestingSchedule expectedSchedule;
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

        assertTrue(
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob).endDate == 0,
            "Schedule should not exist"
        );

        // Arrange
        $.expectedSchedule =
            _getExpectedScheduleFromAmountAndDuration(totalAmount, totalDuration, cliffPeriod, startDate, claimPeriod);
        $.expectedCliffDate = cliffPeriod == 0 ? 0 : $.expectedSchedule.cliffAndFlowDate;
        $.expectedStartDate = startDate == 0 ? uint32(block.timestamp) : startDate;

        // Assume we're not getting liquidated at the end:
        vm.assume(
            $.beforeSenderBalance
                >= totalAmount + vestingScheduler.END_DATE_VALID_BEFORE() * SafeCast.toUint256($.expectedSchedule.flowRate)
        );

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
        superToken.approve(
            address(vestingScheduler), vestingScheduler.getMaximumNeededTokenAllowance($.expectedSchedule)
        );
        vm.stopPrank();

        // Intermediary `mapCreateVestingScheduleParams` test
        assertAreScheduleCreationParamsEqual(
            IVestingSchedulerV3.ScheduleCreationParams(
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
            vestingScheduler.mapCreateVestingScheduleParams(
                superToken, alice, bob, totalAmount, totalDuration, $.expectedStartDate, cliffPeriod, claimPeriod
            )
        );

        vm.expectEmit();
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            $.expectedStartDate,
            $.expectedCliffDate,
            $.expectedSchedule.flowRate,
            $.expectedSchedule.endDate,
            $.expectedSchedule.cliffAmount,
            $.expectedSchedule.claimValidityDate,
            $.expectedSchedule.remainderAmount
        );

        // Act
        vm.startPrank(alice);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken, bob, totalAmount, totalDuration, startDate, cliffPeriod, claimPeriod
        );

        vm.stopPrank();

        // Assert
        IVestingSchedulerV3.VestingSchedule memory actualSchedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertEq(
            actualSchedule.cliffAndFlowDate,
            $.expectedSchedule.cliffAndFlowDate,
            "schedule created: cliffAndFlowDate not expected"
        );
        assertEq(actualSchedule.flowRate, $.expectedSchedule.flowRate, "schedule created: flowRate not expected");
        assertEq(
            actualSchedule.cliffAmount, $.expectedSchedule.cliffAmount, "schedule created: cliffAmount not expected"
        );
        assertEq(actualSchedule.endDate, $.expectedSchedule.endDate, "schedule created: endDate not expected");
        assertEq(
            actualSchedule.remainderAmount,
            $.expectedSchedule.remainderAmount,
            "schedule created: remainderAmount not expected"
        );
        assertEq(
            actualSchedule.claimValidityDate,
            $.expectedSchedule.claimValidityDate,
            "schedule created: claimValidityDate not expected"
        );

        // Act
        console.log("Executing cliff and flow.");
        uint32 randomFlowDelay = ($.expectedSchedule.claimValidityDate - $.expectedSchedule.cliffAndFlowDate);
        vm.warp($.expectedSchedule.cliffAndFlowDate + randomFlowDelay);

        $.claimer = randomizer % 2 == 0 ? bob : alice;

        vm.prank($.claimer);
        vm.expectEmit();
        emit VestingClaimed(superToken, alice, bob, $.claimer);
        vm.expectEmit();
        emit VestingCliffAndFlowExecuted(
            superToken,
            alice,
            bob,
            $.expectedSchedule.cliffAndFlowDate,
            $.expectedSchedule.flowRate,
            $.expectedSchedule.cliffAmount,
            randomFlowDelay * SafeCast.toUint256($.expectedSchedule.flowRate)
        );
        assertTrue(vestingScheduler.executeCliffAndFlow(superToken, alice, bob));
        vm.stopPrank();

        // Assert
        actualSchedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertEq(actualSchedule.cliffAndFlowDate, 0, "schedule started: cliffAndFlowDate not expected");
        assertEq(actualSchedule.cliffAmount, 0, "schedule started: cliffAmount not expected");
        assertEq(actualSchedule.flowRate, $.expectedSchedule.flowRate, "schedule started: flowRate not expected");
        assertEq(actualSchedule.endDate, $.expectedSchedule.endDate, "schedule started: endDate not expected");
        assertEq(
            actualSchedule.remainderAmount,
            $.expectedSchedule.remainderAmount,
            "schedule started: remainderAmount not expected"
        );

        if (randomizer % 7 != 0) {
            // # Test end execution on time.
            console.log("Executing end vesting early.");
            uint32 randomEarlyEndTime =
                (vestingScheduler.END_DATE_VALID_BEFORE() - (vestingScheduler.END_DATE_VALID_BEFORE() / randomizer));

            vm.warp($.expectedSchedule.endDate - randomEarlyEndTime);
            vm.expectEmit();
            uint256 earlyEndCompensation = randomEarlyEndTime * SafeCast.toUint256($.expectedSchedule.flowRate)
                + $.expectedSchedule.remainderAmount;
            emit VestingEndExecuted(superToken, alice, bob, $.expectedSchedule.endDate, earlyEndCompensation, false);

            // Act
            assertTrue(vestingScheduler.executeEndVesting(superToken, alice, bob));

            // Assert
            $.afterSenderBalance = superToken.balanceOf(alice);
            $.afterReceiverBalance = superToken.balanceOf(bob);

            assertEq(
                $.afterSenderBalance,
                $.beforeSenderBalance - totalAmount,
                "Sender balance should decrease by totalAmount"
            );
            assertEq(
                $.afterReceiverBalance,
                $.beforeReceiverBalance + totalAmount,
                "Receiver balance should increase by totalAmount"
            );
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

            assertLt(
                $.afterSenderBalance,
                $.beforeSenderBalance - totalAmount + $.expectedSchedule.remainderAmount,
                "Sender balance should decrease by at least totalAmount"
            );
            assertGt(
                $.afterReceiverBalance,
                $.beforeReceiverBalance + totalAmount - $.expectedSchedule.remainderAmount,
                "Receiver balance should increase by at least totalAmount"
            );
        }

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);

        vm.warp(type(uint32).max);
        assertEq(
            $.afterSenderBalance,
            superToken.balanceOf(alice),
            "After the schedule has ended, the sender's balance should never change."
        );
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

        assertTrue(
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob).endDate == 0,
            "Schedule should not exist"
        );

        // Arrange
        $.expectedSchedule =
            _getExpectedScheduleFromAmountAndDuration(totalAmount, totalDuration, cliffPeriod, startDate, claimPeriod);
        $.expectedCliffDate = cliffPeriod == 0 ? 0 : $.expectedSchedule.cliffAndFlowDate;
        $.expectedStartDate = startDate == 0 ? uint32(block.timestamp) : startDate;

        // Assume we're not getting liquidated at the end:
        vm.assume(
            $.beforeSenderBalance
                >= totalAmount + vestingScheduler.END_DATE_VALID_BEFORE() * SafeCast.toUint256($.expectedSchedule.flowRate)
        );

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
        superToken.approve(
            address(vestingScheduler), vestingScheduler.getMaximumNeededTokenAllowance($.expectedSchedule)
        );
        vm.stopPrank();

        // Intermediary `mapCreateVestingScheduleParams` test
        assertAreScheduleCreationParamsEqual(
            IVestingSchedulerV3.ScheduleCreationParams(
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
            vestingScheduler.mapCreateVestingScheduleParams(
                superToken, alice, bob, totalAmount, totalDuration, $.expectedStartDate, cliffPeriod, claimPeriod
            )
        );

        vm.expectEmit();
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            $.expectedStartDate,
            $.expectedCliffDate,
            $.expectedSchedule.flowRate,
            $.expectedSchedule.endDate,
            $.expectedSchedule.cliffAmount,
            $.expectedSchedule.claimValidityDate,
            $.expectedSchedule.remainderAmount
        );

        // Act
        vm.startPrank(alice);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken, bob, totalAmount, totalDuration, startDate, cliffPeriod, claimPeriod
        );
        vm.stopPrank();

        // Assert
        IVestingSchedulerV3.VestingSchedule memory actualSchedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertEq(
            actualSchedule.cliffAndFlowDate,
            $.expectedSchedule.cliffAndFlowDate,
            "schedule created: cliffAndFlowDate not expected"
        );
        assertEq(actualSchedule.flowRate, $.expectedSchedule.flowRate, "schedule created: flowRate not expected");
        assertEq(
            actualSchedule.cliffAmount, $.expectedSchedule.cliffAmount, "schedule created: cliffAmount not expected"
        );
        assertEq(actualSchedule.endDate, $.expectedSchedule.endDate, "schedule created: endDate not expected");
        assertEq(
            actualSchedule.remainderAmount,
            $.expectedSchedule.remainderAmount,
            "schedule created: remainderAmount not expected"
        );
        assertEq(
            actualSchedule.claimValidityDate,
            $.expectedSchedule.claimValidityDate,
            "schedule created: claimValidityDate not expected"
        );

        // Act
        console.log("Executing cliff and flow.");
        vm.warp(
            $.expectedSchedule.endDate - vestingScheduler.END_DATE_VALID_BEFORE()
            /* random delay: */
            + (
                $.expectedSchedule.claimValidityDate
                    - ($.expectedSchedule.endDate - vestingScheduler.END_DATE_VALID_BEFORE())
            ) / randomizer
        );

        $.claimer = randomizer % 2 == 0 ? bob : alice;

        vm.prank($.claimer);

        vm.expectEmit();
        emit VestingClaimed(superToken, alice, bob, $.claimer);
        vm.expectEmit();
        emit VestingCliffAndFlowExecuted(
            superToken,
            alice,
            bob,
            $.expectedSchedule.cliffAndFlowDate,
            0,
            $.expectedSchedule.cliffAmount,
            totalAmount - $.expectedSchedule.cliffAmount
        );

        vm.expectEmit();
        emit VestingEndExecuted(superToken, alice, bob, $.expectedSchedule.endDate, 0, false);

        assertTrue(vestingScheduler.executeCliffAndFlow(superToken, alice, bob));
        vm.stopPrank();

        $.afterSenderBalance = superToken.balanceOf(alice);
        $.afterReceiverBalance = superToken.balanceOf(bob);

        assertEq(
            $.afterSenderBalance, $.beforeSenderBalance - totalAmount, "Sender balance should decrease by totalAmount"
        );
        assertEq(
            $.afterReceiverBalance,
            $.beforeReceiverBalance + totalAmount,
            "Receiver balance should increase by totalAmount"
        );

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);

        vm.warp(type(uint32).max);
        assertEq(
            $.afterSenderBalance,
            superToken.balanceOf(alice),
            "After the schedule has ended, the sender's balance should never change."
        );
    }

    function test_createAndExecuteVestingScheduleFromAmountAndDuration(uint256 _totalAmount, uint32 _totalDuration)
        public
    {
        _totalDuration = SafeCast.toUint32(bound(_totalDuration, uint32(7 days), uint32(365 days)));
        _totalAmount = bound(_totalAmount, 1 ether, 100 ether);

        int96 flowRate = SafeCast.toInt96(SafeCast.toInt256(_totalAmount / _totalDuration));

        uint96 remainderAmount = SafeCast.toUint96(_totalAmount - (SafeCast.toUint256(flowRate) * _totalDuration));

        _setACL_AUTHORIZE_FULL_CONTROL(alice, flowRate);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            uint32(block.timestamp),
            0,
            flowRate,
            uint32(block.timestamp) + _totalDuration,
            0,
            0,
            remainderAmount
        );

        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(superToken, alice, bob, uint32(block.timestamp), flowRate, 0, 0);

        vestingScheduler.createAndExecuteVestingScheduleFromAmountAndDuration(
            superToken, bob, _totalAmount, _totalDuration
        );

        vm.stopPrank();
    }

    function test_createAndExecuteVestingScheduleFromAmountAndDuration_noCtx(
        uint256 _totalAmount,
        uint32 _totalDuration
    ) public {
        _totalDuration = SafeCast.toUint32(bound(_totalDuration, uint32(7 days), uint32(365 days)));
        _totalAmount = bound(_totalAmount, 1 ether, 100 ether);

        int96 flowRate = SafeCast.toInt96(SafeCast.toInt256(_totalAmount / _totalDuration));

        uint96 remainderAmount = SafeCast.toUint96(_totalAmount - (SafeCast.toUint256(flowRate) * _totalDuration));

        _setACL_AUTHORIZE_FULL_CONTROL(alice, flowRate);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            uint32(block.timestamp),
            0,
            flowRate,
            uint32(block.timestamp) + _totalDuration,
            0,
            0,
            remainderAmount
        );

        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(superToken, alice, bob, uint32(block.timestamp), flowRate, 0, 0);

        vestingScheduler.createAndExecuteVestingScheduleFromAmountAndDuration(
            superToken, bob, _totalAmount, _totalDuration
        );

        vm.stopPrank();
    }

    function test_createClaimableVestingSchedule() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            END_DATE,
            CLIFF_TRANSFER_AMOUNT,
            CLAIM_VALIDITY_DATE,
            0
        );

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, CLAIM_VALIDITY_DATE
        );
        vm.stopPrank();

        vm.startPrank(alice);
        //assert storage data
        VestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE, "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE, "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE, "schedule.flowRate");
        assertTrue(schedule.claimValidityDate == CLAIM_VALIDITY_DATE, "schedule.claimValidityDate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT, "schedule.cliffAmount");
    }

    function test_createClaimableVestingSchedule_claimValidity() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            END_DATE,
            CLIFF_TRANSFER_AMOUNT,
            CLAIM_VALIDITY_DATE,
            0
        );

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, CLAIM_VALIDITY_DATE
        );
        vm.stopPrank();

        vm.startPrank(alice);
        //assert storage data
        VestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE, "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE, "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE, "schedule.flowRate");
        assertTrue(schedule.claimValidityDate == CLAIM_VALIDITY_DATE, "schedule.claimValidityDate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT, "schedule.cliffAmount");
    }

    function test_createClaimableVestingSchedule_noCtx() public {
        vm.expectEmit(true, true, true, true);
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            START_DATE,
            CLIFF_DATE,
            FLOW_RATE,
            END_DATE,
            CLIFF_TRANSFER_AMOUNT,
            CLAIM_VALIDITY_DATE,
            0
        );

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, CLAIM_VALIDITY_DATE
        );
        vm.stopPrank();

        vm.startPrank(alice);
        //assert storage data
        VestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertTrue(schedule.cliffAndFlowDate == CLIFF_DATE, "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == END_DATE, "schedule.endDate");
        assertTrue(schedule.flowRate == FLOW_RATE, "schedule.flowRate");
        assertTrue(schedule.claimValidityDate == CLAIM_VALIDITY_DATE, "schedule.flowRate");
        assertTrue(schedule.cliffAmount == CLIFF_TRANSFER_AMOUNT, "schedule.cliffAmount");
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
            CLAIM_VALIDITY_DATE
        );

        // revert with receivers = sender
        vm.expectRevert(IVestingSchedulerV2.AccountInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, alice, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, CLAIM_VALIDITY_DATE
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
            CLAIM_VALIDITY_DATE
        );

        // revert with flowRate = 0
        vm.expectRevert(IVestingSchedulerV2.FlowRateInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, 0, CLIFF_TRANSFER_AMOUNT, END_DATE, CLAIM_VALIDITY_DATE
        );

        // revert with cliffDate = 0 but cliffAmount != 0
        vm.expectRevert(IVestingSchedulerV2.CliffInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, 0, 0, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, CLAIM_VALIDITY_DATE
        );

        // revert with startDate < block.timestamp && cliffDate = 0
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, uint32(block.timestamp - 1), 0, FLOW_RATE, 0, END_DATE, CLAIM_VALIDITY_DATE
        );

        // revert with endDate = 0
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, 0, CLAIM_VALIDITY_DATE
        );

        // revert with cliffAndFlowDate < block.timestamp
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, 0, uint32(block.timestamp) - 1, FLOW_RATE, 0, END_DATE, CLAIM_VALIDITY_DATE
        );

        // revert with cliffAndFlowDate >= endDate
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, CLIFF_DATE, CLAIM_VALIDITY_DATE
        );

        // revert with cliffAndFlowDate + startDateValidFor >= endDate - endDateValidBefore
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, CLIFF_DATE, CLAIM_VALIDITY_DATE
        );

        // revert with startDate > cliffDate
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, CLIFF_DATE + 1, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, CLAIM_VALIDITY_DATE
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
            CLAIM_VALIDITY_DATE
        );

        // revert with invalid claim validity date (before schedule/cliff start)
        vm.expectRevert(IVestingSchedulerV2.TimeWindowInvalid.selector);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, CLIFF_DATE - 1
        );
    }

    function test_createClaimableVestingSchedule_dataExists() public {
        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, CLAIM_VALIDITY_DATE
        );
        vm.stopPrank();

        vm.expectRevert(IVestingSchedulerV2.ScheduleAlreadyExists.selector);

        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, CLAIM_VALIDITY_DATE
        );
        vm.stopPrank();
    }

    function test_createClaimableVestingScheduleFromAmountAndDuration_withoutCliff() public {
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
        emit VestingScheduleCreated(
            superToken, alice, bob, startDate, 0, expectedFlowRate, expectedEndDate, 0, startDate + claimPeriod, 0
        );
        vm.startPrank(alice);

        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            totalVestedAmount,
            vestingDuration,
            startDate,
            0, // cliffPeriod
            claimPeriod
        );
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
            superToken, bob, totalVestedAmount, vestingDuration, 0, 0, claimPeriod
        );
        vm.stopPrank();
    }

    function test_createClaimableVestingScheduleFromAmountAndDuration_withCliff() public {
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
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            startDate,
            startDate + cliffPeriod,
            expectedFlowRate,
            startDate + vestingDuration,
            12960000,
            startDate + claimPeriod,
            0
        );

        vm.startPrank(alice);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken, bob, totalVestedAmount, vestingDuration, startDate, cliffPeriod, claimPeriod
        );
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
        emit VestingScheduleCreated(
            superToken,
            alice,
            bob,
            uint32(block.timestamp),
            expectedCliffDate,
            expectedFlowRate,
            expectedEndDate,
            expectedCliffAmount,
            uint32(block.timestamp) + claimPeriod,
            0
        );

        vm.startPrank(alice);

        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken, bob, totalVestedAmount, vestingDuration, 0, cliffPeriod, claimPeriod
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
            15 days // claimPeriod
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
            15 days // claimPeriod
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
            15 days // claimPeriod
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
            15 days // claimPeriod
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
            15 days // claimPeriod
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
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, adjustedAmountClosing, false);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;
        assertEq(aliceInitialBalance - aliceFinalBalance, aliceShouldStream, "(sender) wrong final balance");
        assertEq(bobFinalBalance, bobInitialBalance + aliceShouldStream, "(receiver) wrong final balance");

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function test_executeCliffAndFlow_claimableScheduleWithCliffAmount_receiverClaim_withUpdatedAmountAfterClaim()
        public
    {
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
        _createClaimableVestingScheduleWithDefaultData(alice, bob);

        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.warp(block.timestamp + CLIFF_DATE + 30 minutes);

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

        // Move time to 1 hour before end of vesting
        uint256 finalTimestamp = block.timestamp + 10 days - 1 hours;
        vm.warp(finalTimestamp);

        uint256 timeDiffToEndDate = END_DATE > block.timestamp ? END_DATE - block.timestamp : 0;
        uint256 adjustedAmountClosing = timeDiffToEndDate * uint96(FLOW_RATE);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, adjustedAmountClosing);
        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, adjustedAmountClosing, false);

        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");

        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;

        assertEq(aliceInitialBalance - aliceFinalBalance, aliceShouldStream, "(sender) wrong final balance");
        assertEq(bobFinalBalance, bobInitialBalance + aliceShouldStream, "(receiver) wrong final balance");

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function test_executeCliffAndFlow_claimAfterEndDate(uint256 delayAfterEndDate, uint256 claimDate, uint8 randomizer)
        public
    {
        randomizer = SafeCast.toUint8(bound(randomizer, 1, type(uint8).max));

        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        uint256 totalExpectedAmount = CLIFF_TRANSFER_AMOUNT + (END_DATE - CLIFF_DATE) * SafeCast.toUint256(FLOW_RATE);

        delayAfterEndDate = bound(delayAfterEndDate, 1, 1e8);
        claimDate = bound(claimDate, END_DATE - vestingScheduler.END_DATE_VALID_BEFORE(), END_DATE + delayAfterEndDate);

        _createClaimableVestingScheduleWithClaimDateAfterEndDate(alice, bob, delayAfterEndDate);
        vm.prank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        vm.warp(claimDate);

        address claimer = randomizer % 2 == 0 ? bob : alice;
        vm.expectEmit(true, true, true, false);
        emit VestingClaimed(superToken, alice, bob, claimer);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, totalExpectedAmount);

        vm.expectEmit(true, true, true, true);
        emit VestingCliffAndFlowExecuted(
            superToken, alice, bob, CLIFF_DATE, 0, CLIFF_TRANSFER_AMOUNT, totalExpectedAmount - CLIFF_TRANSFER_AMOUNT
        );

        vm.expectEmit(true, true, true, true);
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, 0, false);

        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
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
        emit VestingEndExecuted(superToken, alice, bob, END_DATE, adjustedAmountClosing, false);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeCloseVesting should return true");
        uint256 aliceFinalBalance = superToken.balanceOf(alice);
        uint256 bobFinalBalance = superToken.balanceOf(bob);
        uint256 aliceShouldStream = (END_DATE - CLIFF_DATE) * uint96(FLOW_RATE) + CLIFF_TRANSFER_AMOUNT;
        assertEq(aliceInitialBalance - aliceFinalBalance, aliceShouldStream, "(sender) wrong final balance");
        assertEq(bobFinalBalance, bobInitialBalance + aliceShouldStream, "(receiver) wrong final balance");
    }

    function test_executeCliffAndFlow_claimableScheduleWithCliffAmount_cannotClaimOnBehalf(address _claimer) public {
        vm.assume(vestingScheduler.isTrustedForwarder(_claimer) == false);
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
        IVestingSchedulerV3.VestingSchedule memory expectedSchedule =
            _getExpectedScheduleFromAmountAndDuration(totalAmount, totalDuration, cliffPeriod, startDate, 0);

        // Assume we're not getting liquidated at the end:
        vm.assume(
            beforeSenderBalance
                >= totalAmount + vestingScheduler.END_DATE_VALID_BEFORE() * SafeCast.toUint256(expectedSchedule.flowRate)
        );

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
            superToken, bob, totalAmount, totalDuration, startDate, cliffPeriod, 0
        );
        vm.stopPrank();

        // Act
        vm.warp(expectedSchedule.cliffAndFlowDate + (vestingScheduler.START_DATE_VALID_AFTER()));
        assertTrue(vestingScheduler.executeCliffAndFlow(superToken, alice, bob));

        if (randomizer % 2 == 0) {
            // Let's set the allowance again half-way through.
            vm.startPrank(alice);
            superToken.approve(
                address(vestingScheduler),
                vestingScheduler.getMaximumNeededTokenAllowance(
                    vestingScheduler.getVestingSchedule(address(superToken), alice, bob)
                )
            );
            vm.stopPrank();
        }

        // Act
        vm.warp(expectedSchedule.endDate - (vestingScheduler.END_DATE_VALID_BEFORE()));
        assertTrue(vestingScheduler.executeEndVesting(superToken, alice, bob));

        // Assert
        assertEq(superToken.allowance(alice, address(vestingScheduler)), 0, "No allowance should be left");
        (,,, int96 flowRateAllowance) = superToken.getFlowPermissions(alice, address(vestingScheduler));
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
        IVestingSchedulerV3.VestingSchedule memory expectedSchedule =
            _getExpectedScheduleFromAmountAndDuration(totalAmount, totalDuration, cliffPeriod, startDate, claimPeriod);

        // Assume we're not getting liquidated at the end:
        vm.assume(
            beforeSenderBalance
                >= totalAmount + vestingScheduler.END_DATE_VALID_BEFORE() * SafeCast.toUint256(expectedSchedule.flowRate)
        );

        // Arrange allowance
        vm.assume(superToken.allowance(alice, address(vestingScheduler)) == 0);

        vm.startPrank(alice);
        superToken.revokeFlowPermissions(address(vestingScheduler));
        bool willThereBeFullTransfer =
            expectedSchedule.claimValidityDate >= expectedSchedule.endDate - vestingScheduler.END_DATE_VALID_BEFORE();
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
            superToken, bob, totalAmount, totalDuration, startDate, cliffPeriod, claimPeriod
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
            superToken.approve(
                address(vestingScheduler),
                vestingScheduler.getMaximumNeededTokenAllowance(
                    vestingScheduler.getVestingSchedule(address(superToken), alice, bob)
                )
            );
            vm.stopPrank();
        }

        // Act
        if (!willThereBeFullTransfer) {
            vm.warp(expectedSchedule.endDate - vestingScheduler.END_DATE_VALID_BEFORE());
            assertTrue(vestingScheduler.executeEndVesting(superToken, alice, bob));
        }

        // Assert
        assertEq(superToken.allowance(alice, address(vestingScheduler)), 0, "No allowance should be left");
        (,,, int96 flowRateAllowance) = superToken.getFlowPermissions(alice, address(vestingScheduler));
        assertEq(flowRateAllowance, 0, "No flow rate allowance should be left");

        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    // VestingSchedulerV3 Scenarios :
    /* Scenario 1 :
    Assuming a 5 month long schedule:

    Define schedule for 1000 USDC (guaranteeing only 200USDC for 1 month)

    One month later, update schedule to 1400 USDC (with four months left and 200USDC already transferred, this means 300 USDC/mo)

    One month later, update schedule to 1100 USDC (with 3 months left, and 500 USDC already transferred, this means 200 USDC/mo)

    At the time of the last month, with the total amount set at 1500 USDC, the stream shall be closed up to ±24hrs early, settling any differences to the expected total
    */
    function testVestingSchedulerV3_scenario_notClaimable() public {
        // Initial setup
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        // Define constants for the test
        uint256 initialTotalAmount = 1000 ether;
        uint32 totalDuration = 150 days; // 5 months

        // Set up permissions for Alice
        _setACL_AUTHORIZE_FULL_CONTROL(alice, type(int96).max); // Allow any flow rate

        // Create the initial vesting schedule
        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        uint32 startDate = uint32(block.timestamp + 10 days);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            initialTotalAmount,
            totalDuration,
            startDate,
            0, // No cliff period
            0 // No claim period
        );
        vm.stopPrank();

        // Get the schedule
        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

        // Verify initial schedule
        assertEq(schedule.endDate - startDate, totalDuration, "Duration should be 5 months");

        // Warp to cliff date and execute cliff and flow
        vm.warp(startDate);

        vm.prank(alice);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(success, "executeCliffAndFlow should return true");

        vm.warp(startDate + 30 days);
        // Verify Bob received the first month's amount (200 USDC)
        uint256 firstMonthAmount = initialTotalAmount / 5; // 200 USDC
        assertApproxEqAbs(
            superToken.balanceOf(bob) - bobInitialBalance,
            firstMonthAmount,
            firstMonthAmount * 10 / 10_000,
            "Bob should have received 200 USDC after first month"
        );

        // Warp to second month and update schedule to 1400 USDC
        vm.warp(startDate + 2 * 30 days);

        uint256 secondUpdateAmount = 1400 ether;
        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, secondUpdateAmount);

        // Verify the flow rate has been updated
        schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        uint256 remainingMonths = 4;

        (uint256 settledAmount,) =
            vestingScheduler.accountings(_helperGetScheduleId(address(superToken), alice, bob));

        uint256 remainingAmount = secondUpdateAmount - settledAmount;
        int96 expectedFlowRate =
            SafeCast.toInt96(SafeCast.toInt256(remainingAmount / (schedule.endDate - block.timestamp)));
        assertEq(schedule.flowRate, expectedFlowRate, "Flow rate should be updated for 300 USDC/month");

        // Warp to third month and update schedule to 1100 USDC
        vm.warp(startDate + 3 * 30 days);

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, 1100 ether);

        // Verify the flow rate has been updated again
        schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

        (settledAmount,) = vestingScheduler.accountings(_helperGetScheduleId(address(superToken), alice, bob));

        // Calculate new flow rate for remaining 3 months
        remainingMonths = 3;
        remainingAmount = 1100 ether - settledAmount;
        expectedFlowRate = SafeCast.toInt96(SafeCast.toInt256(remainingAmount / (schedule.endDate - block.timestamp)));
        assertEq(schedule.flowRate, expectedFlowRate, "Flow rate should be updated for 200 USDC/month");

        // Warp to last month and update schedule to 1500 USDC
        vm.warp(startDate + 4 * 30 days);

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, 1500 ether);

        // Warp to 24 hours before end date and execute end vesting
        vm.warp(schedule.endDate - 24 hours);

        vm.prank(alice);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeEndVesting should return true");

        // Verify final balances
        assertEq(
            aliceInitialBalance - superToken.balanceOf(alice),
            1500 ether,
            "Alice should have transferred the full 1500 USDC"
        );
        assertEq(
            superToken.balanceOf(bob) - bobInitialBalance, 1500 ether, "Bob should have received the full 1500 USDC"
        );

        // Verify schedule no longer exists
        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    /* Scenario 1 :
    Assuming a 5 month long schedule that requires the receiver to claim the schedule:

    Define schedule for 1000 USDC (guaranteeing only 200USDC for 1 month)

    One month later, update schedule to 1400 USDC (with four months left and 200USDC meant to be transferred, this means 300 USDC/mo)
    The receiver claims the schedule right after the update

    One month later, update schedule to 1100 USDC (with 3 months left, and 500 USDC already transferred, this means 200 USDC/mo)

    At the time of the last month, with the total amount set at 1500 USDC, the stream shall be closed up to ±24hrs early, settling any differences to the expected total
    */
    function testVestingSchedulerV3_scenario_withClaim() public {
        // Initial setup
        uint256 aliceInitialBalance = superToken.balanceOf(alice);
        uint256 bobInitialBalance = superToken.balanceOf(bob);

        // Define constants for the test
        uint256 initialTotalAmount = 1000 ether;
        uint32 totalDuration = 150 days; // 5 months
        uint32 claimPeriod = 60 days; // Receiver has 60 days to claim

        // Set up permissions for Alice
        _setACL_AUTHORIZE_FULL_CONTROL(alice, type(int96).max); // Allow any flow rate

        // Create the initial vesting schedule with claim period
        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        uint32 startDate = uint32(block.timestamp);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            initialTotalAmount,
            totalDuration,
            startDate,
            0, // No cliff period
            claimPeriod // Claim period of 60 days
        );
        vm.stopPrank();

        // Get the schedule
        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

        // Verify initial schedule
        assertEq(schedule.endDate - startDate, totalDuration, "Duration should be 5 months");
        assertEq(schedule.claimValidityDate, startDate + claimPeriod, "Claim validity date should be set correctly");

        // Warp to first month (30 days) and update schedule to 1400 USDC
        vm.warp(startDate + 30 days);

        uint256 updatedTotalAmount = 1400 ether;
        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, updatedTotalAmount);

        assertEq(vestingScheduler.getTotalVestedAmount(superToken, alice, bob), updatedTotalAmount);

        // Get the updated schedule
        schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

        (uint256 settledAmount,) =
            vestingScheduler.accountings(_helperGetScheduleId(address(superToken), alice, bob));

        // Calculate expected flow rate after update
        int96 expectedFlowRate = SafeCast.toInt96(
            SafeCast.toInt256((updatedTotalAmount - settledAmount) / (schedule.endDate - block.timestamp))
        );

        // Verify the flow rate has been updated correctly
        assertApproxEqAbs(
            schedule.flowRate,
            expectedFlowRate,
            1e10, // Allow small rounding differences
            "Flow rate should be updated correctly"
        );

        // Bob claims the schedule right after the update
        vm.prank(bob);
        bool success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(success, "executeCliffAndFlow should return true");

        // Calculate expected amount received at claim time
        // This should be approximately 1 month's worth of the original schedule (200 USDC)
        uint256 expectedClaimAmount = initialTotalAmount / 5; // 200 USDC for first month

        // Verify Bob received the correct amount at claim time
        assertApproxEqAbs(
            superToken.balanceOf(bob) - bobInitialBalance,
            expectedClaimAmount,
            expectedClaimAmount * 10 / 10_000, // Allow 0.1% difference
            "Bob should have received ~200 USDC at claim time"
        );

        // Warp to second month (60 days total)
        vm.warp(startDate + 60 days);

        // Calculate expected amount after second month
        // First month at original rate + second month at updated rate
        uint256 expectedTotalAfterTwoMonths = expectedClaimAmount + (SafeCast.toUint256(expectedFlowRate) * 30 days);

        // Verify Bob's balance after second month
        assertApproxEqAbs(
            superToken.balanceOf(bob) - bobInitialBalance,
            expectedTotalAfterTwoMonths,
            expectedTotalAfterTwoMonths * 10 / 10_000, // Allow 0.1% difference
            "Bob should have received ~500 USDC after second month"
        );

        // Update schedule again to 1100 USDC
        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, 1100 ether);

        assertEq(vestingScheduler.getTotalVestedAmount(superToken, alice, bob), 1100 ether);

        // Warp to third month (90 days total)
        vm.warp(startDate + 90 days);

        (settledAmount,) = vestingScheduler.accountings(_helperGetScheduleId(address(superToken), alice, bob));

        // Calculate expected amount after third month
        // First two months + third month at reduced rate
        schedule = vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        uint256 thirdMonthAmount = (1100 ether - settledAmount) / 3; // ~200 USDC/month

        // Verify Bob's balance after third month
        assertApproxEqAbs(
            superToken.balanceOf(bob) - bobInitialBalance,
            expectedTotalAfterTwoMonths + thirdMonthAmount,
            (expectedTotalAfterTwoMonths + thirdMonthAmount) * 10 / 10_000, // Allow 0.1% difference
            "Bob should have received ~680 USDC after third month"
        );

        // Update schedule one last time to 1500 USDC
        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmount(superToken, bob, 1500 ether);

        assertEq(vestingScheduler.getTotalVestedAmount(superToken, alice, bob), 1500 ether);

        // Warp to 24 hours before end date and execute end vesting
        vm.warp(schedule.endDate - 24 hours);

        vm.prank(alice);
        success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(success, "executeEndVesting should return true");

        // Verify final balances
        assertApproxEqAbs(
            aliceInitialBalance - superToken.balanceOf(alice),
            1500 ether,
            1e16, // Allow small rounding differences
            "Alice should have transferred approximately 1500 USDC"
        );
        assertApproxEqAbs(
            superToken.balanceOf(bob) - bobInitialBalance,
            1500 ether,
            1e16, // Allow small rounding differences
            "Bob should have received approximately 1500 USDC"
        );

        // Verify schedule no longer exists
        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    struct VestingTestState {
        uint256 initialAmount;
        uint256 secondAmount;
        uint256 thirdAmount;
        uint256 finalAmount;
        uint32 totalDuration;
        uint32 durationExtension1;
        uint32 durationExtension2;
        uint32 startDate;
        uint32 firstNewEndDate;
        uint32 secondNewEndDate;
        uint32 finalEndDate;
        uint256 aliceInitialBalance;
        uint256 aliceFinalBalance;
        uint256 bobInitialBalance;
        uint256 bobFinalBalance;
        uint256 retrievedTotalAmount;
        bool success;
    }

    function testVestingSchedulerV3_UpdateVestingSchedule_WithAmountAndEndDate(
        uint256 initialAmount,
        uint256 secondAmount,
        uint256 thirdAmount,
        uint256 finalAmount,
        uint32 totalDuration,
        uint32 durationExtension1,
        uint32 durationExtension2
    ) public {
        VestingTestState memory state;

        // Bound inputs to reasonable values
        state.initialAmount = bound(initialAmount, 500 ether, 2000 ether);

        state.secondAmount = bound(secondAmount, state.initialAmount - 10 ether, state.initialAmount + 10 ether);
        state.thirdAmount = bound(thirdAmount, state.secondAmount - 10 ether, state.secondAmount + 10 ether);
        state.finalAmount = bound(finalAmount, state.thirdAmount - 10 ether, state.thirdAmount + 10 ether);

        // Ensure reasonable durations
        state.totalDuration = uint32(bound(totalDuration, vestingScheduler.MIN_VESTING_DURATION() + 7 days, 180 days));
        state.durationExtension1 = uint32(bound(durationExtension1, 1 days, 3 days));
        state.durationExtension2 = uint32(bound(durationExtension2, 1 days, 3 days));

        // Capture initial balances
        state.aliceInitialBalance = superToken.balanceOf(alice);
        state.bobInitialBalance = superToken.balanceOf(bob);

        // Setup
        _setACL_AUTHORIZE_FULL_CONTROL(alice, type(int96).max);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        // Create initial vesting schedule
        state.startDate = uint32(block.timestamp);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            state.initialAmount,
            state.totalDuration,
            state.startDate,
            0, // No cliff period
            0  // No claim period
        );
        vm.stopPrank();

        // Verify initial total amount
        state.retrievedTotalAmount = vestingScheduler.getTotalVestedAmount(superToken, alice, bob);
        assertEq(state.retrievedTotalAmount, state.initialAmount, "Initial total amount should match");

        // Execute cliff and flow to start vesting
        vm.warp(state.startDate);
        vm.prank(alice);
        state.success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(state.success, "executeCliffAndFlow should succeed");

        console.log("First update - 25% into vesting");
        vm.warp(state.startDate + state.totalDuration/4);

        console.log("Update to secondAmount and extend duration");
        state.firstNewEndDate = state.startDate + state.totalDuration + state.durationExtension1;

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmountAndEndDate(
            superToken,
            bob,
            state.secondAmount,
            state.firstNewEndDate
        );

        // Verify updated total amount
        state.retrievedTotalAmount = vestingScheduler.getTotalVestedAmount(superToken, alice, bob);
        assertEq(state.retrievedTotalAmount, state.secondAmount, "Total amount after first update should match secondAmount");

        console.log("Warp to 50% of original duration");
        vm.warp(state.startDate + state.totalDuration / 2);

        // Second update
        state.secondNewEndDate = state.firstNewEndDate - state.durationExtension2;

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmountAndEndDate(
            superToken,
            bob,
            state.thirdAmount,
            state.secondNewEndDate
        );

        // Verify updated total amount
        state.retrievedTotalAmount = vestingScheduler.getTotalVestedAmount(superToken, alice, bob);
        assertEq(state.retrievedTotalAmount, state.thirdAmount, "Total amount after second update should match thirdAmount");

        console.log("Warp to 75% of original duration");
        vm.warp(state.startDate + (state.totalDuration * 3)/4);

        console.log("Final update");
        state.finalEndDate = state.secondNewEndDate - 1 days;

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmountAndEndDate(
            superToken,
            bob,
            state.finalAmount,
            state.finalEndDate
        );

        // Verify updated total amount
        state.retrievedTotalAmount = vestingScheduler.getTotalVestedAmount(superToken, alice, bob);
        assertEq(state.retrievedTotalAmount, state.finalAmount, "Total amount after final update should match finalAmount");

        // Warp to 12 hours before end and execute end vesting
        vm.warp(state.finalEndDate - 12 hours);

        vm.prank(alice);
        state.success = vestingScheduler.executeEndVesting(superToken, alice, bob);
        assertTrue(state.success, "executeEndVesting should succeed");

        // Verify final balances
        state.aliceFinalBalance = superToken.balanceOf(alice);
        state.bobFinalBalance = superToken.balanceOf(bob);

        assertEq(
            state.aliceInitialBalance - state.aliceFinalBalance,
            state.finalAmount,
            "Alice should have transferred exactly finalAmount"
        );

        assertEq(
            state.bobFinalBalance - state.bobInitialBalance,
            state.finalAmount,
            "Bob should have received exactly finalAmount"
        );

        // Verify schedule no longer exists
        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function testVestingSchedulerV3_UpdateVestingSchedule_WithAmountAndEndDate_AndClaimPeriodExecutedAsSingleTransfer(
        uint256 initialAmount,
        uint256 secondAmount,
        uint256 thirdAmount,
        uint256 finalAmount,
        uint32 totalDuration,
        uint32 durationExtension1,
        uint32 durationExtension2
    ) public {
        VestingTestState memory state;

        // Bound inputs to reasonable values
        state.initialAmount = bound(initialAmount, 500 ether, 2000 ether);

        state.secondAmount = bound(secondAmount, state.initialAmount - 10 ether, state.initialAmount + 10 ether);
        state.thirdAmount = bound(thirdAmount, state.secondAmount - 10 ether, state.secondAmount + 10 ether);
        state.finalAmount = bound(finalAmount, state.thirdAmount - 10 ether, state.thirdAmount + 10 ether);

        // Ensure reasonable durations
        state.totalDuration = uint32(bound(totalDuration, vestingScheduler.MIN_VESTING_DURATION() + 7 days, 180 days));
        state.durationExtension1 = uint32(bound(durationExtension1, 1 days, 3 days));
        state.durationExtension2 = uint32(bound(durationExtension2, 1 days, 3 days));

        // Capture initial balances
        state.aliceInitialBalance = superToken.balanceOf(alice);
        state.bobInitialBalance = superToken.balanceOf(bob);

        // Setup
        _setACL_AUTHORIZE_FULL_CONTROL(alice, type(int96).max);

        vm.startPrank(alice);
        superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

        // Create initial vesting schedule
        state.startDate = uint32(block.timestamp);
        vestingScheduler.createVestingScheduleFromAmountAndDuration(
            superToken,
            bob,
            state.initialAmount,
            state.totalDuration,
            state.startDate,
            0, // No cliff period
            state.totalDuration + 7 days
        );
        vm.stopPrank();

        // Verify initial total amount
        state.retrievedTotalAmount = vestingScheduler.getTotalVestedAmount(superToken, alice, bob);
        assertEq(state.retrievedTotalAmount, state.initialAmount, "Initial total amount should match");

        console.log("First update - 25% into vesting");
        vm.warp(state.startDate + state.totalDuration/4);

        console.log("Update to secondAmount and extend duration");
        state.firstNewEndDate = state.startDate + state.totalDuration + state.durationExtension1;

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmountAndEndDate(
            superToken,
            bob,
            state.secondAmount,
            state.firstNewEndDate
        );

        // Verify updated total amount
        state.retrievedTotalAmount = vestingScheduler.getTotalVestedAmount(superToken, alice, bob);
        assertEq(state.retrievedTotalAmount, state.secondAmount, "Total amount after first update should match secondAmount");

        console.log("Warp to 50% of original duration");
        vm.warp(state.startDate + state.totalDuration / 2);

        // Second update
        state.secondNewEndDate = state.firstNewEndDate - state.durationExtension2;

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmountAndEndDate(
            superToken,
            bob,
            state.thirdAmount,
            state.secondNewEndDate
        );

        // Verify updated total amount
        state.retrievedTotalAmount = vestingScheduler.getTotalVestedAmount(superToken, alice, bob);
        assertEq(state.retrievedTotalAmount, state.thirdAmount, "Total amount after second update should match thirdAmount");

        console.log("Warp to 75% of original duration");
        vm.warp(state.startDate + (state.totalDuration * 3)/4);

        console.log("Final update");
        state.finalEndDate = state.secondNewEndDate - 1 days;

        vm.prank(alice);
        vestingScheduler.updateVestingScheduleFlowRateFromAmountAndEndDate(
            superToken,
            bob,
            state.finalAmount,
            state.finalEndDate
        );

        // Verify updated total amount
        state.retrievedTotalAmount = vestingScheduler.getTotalVestedAmount(superToken, alice, bob);
        assertEq(state.retrievedTotalAmount, state.finalAmount, "Total amount after final update should match finalAmount");

        // Warp to 12 hours before end and execute end vesting
        vm.warp(state.finalEndDate + 1 days);

        vm.prank(alice);
        state.success = vestingScheduler.executeCliffAndFlow(superToken, alice, bob);
        assertTrue(state.success, "executeCliffAndFlow should succeed");

        // Verify final balances
        state.aliceFinalBalance = superToken.balanceOf(alice);
        state.bobFinalBalance = superToken.balanceOf(bob);

        assertEq(
            state.aliceInitialBalance - state.aliceFinalBalance,
            state.finalAmount,
            "Alice should have transferred exactly finalAmount"
        );

        assertEq(
            state.bobFinalBalance - state.bobInitialBalance,
            state.finalAmount,
            "Bob should have received exactly finalAmount"
        );

        // Verify schedule no longer exists
        testAssertScheduleDoesNotExist(address(superToken), alice, bob);
    }

    function testEndVestingScheduleNow_Claimable() public {
       // Setup
       uint256 aliceInitialBalance = superToken.balanceOf(alice);
       uint256 bobInitialBalance = superToken.balanceOf(bob);

       _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
       _createClaimableVestingScheduleWithDefaultData(alice, bob);

       vm.prank(alice);
       superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

       // Warp to midway through vesting but before claiming
       uint256 midwayTime = CLIFF_DATE + (CLAIM_VALIDITY_DATE - CLIFF_DATE) / 2;
       vm.assume(midwayTime < CLAIM_VALIDITY_DATE);
       vm.warp(midwayTime);

       // End vesting now
       vm.prank(alice);
       vestingScheduler.endVestingScheduleNow(superToken, bob);

       // Verify schedule was updated but still exists
       IVestingSchedulerV3.VestingSchedule memory updatedSchedule =
           vestingScheduler.getVestingSchedule(address(superToken), alice, bob);

       assertEq(updatedSchedule.endDate, uint32(block.timestamp), "End date should be updated to current timestamp");

       // Now claim the schedule
       vm.prank(bob);
       vestingScheduler.executeCliffAndFlow(superToken, alice, bob);

       // Verify the full amount was transferred
       uint256 totalAmount = CLIFF_TRANSFER_AMOUNT + (END_DATE - CLIFF_DATE) * uint256(uint96(FLOW_RATE));

       assertApproxEqAbs(
           superToken.balanceOf(bob) - bobInitialBalance,
           totalAmount,
           1e16, // Allow small rounding differences
           "Bob should have received the full amount"
       );

       assertApproxEqAbs(
           aliceInitialBalance - superToken.balanceOf(alice),
           totalAmount,
           1e16, // Allow small rounding differences
           "Alice's balance should have decreased by the full amount"
       );

       // Verify schedule no longer exists
       testAssertScheduleDoesNotExist(address(superToken), alice, bob);
   }

   function testEndVestingScheduleNow_NonClaimable() public {
       // Setup
       uint256 aliceInitialBalance = superToken.balanceOf(alice);
       uint256 bobInitialBalance = superToken.balanceOf(bob);

       _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
       _createVestingScheduleWithDefaultData(alice, bob);

       vm.prank(alice);
       superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

       // Warp to after cliff date and execute cliff and flow
       vm.warp(CLIFF_DATE + 1 days);
       vm.prank(admin);
       vestingScheduler.executeCliffAndFlow(superToken, alice, bob);

       // Warp to midway through vesting
       uint256 midwayTime = CLIFF_DATE + (END_DATE - CLIFF_DATE) / 2;
       vm.warp(midwayTime);

       // Calculate expected vested amount
       uint256 expectedVestedAmount = CLIFF_TRANSFER_AMOUNT +
           (block.timestamp - CLIFF_DATE) * uint256(uint96(FLOW_RATE));

       // End vesting now
       vm.expectEmit(true, true, true, true);
       emit VestingEndExecuted(superToken, alice, bob, uint32(block.timestamp), 0, false);

       vm.prank(alice);
       vestingScheduler.endVestingScheduleNow(superToken, bob);

       // Verify schedule no longer exists
       testAssertScheduleDoesNotExist(address(superToken), alice, bob);

       // Verify correct amounts were transferred
       assertApproxEqAbs(
           superToken.balanceOf(bob) - bobInitialBalance,
           expectedVestedAmount,
           1e16, // Allow small rounding differences
           "Bob should have received the expected vested amount"
       );

       assertApproxEqAbs(
           aliceInitialBalance - superToken.balanceOf(alice),
           expectedVestedAmount,
           1e16, // Allow small rounding differences
           "Alice's balance should have decreased by the expected vested amount"
       );
   }

   function testEndVestingScheduleNow_NonClaimable_WithoutCliffAndFlowExecuted() public {
       // Setup
       uint256 aliceInitialBalance = superToken.balanceOf(alice);
       uint256 bobInitialBalance = superToken.balanceOf(bob);

       _setACL_AUTHORIZE_FULL_CONTROL(alice, FLOW_RATE);
       _createVestingScheduleWithDefaultData(alice, bob);

       vm.prank(alice);
       superToken.increaseAllowance(address(vestingScheduler), type(uint256).max);

       // Warp to after cliff date and execute cliff and flow
       vm.warp(CLIFF_DATE + 1 days);

       // Calculate expected vested amount
       uint256 expectedVestedAmount = CLIFF_TRANSFER_AMOUNT +
           (block.timestamp - CLIFF_DATE) * uint256(uint96(FLOW_RATE));

       uint256 flowDelayCompensation = (block.timestamp - CLIFF_DATE) * uint256(uint96(FLOW_RATE));

       // End vesting now
       vm.expectEmit(true, true, true, true);
       emit VestingCliffAndFlowExecuted(
           superToken, alice, bob, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, flowDelayCompensation
       );

       // End vesting now
       vm.expectEmit(true, true, true, true);
       emit VestingEndExecuted(superToken, alice, bob, uint32(block.timestamp), 0, false);

       vm.prank(alice);
       vestingScheduler.endVestingScheduleNow(superToken, bob);

       // Verify schedule no longer exists
       testAssertScheduleDoesNotExist(address(superToken), alice, bob);

       // Verify correct amounts were transferred
       assertApproxEqAbs(
           superToken.balanceOf(bob) - bobInitialBalance,
           expectedVestedAmount,
           1e16, // Allow small rounding differences
           "Bob should have received the expected vested amount"
       );

       assertApproxEqAbs(
           aliceInitialBalance - superToken.balanceOf(alice),
           expectedVestedAmount,
           1e16, // Allow small rounding differences
           "Alice's balance should have decreased by the expected vested amount"
       );
   }

    function test_use_2771_forward_call() public {
        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, 0
        );
        _arrangeAllowances(alice, FLOW_RATE);
        vm.stopPrank();

        vm.warp(CLIFF_DATE != 0 ? CLIFF_DATE : START_DATE);
        vestingScheduler.executeCliffAndFlow(superToken, alice, bob);

        uint32 newEndDate = END_DATE + 1234;
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC2771_FORWARD_CALL,
            target: address(vestingScheduler),
            data: abi.encodeCall(vestingScheduler.updateVestingScheduleFlowRateFromEndDate, (superToken, bob, newEndDate))
        });

        // Act
        vm.prank(alice);
        sf.host.batchCall(ops);
        vm.stopPrank();

        // Assert
        IVestingSchedulerV3.VestingSchedule memory schedule =
            vestingScheduler.getVestingSchedule(address(superToken), alice, bob);
        assertEq(schedule.endDate, newEndDate);
    }

    function test_use_2771_forward_call_revert() public {
        vm.startPrank(alice);
        vestingScheduler.createVestingSchedule(
            superToken, bob, START_DATE, CLIFF_DATE, FLOW_RATE, CLIFF_TRANSFER_AMOUNT, END_DATE, 0
        );
        _arrangeAllowances(alice, FLOW_RATE);
        vm.stopPrank();

        vm.warp(CLIFF_DATE != 0 ? CLIFF_DATE : START_DATE);
        vestingScheduler.executeCliffAndFlow(superToken, alice, bob);

        uint32 newEndDate = END_DATE + 1234;
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC2771_FORWARD_CALL,
            target: address(vestingScheduler),
            data: abi.encodeCall(vestingScheduler.updateVestingScheduleFlowRateFromEndDate, (superToken, bob, newEndDate))
        });

        // Act & Assert
        vm.prank(bob); // Not the sender
        vm.expectRevert(IVestingSchedulerV2.ScheduleDoesNotExist.selector);
        sf.host.batchCall(ops);
        vm.stopPrank();
    }

    function _helperGetScheduleId(address superToken, address sender, address receiver)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(superToken, sender, receiver));
    }
}
