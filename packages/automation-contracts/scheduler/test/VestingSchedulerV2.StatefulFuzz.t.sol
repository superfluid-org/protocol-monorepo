// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {FlowOperatorDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IVestingSchedulerV2} from "./../contracts/interface/IVestingSchedulerV2.sol";
import {VestingSchedulerV2} from "./../contracts/VestingSchedulerV2.sol";
import {FoundrySuperfluidTester} from "@superfluid-finance/ethereum-contracts/test/foundry/FoundrySuperfluidTester.t.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import "forge-std/console2.sol";

/// @title VestingSchedulerTests
contract VestingSchedulerV2StatefulFuzzTests is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    /// @dev This is required by solidity for using the SuperTokenV1Library in the tester
    VestingSchedulerV2 public vestingScheduler;

    /// @dev Constants for Testing
    uint256 constant MIN_CLIFF_AMOUNT = 2;
    uint256 constant MAX_CLIFF_AMOUNT = 1_000e18;
    int96 constant MIN_FLOW_RATE = 1;
    int96 constant MAX_FLOW_RATE = 1_000e18;
    bytes constant EMPTY_CTX = "";

    uint8 constant numOfTesters = 5;

    constructor() FoundrySuperfluidTester(numOfTesters) {
        vestingScheduler = new VestingSchedulerV2(sf.host);
    }

    /// SETUP AND HELPERS
    function setUp() public virtual override {
        vm.setEnv(TOKEN_TYPE_ENV_KEY, "WRAPPER_SUPER_TOKEN");
        super.setUp();
    }

    enum TestActionType {
        TA_CREATE_SCHEDULE,
        TA_UPDATE_SCHEDULE,
        TA_DELETE_SCHEDULE,
        TA_EXECUTE_SCHEDULE,
        TA_TERMINATE_SCHEDULE
        // TA_CREATE_CLAIMABLE_SCHEDULE,
    }

    struct Actions {
        uint8 actionCode;
        uint256 testerId;
        address receiver;
        uint32 startDate;
        uint32 cliffDate;
        int96 flowRate;
        uint256 cliffAmount;
        uint32 endDate;
        uint32 newEndDate;
    }

    function toActionType(
        uint8 actionCode,
        uint8 maxAction
    ) internal pure returns (TestActionType) {
        return TestActionType(actionCode % maxAction);
    }

    function test_StatefulFuzz(Actions[10] calldata actions) external {
        for (uint256 i = 0; i < actions.length; i++) {
            console2.log("ITERATION ID : %d", i);
            Actions memory a = actions[i];
            TestActionType t = toActionType(a.actionCode, 5);

            a.testerId = bound(a.testerId, 0, 4);
            address sender = TEST_ACCOUNTS[a.testerId];

            vm.assume(
                vestingScheduler
                    .getVestingSchedule(address(superToken), sender, a.receiver)
                    .flowRate == 0
            );

            vm.assume(a.receiver != address(0) && sender != a.receiver);
            a.flowRate = int96(bound(a.flowRate, 1, 1000e18));
            a.startDate = uint32(
                bound(
                    a.startDate,
                    uint32(block.timestamp),
                    uint32(block.timestamp + 3650 days)
                )
            );
            a.endDate = uint32(
                bound(
                    a.endDate,
                    a.startDate + vestingScheduler.MIN_VESTING_DURATION() + 1,
                    a.startDate + uint32(3650 days)
                )
            );
            if (a.cliffDate == 0) {
                a.cliffAmount = 0;
                vm.assume(a.startDate < a.endDate);
                vm.assume(
                    a.startDate + vestingScheduler.START_DATE_VALID_AFTER() <
                        a.endDate - vestingScheduler.END_DATE_VALID_BEFORE()
                );
            } else {
                a.cliffAmount = bound(a.cliffAmount, 1e18, 1000e18);
                a.cliffDate = uint32(
                    bound(a.cliffDate, a.startDate, a.endDate - 1)
                );
                vm.assume(
                    a.endDate - a.cliffDate >
                        vestingScheduler.MIN_VESTING_DURATION()
                );
                vm.assume(
                    a.cliffDate + vestingScheduler.START_DATE_VALID_AFTER() <
                        a.endDate - vestingScheduler.END_DATE_VALID_BEFORE()
                );
            }

            if (t == TestActionType.TA_CREATE_SCHEDULE) {
                _test_createVestingSchedule(
                    sender,
                    a.receiver,
                    a.startDate,
                    a.cliffDate,
                    a.flowRate,
                    a.cliffAmount,
                    a.endDate
                );
            } else if (t == TestActionType.TA_UPDATE_SCHEDULE) {
                _test_updateVestingSchedule(
                    sender,
                    a.receiver,
                    a.startDate,
                    a.cliffDate,
                    a.flowRate,
                    a.cliffAmount,
                    a.endDate,
                    a.newEndDate
                );
            } else if (t == TestActionType.TA_DELETE_SCHEDULE) {
                _test_deleteVestingSchedule(
                    sender,
                    a.receiver,
                    a.startDate,
                    a.cliffDate,
                    a.flowRate,
                    a.cliffAmount,
                    a.endDate
                );
            } else if (t == TestActionType.TA_EXECUTE_SCHEDULE) {
                _test_executeCliffAndFlow(
                    sender,
                    a.receiver,
                    a.startDate,
                    a.cliffDate,
                    a.flowRate,
                    a.cliffAmount,
                    a.endDate
                );
            } else if (t == TestActionType.TA_TERMINATE_SCHEDULE) {
                _test_executeEndVesting(
                    sender,
                    a.receiver,
                    a.startDate,
                    a.cliffDate,
                    a.flowRate,
                    a.cliffAmount,
                    a.endDate
                );
            } else assert(false);
        }
    }

    function _test_createVestingSchedule(
        address sender,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate
    ) internal {
        _createVestingSchedule(
            sender,
            receiver,
            startDate,
            cliffDate,
            flowRate,
            cliffAmount,
            endDate
        );

        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler
            .getVestingSchedule(address(superToken), sender, receiver);

        uint32 cliffAndFlowDate = cliffDate == 0 ? startDate : cliffDate;
        assertTrue(
            schedule.cliffAndFlowDate == cliffAndFlowDate,
            "schedule.cliffAndFlowDate"
        );
        assertTrue(schedule.endDate == endDate, "schedule.endDate");
        assertTrue(schedule.flowRate == flowRate, "schedule.flowRate");
        assertTrue(schedule.cliffAmount == cliffAmount, "schedule.cliffAmount");
        assertTrue(
            schedule.claimValidityDate == 0,
            "schedule.claimValidityDate"
        );
    }

    function _test_executeCliffAndFlow(
        address sender,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate
    ) internal {
        _createVestingSchedule(
            sender,
            receiver,
            startDate,
            cliffDate,
            flowRate,
            cliffAmount,
            endDate
        );

        _provisionSender(sender);
        _arrangeAllowances(sender, flowRate);

        // Set the time to 1 second after the cliff and flow date
        vm.warp(cliffDate == 0 ? startDate + 1 : cliffDate + 1);

        bool success = vestingScheduler.executeCliffAndFlow(
            superToken,
            sender,
            receiver
        );

        assertTrue(success, "executeCliffAndFlow should return true");

        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler
            .getVestingSchedule(address(superToken), sender, receiver);
        assertTrue(schedule.cliffAndFlowDate == 0, "schedule.cliffAndFlowDate");
        assertTrue(schedule.cliffAmount == 0, "schedule.cliffAmount");
    }

    function _test_updateVestingSchedule(
        address sender,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate,
        uint32 newEndDate
    ) internal {
        _createVestingSchedule(
            sender,
            receiver,
            startDate,
            cliffDate,
            flowRate,
            cliffAmount,
            endDate
        );

        _provisionSender(sender);
        _arrangeAllowances(sender, flowRate);

        // Set the time to 1 second after the cliff and flow date
        vm.warp(cliffDate == 0 ? startDate + 1 : cliffDate + 1);
        vestingScheduler.executeCliffAndFlow(superToken, sender, receiver);

        vm.assume(newEndDate > block.timestamp);
        vm.prank(sender);
        vestingScheduler.updateVestingSchedule(
            superToken,
            receiver,
            newEndDate,
            EMPTY_CTX
        );

        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler
            .getVestingSchedule(address(superToken), sender, receiver);
        assertTrue(schedule.endDate == newEndDate, "schedule.cliffAndFlowDate");
        assertTrue(schedule.remainderAmount == 0, "schedule.remainderAmount");
    }

    function _test_executeEndVesting(
        address sender,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate
    ) internal {
        _createVestingSchedule(
            sender,
            receiver,
            startDate,
            cliffDate,
            flowRate,
            cliffAmount,
            endDate
        );

        _provisionSender(sender);
        _arrangeAllowances(sender, flowRate);

        // Set the time to 1 second after the cliff and flow date
        vm.warp(cliffDate == 0 ? startDate + 1 : cliffDate + 1);

        vestingScheduler.executeCliffAndFlow(superToken, sender, receiver);

        vm.warp(endDate - vestingScheduler.END_DATE_VALID_BEFORE() + 1);

        bool success = vestingScheduler.executeEndVesting(
            superToken,
            sender,
            receiver
        );
        assertTrue(success, "executeEndVesting should return true");

        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler
            .getVestingSchedule(address(superToken), sender, receiver);
        assertTrue(schedule.cliffAndFlowDate == 0, "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == 0, "schedule.endDate");
        assertTrue(schedule.flowRate == 0, "schedule.flowRate");
        assertTrue(schedule.cliffAmount == 0, "schedule.cliffAmount");
        assertTrue(
            schedule.claimValidityDate == 0,
            "schedule.claimValidityDate"
        );
        assertTrue(schedule.remainderAmount == 0, "schedule.remainderAmount");
    }

    function _test_deleteVestingSchedule(
        address sender,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate
    ) internal {
        _createVestingSchedule(
            sender,
            receiver,
            startDate,
            cliffDate,
            flowRate,
            cliffAmount,
            endDate
        );

        vm.prank(sender);
        vestingScheduler.deleteVestingSchedule(superToken, receiver, EMPTY_CTX);

        //assert storage data
        VestingSchedulerV2.VestingSchedule memory schedule = vestingScheduler
            .getVestingSchedule(address(superToken), sender, receiver);
        assertTrue(schedule.cliffAndFlowDate == 0, "schedule.cliffAndFlowDate");
        assertTrue(schedule.endDate == 0, "schedule.endDate");
        assertTrue(schedule.flowRate == 0, "schedule.flowRate");
        assertTrue(schedule.cliffAmount == 0, "schedule.cliffAmount");
        assertTrue(
            schedule.claimValidityDate == 0,
            "schedule.claimValidityDate"
        );
        assertTrue(schedule.remainderAmount == 0, "schedule.remainderAmount");
    }

    function _createVestingSchedule(
        address sender,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate
    ) private {
        vm.prank(sender);
        vestingScheduler.createVestingSchedule(
            superToken,
            receiver,
            startDate,
            cliffDate,
            flowRate,
            cliffAmount,
            endDate,
            0,
            EMPTY_CTX
        );
    }

    function _provisionSender(address sender) private {
        token.mint(sender, INIT_TOKEN_BALANCE);
        vm.startPrank(sender);
        token.approve(address(superToken), INIT_TOKEN_BALANCE);
        superToken.upgrade(INIT_TOKEN_BALANCE);
        vm.stopPrank();
    }

    function _arrangeAllowances(address sender, int96 flowRate) private {
        vm.startPrank(sender);
        // ## Superfluid ACL allowance and permissions
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

        // ## ERC-20 allowance for cliff and compensation transfers
        superToken.approve(address(vestingScheduler), type(uint256).max);
        vm.stopPrank();
    }
}