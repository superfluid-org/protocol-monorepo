// SPDX-License-Identifier: AGPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;
import {
    ISuperfluid, ISuperToken, SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { IVestingSchedulerV2 } from "./interface/IVestingSchedulerV2.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract VestingSchedulerV2 is IVestingSchedulerV2, SuperAppBase {

    using SuperTokenV1Library for ISuperToken;

    ISuperfluid public immutable HOST;
    mapping(bytes32 => VestingSchedule) public vestingSchedules; // id = keccak(supertoken, sender, receiver)

    uint32 public constant MIN_VESTING_DURATION = 7 days;
    uint32 public constant START_DATE_VALID_AFTER = 3 days;
    uint32 public constant END_DATE_VALID_BEFORE = 1 days;

    struct ScheduleAggregate {
        ISuperToken superToken;
        address sender;
        address receiver;
        bytes32 id;
        VestingSchedule schedule;
    }

    constructor(ISuperfluid host) {
        // Superfluid SuperApp registration. This is a dumb SuperApp, only for front-end tx batch calls.
        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
        SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
        SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP |
        SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
        SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP |
        SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
        SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;
        host.registerApp(configWord);
        HOST = host;
    }

    /// @dev IVestingScheduler.createVestingSchedule implementation.
    function createVestingSchedule(
        ISuperToken superToken,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate,
        uint32 claimValidityDate,
        bytes memory ctx
    ) external returns (bytes memory newCtx) {
        newCtx = ctx;
        address sender = _getSender(ctx);

        _validateAndCreateVestingSchedule(
            ScheduleCreationParams({
                superToken: superToken,
                sender: sender,
                receiver: receiver,
                startDate: _normalizeStartDate(startDate),
                claimValidityDate: claimValidityDate,
                cliffDate: cliffDate,
                flowRate: flowRate,
                cliffAmount: cliffAmount,
                endDate: endDate,
                remainderAmount: 0
            })
        );
    }

    /// @dev IVestingScheduler.createVestingSchedule implementation.
    function createVestingSchedule(
        ISuperToken superToken,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate,
        uint32 claimValidityDate
    ) external {
        _validateAndCreateVestingSchedule(
            ScheduleCreationParams({
                superToken: superToken,
                sender: msg.sender,
                receiver: receiver,
                startDate: _normalizeStartDate(startDate),
                claimValidityDate: claimValidityDate,
                cliffDate: cliffDate,
                flowRate: flowRate,
                cliffAmount: cliffAmount,
                endDate: endDate,
                remainderAmount: 0
            })
        );
    }

    /// @dev IVestingScheduler.createVestingSchedule implementation.
    /// @dev Note: VestingScheduler (V1) compatible function
    function createVestingSchedule(
        ISuperToken superToken,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate,
        bytes memory ctx
    ) external returns (bytes memory newCtx) {
        newCtx = ctx;
        address sender = _getSender(ctx);

        _validateAndCreateVestingSchedule(
            ScheduleCreationParams({
                superToken: superToken,
                sender: sender,
                receiver: receiver,
                startDate: _normalizeStartDate(startDate),
                claimValidityDate: 0,
                cliffDate: cliffDate,
                flowRate: flowRate,
                cliffAmount: cliffAmount,
                endDate: endDate,
                remainderAmount: 0
            })
        );
    }

    /// @dev IVestingScheduler.createVestingScheduleFromAmountAndDuration implementation.
    /// @dev Note: creating from amount and duration is the preferred way
    function createVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod,
        bytes memory ctx
    ) external returns (bytes memory newCtx) {
        newCtx = ctx;
        address sender = _getSender(ctx);
        
        _validateAndCreateVestingSchedule(
            mapCreateVestingScheduleParams(
                superToken,
                sender,
                receiver,
                totalAmount,
                totalDuration,
                _normalizeStartDate(startDate),
                cliffPeriod,
                claimPeriod
            )
        );
    }

    /// @dev IVestingScheduler.createVestingScheduleFromAmountAndDuration implementation.
    function createVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod
    ) external {
        _validateAndCreateVestingSchedule(
            mapCreateVestingScheduleParams(
                superToken,
                msg.sender,
                receiver,
                totalAmount,
                totalDuration,
                _normalizeStartDate(startDate),
                cliffPeriod,
                claimPeriod
            )
        );
    }

    /// @dev IVestingScheduler.mapCreateVestingScheduleParams implementation.
    function mapCreateVestingScheduleParams(
        ISuperToken superToken,
        address sender,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod
    ) public pure override returns (ScheduleCreationParams memory params) {
        uint32 claimValidityDate = claimPeriod != 0
            ? startDate + claimPeriod
            : 0;

        uint32 endDate = startDate + totalDuration;
        int96 flowRate = SafeCast.toInt96(
            SafeCast.toInt256(totalAmount / totalDuration)
        );
        uint96 remainderAmount = SafeCast.toUint96(
            totalAmount - (SafeCast.toUint256(flowRate) * totalDuration)
        );

        if (cliffPeriod == 0) {
            params = ScheduleCreationParams({
                superToken: superToken,
                sender: sender,
                receiver: receiver,
                startDate: startDate,
                claimValidityDate: claimValidityDate,
                cliffDate: 0,
                flowRate: flowRate,
                cliffAmount: 0,
                endDate: endDate,
                remainderAmount: remainderAmount
            });
        } else {
            uint256 cliffAmount = SafeMath.mul(
                cliffPeriod,
                SafeCast.toUint256(flowRate)
            );
            params = ScheduleCreationParams({
                superToken: superToken,
                sender: sender,
                receiver: receiver,
                startDate: startDate,
                claimValidityDate: claimValidityDate,
                cliffDate: startDate + cliffPeriod,
                flowRate: flowRate,
                cliffAmount: cliffAmount,
                endDate: endDate,
                remainderAmount: remainderAmount
            });
        }
    }

    function _validateAndCreateVestingSchedule(
        ScheduleCreationParams memory params
    ) private {
        // Note: Vesting Scheduler V2 doesn't allow start date to be in the past.
        // V1 did but didn't allow cliff and flow to be in the past though.
        if (params.startDate < block.timestamp) revert TimeWindowInvalid();
        if (params.endDate <= END_DATE_VALID_BEFORE) revert TimeWindowInvalid();

        if (params.receiver == address(0) || params.receiver == params.sender) revert AccountInvalid();
        if (address(params.superToken) == address(0)) revert ZeroAddress();
        if (params.flowRate <= 0) revert FlowRateInvalid();
        if (params.cliffDate != 0 && params.startDate > params.cliffDate) revert TimeWindowInvalid();
        if (params.cliffDate == 0 && params.cliffAmount != 0) revert CliffInvalid();

        uint32 cliffAndFlowDate = params.cliffDate == 0 ? params.startDate : params.cliffDate;
        // Note: Vesting Scheduler V2 allows cliff and flow to be in the schedule creation block, V1 didn't.
        if (cliffAndFlowDate < block.timestamp ||
            cliffAndFlowDate >= params.endDate ||
            cliffAndFlowDate + START_DATE_VALID_AFTER >= params.endDate - END_DATE_VALID_BEFORE ||
            params.endDate - cliffAndFlowDate < MIN_VESTING_DURATION
        ) revert TimeWindowInvalid();

        // Note : claimable schedule created with a claim validity date equal to 0 is considered regular schedule
        if (params.claimValidityDate != 0 && params.claimValidityDate < cliffAndFlowDate) 
            revert TimeWindowInvalid();

        bytes32 id = _getId(address(params.superToken), params.sender, params.receiver);
        if (vestingSchedules[id].endDate != 0) revert ScheduleAlreadyExists();

        vestingSchedules[id] = VestingSchedule({
            cliffAndFlowDate: cliffAndFlowDate,
            endDate: params.endDate,
            flowRate: params.flowRate,
            cliffAmount: params.cliffAmount,
            remainderAmount: params.remainderAmount,
            claimValidityDate: params.claimValidityDate
        });

        emit VestingScheduleCreated(
            params.superToken,
            params.sender,
            params.receiver,
            params.startDate,
            params.cliffDate,
            params.flowRate,
            params.endDate,
            params.cliffAmount,
            params.claimValidityDate,
            params.remainderAmount
        );
    }

    /// @dev IVestingScheduler.createAndExecuteVestingScheduleFromAmountAndDuration.
    function createAndExecuteVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        bytes memory ctx
    ) external returns (bytes memory newCtx) {
        newCtx = _validateAndCreateAndExecuteVestingScheduleFromAmountAndDuration(
            superToken,
            receiver,
            totalAmount,
            totalDuration,
            ctx
        );
    }

    /// @dev IVestingScheduler.createAndExecuteVestingScheduleFromAmountAndDuration.
    function createAndExecuteVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration
    ) external {
        _validateAndCreateAndExecuteVestingScheduleFromAmountAndDuration(
            superToken,
            receiver,
            totalAmount,
            totalDuration,
            bytes("")
        );
    }

    /// @dev IVestingScheduler.createAndExecuteVestingScheduleFromAmountAndDuration.
    function _validateAndCreateAndExecuteVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        bytes memory ctx
    ) private returns (bytes memory newCtx) {
        newCtx = ctx;
        address sender = _getSender(ctx);

        _validateAndCreateVestingSchedule(
            mapCreateVestingScheduleParams(
                superToken,
                sender,
                receiver,
                totalAmount,
                totalDuration,
                _normalizeStartDate(0),
                0, // cliffPeriod
                0 // claimValidityDate
            )
        );

        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);

        _validateBeforeCliffAndFlow(agg.schedule, /* disableClaimCheck: */ false);
        assert(_executeCliffAndFlow(agg));
    }

    /// @dev IVestingScheduler.updateVestingSchedule implementation.
    function updateVestingSchedule(
        ISuperToken superToken,
        address receiver,
        uint32 endDate,
        bytes memory ctx
    ) external returns (bytes memory newCtx) {
        newCtx = ctx;
        address sender = _getSender(ctx);
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);
        VestingSchedule memory schedule = agg.schedule;

        if (endDate <= block.timestamp) revert TimeWindowInvalid();

        // Note: Claimable schedules that have not been claimed cannot be updated

        // Only allow an update if 1. vesting exists 2. executeCliffAndFlow() has been called
        if (schedule.cliffAndFlowDate != 0 || schedule.endDate == 0) revert ScheduleNotFlowing();

        vestingSchedules[agg.id].endDate = endDate;
        // Note: Nullify the remainder amount when complexity of updates is introduced.
        vestingSchedules[agg.id].remainderAmount = 0;

        emit VestingScheduleUpdated(
            superToken,
            sender,
            receiver,
            schedule.endDate,
            endDate,
            0 // remainderAmount
        );
    }

    /// @dev IVestingScheduler.deleteVestingSchedule implementation.
    function deleteVestingSchedule(
        ISuperToken superToken,
        address receiver,
        bytes memory ctx
    ) external returns (bytes memory newCtx) {
        newCtx = ctx;
        address sender = _getSender(ctx);
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);
        VestingSchedule memory schedule = agg.schedule;

        if (schedule.endDate != 0) {
            delete vestingSchedules[agg.id];
            emit VestingScheduleDeleted(superToken, sender, receiver);
        } else {
            revert ScheduleDoesNotExist();
        }
    }

    /// @dev IVestingScheduler.executeCliffAndFlow implementation.
    function executeCliffAndFlow(
        ISuperToken superToken,
        address sender,
        address receiver
    ) external returns (bool success) {
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);
        VestingSchedule memory schedule = agg.schedule;

        if (schedule.claimValidityDate != 0) {
            _validateAndClaim(agg);
            _validateBeforeCliffAndFlow(schedule, /* disableClaimCheck: */ true);
            if (block.timestamp >= _gteDateToExecuteEndVesting(schedule)) {
                _validateBeforeEndVesting(schedule, /* disableClaimCheck: */ true);
                success = _executeVestingAsSingleTransfer(agg);
            } else {
                success = _executeCliffAndFlow(agg);
            }
        } else {
            _validateBeforeCliffAndFlow(schedule, /* disableClaimCheck: */ false);
            success = _executeCliffAndFlow(agg);
        }
    }

    function _validateBeforeCliffAndFlow(
        VestingSchedule memory schedule,
        bool disableClaimCheck
    ) private view {
        if (schedule.cliffAndFlowDate == 0) 
            revert AlreadyExecuted();

        if (!disableClaimCheck && schedule.claimValidityDate != 0) 
            revert ScheduleNotClaimed();

        // Ensure that that the claming date is after the cliff/flow date and before the claim validity date
        if (schedule.cliffAndFlowDate > block.timestamp || 
            _lteDateToExecuteCliffAndFlow(schedule) < block.timestamp)
                revert TimeWindowInvalid();
    }

    function _lteDateToExecuteCliffAndFlow(
        VestingSchedule memory schedule
    ) private pure returns (uint32) {
        if (schedule.cliffAndFlowDate == 0) 
            revert AlreadyExecuted();

        if (schedule.claimValidityDate != 0) {
            return schedule.claimValidityDate;
        } else {
            return schedule.cliffAndFlowDate + START_DATE_VALID_AFTER;
        }
    }

    function _validateAndClaim(
        ScheduleAggregate memory agg
    ) private {
        VestingSchedule memory schedule = agg.schedule;

        // Ensure that the caller is the sender or the receiver if the vesting schedule requires claiming.
        if (msg.sender != agg.sender && msg.sender != agg.receiver)
            revert CannotClaimScheduleOnBehalf();

        if (schedule.claimValidityDate < block.timestamp)
            revert TimeWindowInvalid();
        
        delete vestingSchedules[agg.id].claimValidityDate;
        emit VestingClaimed(agg.superToken, agg.sender, agg.receiver, msg.sender);
    }

    /// @dev IVestingScheduler.executeCliffAndFlow implementation.
    function _executeCliffAndFlow(
        ScheduleAggregate memory agg
    ) private returns (bool success) {
        VestingSchedule memory schedule = agg.schedule;

        // Invalidate configuration straight away -- avoid any chance of re-execution or re-entry.
        delete vestingSchedules[agg.id].cliffAndFlowDate;
        delete vestingSchedules[agg.id].cliffAmount;

        // Compensate for the fact that flow will almost always be executed slightly later than scheduled.
        uint256 flowDelayCompensation = 
            (block.timestamp - schedule.cliffAndFlowDate) * uint96(schedule.flowRate);
        
        // If there's cliff or compensation then transfer that amount.
        if (schedule.cliffAmount != 0 || flowDelayCompensation != 0) {
            // Note: Super Tokens revert, not return false, i.e. we expect always true here.
            assert(
                agg.superToken.transferFrom(
                    agg.sender, agg.receiver, schedule.cliffAmount + flowDelayCompensation));
        }
        // Create a flow according to the vesting schedule configuration.
        agg.superToken.createFlowFrom(agg.sender, agg.receiver, schedule.flowRate);
        emit VestingCliffAndFlowExecuted(
            agg.superToken,
            agg.sender,
            agg.receiver,
            schedule.cliffAndFlowDate,
            schedule.flowRate,
            schedule.cliffAmount,
            flowDelayCompensation
        );

        return true;
    }

    function _executeVestingAsSingleTransfer(
        ScheduleAggregate memory agg
    ) private returns (bool success) {
        VestingSchedule memory schedule = agg.schedule;

        delete vestingSchedules[agg.id];

        uint256 totalVestedAmount = _getTotalVestedAmount(schedule);

        // Note: Super Tokens revert, not return false, i.e. we expect always true here.
        assert(agg.superToken.transferFrom(agg.sender, agg.receiver, totalVestedAmount));

        emit VestingCliffAndFlowExecuted(
            agg.superToken,
            agg.sender,
            agg.receiver,
            schedule.cliffAndFlowDate,
            0, // flow rate
            schedule.cliffAmount,
            totalVestedAmount - schedule.cliffAmount // flow delay compensation
        );

        emit VestingEndExecuted(
            agg.superToken,
            agg.sender,
            agg.receiver,
            schedule.endDate,
            0, // Early end compensation
            false // Did end fail
        );

        return true;
    }

    function _getTotalVestedAmount(
        VestingSchedule memory schedule
    ) private pure returns (uint256) {
        return
            schedule.cliffAmount + 
            schedule.remainderAmount + 
            (schedule.endDate - schedule.cliffAndFlowDate) * SafeCast.toUint256(schedule.flowRate);
    }

    /// @dev IVestingScheduler.executeEndVesting implementation.
    function executeEndVesting(
        ISuperToken superToken,
        address sender,
        address receiver
    ) external returns (bool success) {
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);
        VestingSchedule memory schedule = agg.schedule;

        _validateBeforeEndVesting(schedule, /* disableClaimCheck: */ false);

        // Invalidate configuration straight away -- avoid any chance of re-execution or re-entry.
        delete vestingSchedules[agg.id];

        // If vesting is not running, we can't do anything, just emit failing event.
        if (_isFlowOngoing(superToken, sender, receiver)) {
            // delete first the stream and unlock deposit amount.
            superToken.deleteFlowFrom(sender, receiver);

            uint256 earlyEndCompensation = schedule.endDate >= block.timestamp 
                ? (schedule.endDate - block.timestamp) * uint96(schedule.flowRate) + schedule.remainderAmount
                : 0;

            // Note: we consider the compensation as failed if the stream is still ongoing after the end date.
            bool didCompensationFail = schedule.endDate < block.timestamp;
            if (earlyEndCompensation != 0) {
                // Note: Super Tokens revert, not return false, i.e. we expect always true here.
                assert(superToken.transferFrom(sender, receiver, earlyEndCompensation));
            }

            emit VestingEndExecuted(
                superToken,
                sender,
                receiver,
                schedule.endDate,
                earlyEndCompensation,
                didCompensationFail
            );
        } else {
            emit VestingEndFailed(
                superToken,
                sender,
                receiver,
                schedule.endDate
            );
        }

        return true;
    }

    function _validateBeforeEndVesting(
        VestingSchedule memory schedule,
        bool disableClaimCheck
    ) private view {
        if (schedule.endDate == 0) 
            revert AlreadyExecuted();

        if (!disableClaimCheck && schedule.claimValidityDate != 0) 
            revert ScheduleNotClaimed();

        if (_gteDateToExecuteEndVesting(schedule) > block.timestamp)
            revert TimeWindowInvalid();
    }

    function _gteDateToExecuteEndVesting(
        VestingSchedule memory schedule
    ) private pure returns (uint32) {
        if (schedule.endDate == 0)
            revert AlreadyExecuted();

        return schedule.endDate - END_DATE_VALID_BEFORE;
    }

    /// @dev IVestingScheduler.getVestingSchedule implementation.
    function getVestingSchedule(
        address superToken, address sender, address receiver
    ) external view returns (VestingSchedule memory) {
        return vestingSchedules[_getId(address(superToken), sender, receiver)];
    }

    function _getVestingScheduleAggregate(
        ISuperToken superToken, address sender, address receiver
    ) private view returns (ScheduleAggregate memory) {
        bytes32 id = _getId(address(superToken), sender, receiver);
        return ScheduleAggregate({
            superToken: superToken,
            sender: sender,
            receiver: receiver,
            id: id,
            schedule: vestingSchedules[id]
        });
    }

    function _normalizeStartDate(uint32 startDate) private view returns (uint32) {
        // Default to current block timestamp if no start date is provided.
        if (startDate == 0) {
            return uint32(block.timestamp);
        }
        return startDate;
    }

    /// @dev IVestingScheduler.getMaximumNeededTokenAllowance implementation.
    function getMaximumNeededTokenAllowance(
        VestingSchedule memory schedule
    ) external pure override returns (uint256) {
        uint256 maxFlowDelayCompensationAmount = 
            schedule.cliffAndFlowDate == 0 
                ? 0 
                : START_DATE_VALID_AFTER * SafeCast.toUint256(schedule.flowRate);
        uint256 maxEarlyEndCompensationAmount = 
            schedule.endDate == 0 
                ? 0 
                : END_DATE_VALID_BEFORE * SafeCast.toUint256(schedule.flowRate);

        if (schedule.claimValidityDate == 0) {
            return
                schedule.cliffAmount +
                schedule.remainderAmount +
                maxFlowDelayCompensationAmount +
                maxEarlyEndCompensationAmount;
        } else if (schedule.claimValidityDate >= _gteDateToExecuteEndVesting(schedule)) {
            return _getTotalVestedAmount(schedule);
        } else {
            return schedule.cliffAmount +
                   schedule.remainderAmount +
                   (schedule.claimValidityDate - schedule.cliffAndFlowDate) * SafeCast.toUint256(schedule.flowRate) +
                   maxEarlyEndCompensationAmount;
        }
    }

    /// @dev get sender of transaction from Superfluid Context or transaction itself.
    function _getSender(bytes memory ctx) private view returns (address sender) {
        if (ctx.length != 0) {
            if (msg.sender != address(HOST)) revert HostInvalid();
            sender = HOST.decodeCtx(ctx).msgSender;
        } else {
            sender = msg.sender;
        }
        // This is an invariant and should never happen.
        assert(sender != address(0));
    }

    /// @dev get flowRate of stream
    function _isFlowOngoing(ISuperToken superToken, address sender, address receiver) private view returns (bool) {
        return superToken.getFlowRate(sender, receiver) != 0;
    }

    function _getId(
        address superToken, address sender, address receiver
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(superToken, sender, receiver));
    }
}
