// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import {
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

interface IVestingSchedulerV2 {
    error TimeWindowInvalid();
    error AccountInvalid();
    error ZeroAddress();
    error HostInvalid();
    error FlowRateInvalid();
    error CliffInvalid();
    error ScheduleAlreadyExists();
    error ScheduleDoesNotExist();
    error ScheduleNotFlowing();
    error CannotClaimScheduleOnBehalf();
    error AlreadyExecuted();
    error ScheduleNotClaimed();

    /**
     * @dev Vesting configuration provided by user.
     * @param cliffAndFlowDate Date of flow start and cliff execution (if a cliff was specified)
     * @param endDate End date of the vesting
     * @param claimValidityDate Date before which the claimable schedule must be claimed
     * @param flowRate For the stream
     * @param cliffAmount Amount to be transferred at the cliff
     * @param remainderAmount Amount transferred during early end to achieve an accurate "total vested amount"
     */
    struct VestingSchedule {
        uint32 cliffAndFlowDate;
        uint32 endDate;
        int96 flowRate;

        uint256 cliffAmount;

        uint96 remainderAmount;
        uint32 claimValidityDate;
    }

        /**
     * @dev Parameters used to create vesting schedules
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param startDate Timestamp when the vesting should start
     * @param claimValidityDate Date before which the claimable schedule must be claimed
     * @param cliffDate Timestamp of cliff execution - if 0, startDate acts as cliff
     * @param flowRate The flowRate for the stream
     * @param cliffAmount The amount to be transferred at the cliff
     * @param endDate The timestamp when the stream should stop.
     * @param remainderAmount Amount transferred during early end to achieve an accurate "total vested amount"
     * @param ctx Superfluid context used when batching operations. (or bytes(0) if not SF batching)
     */
    struct ScheduleCreationParams {
        ISuperToken superToken;
        address sender;
        address receiver;
        uint32 startDate;
        uint32 claimValidityDate;
        uint32 cliffDate;
        int96 flowRate;
        uint256 cliffAmount;
        uint32 endDate;
        uint96 remainderAmount;
    }

    /**
     * @dev Event emitted on creation of a new vesting schedule
     * @param superToken SuperToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     * @param startDate Timestamp when the vesting starts
     * @param claimValidityDate Date before which the claimable schedule must be claimed
     * @param cliffDate Timestamp of the cliff
     * @param flowRate The flowRate for the stream
     * @param endDate The timestamp when the stream should stop
     * @param cliffAmount The amount to be transferred at the cliff
     * @param remainderAmount Amount transferred during early end to achieve an accurate "total vested amount"
     */
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

    /**
     * @dev Creates a new vesting schedule
     * @dev If a non-zero cliffDate is set, the startDate has no effect other than being logged in an event.
     * @dev If cliffDate is set to zero, the startDate becomes the cliff (transfer cliffAmount and start stream).
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param startDate Timestamp when the vesting should start
     * @param cliffDate Timestamp of cliff execution - if 0, startDate acts as cliff
     * @param flowRate The flowRate for the stream
     * @param cliffAmount The amount to be transferred at the cliff
     * @param endDate The timestamp when the stream should stop.
     * @param claimValidityDate Date before which the claimable schedule must be claimed
     * @param ctx Superfluid context used when batching operations. (or bytes(0) if not SF batching)
     */
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
    ) external returns (bytes memory newCtx);

    /**
     * @dev See IVestingScheduler.createVestingSchedule overload for more details.
     */
    function createVestingSchedule(
        ISuperToken superToken,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate,
        bytes memory ctx
    ) external returns (bytes memory newCtx);

    /**
     * @dev See IVestingScheduler.createVestingSchedule overload for more details.
     */
    function createVestingSchedule(
        ISuperToken superToken,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate,
        uint32 claimValidityDate
    ) external;

    /**
     * @dev Creates a new vesting schedule
     * @dev The function makes it more intuitive to create a vesting schedule compared to the original function.
     * @dev The function calculates the endDate, cliffDate, cliffAmount, flowRate, etc, based on the input arguments.
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param totalAmount The total amount to be vested 
     * @param totalDuration The total duration of the vestingß
     * @param startDate Timestamp when the vesting should start
     * @param cliffPeriod The cliff period of the vesting
     * @param claimPeriod The claim availability period
     * @param ctx Superfluid context used when batching operations. (or bytes(0) if not SF batching)
     */
    function createVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod,
        bytes memory ctx
    ) external returns (bytes memory newCtx);

    /**
     * @dev See IVestingScheduler.createVestingScheduleFromAmountAndDuration overload for more details.
     */
    function createVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod
    ) external;

    /**
     * @dev Returns all relevant information related to a new vesting schedule creation 
     * @dev based on the amounts and durations.
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param totalAmount The total amount to be vested 
     * @param totalDuration The total duration of the vestingß
     * @param startDate Timestamp when the vesting should start
     * @param cliffPeriod The cliff period of the vesting
     * @param claimPeriod The claim availability period
     */
    function mapCreateVestingScheduleParams(
        ISuperToken superToken,
        address sender,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod
    ) external returns (ScheduleCreationParams memory params);

    /**
     * @dev Creates a new vesting schedule
     * @dev The function calculates the endDate, cliffDate, cliffAmount, flowRate, etc, based on the input arguments.
     * @dev The function creates the vesting schedule with start date set to current timestamp,
     * @dev and executes the start (i.e. creation of the flow) immediately.
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param totalAmount The total amount to be vested 
     * @param totalDuration The total duration of the vesting
     * @param ctx Superfluid context used when batching operations. (or bytes(0) if not SF batching)
     */
    function createAndExecuteVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        bytes memory ctx
    ) external returns (bytes memory newCtx);

    /** 
     * @dev See IVestingScheduler.createAndExecuteVestingScheduleFromAmountAndDuration.
     */
    function createAndExecuteVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration
    ) external;
    
    /**
     * @dev Event emitted on update of a vesting schedule
     * @param superToken The superToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     * @param oldEndDate Old timestamp when the stream should stop
     * @param endDate New timestamp when the stream should stop
     */
    event VestingScheduleUpdated(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 oldEndDate,
        uint32 endDate,
        uint96 remainderAmount
    );

    /**
     * @dev Updates the end date for a vesting schedule which already reached the cliff
     * @notice When updating, there's no restriction to the end date other than not being in the past
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param endDate The timestamp when the stream should stop
     * @param ctx Superfluid context used when batching operations. (or bytes(0) if not SF batching)
     */
    function updateVestingSchedule(ISuperToken superToken, address receiver, uint32 endDate, bytes memory ctx)
        external
        returns (bytes memory newCtx);

    /**
     * @dev Event emitted on deletion of a vesting schedule
     * @param superToken The superToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     */
    event VestingScheduleDeleted(ISuperToken indexed superToken, address indexed sender, address indexed receiver);

    /**
     * @dev Event emitted on end of a vesting that failed because there was no running stream
     * @param superToken The superToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     * @param endDate The timestamp when the stream should stop
     */
    event VestingEndFailed(
        ISuperToken indexed superToken, address indexed sender, address indexed receiver, uint32 endDate
    );

    /**
     * @dev Deletes a vesting schedule
     * @param superToken The superToken to be vested
     * @param receiver Vesting receiver
     * @param ctx Superfluid context used when batching operations. (or bytes(0) if not SF batching)
     */
    function deleteVestingSchedule(ISuperToken superToken, address receiver, bytes memory ctx)
        external
        returns (bytes memory newCtx);

    /**
     * @dev Emitted when the cliff of a scheduled vesting is executed
     * @param superToken The superToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     * @param cliffAndFlowDate The timestamp when the stream should start
     * @param flowRate The flowRate for the stream
     * @param cliffAmount The amount you would like to transfer at the startDate when you start streaming
     * @param flowDelayCompensation Adjusted amount transferred to receiver. (elapse time from config and tx timestamp)
     */
    event VestingCliffAndFlowExecuted(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 cliffAndFlowDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint256 flowDelayCompensation
    );

    /**
     * @dev Emitted when a claimable vesting schedule is claimed
     * @param superToken The superToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     * @param claimer Account that claimed the vesting (can only be sender or receiver)
     */
    event VestingClaimed(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        address claimer
    );

    /**
     * @dev Executes a cliff (transfer and stream start)
     * @notice Intended to be invoked by a backend service
     * @param superToken SuperToken to be streamed
     * @param sender Account who will be send the stream
     * @param receiver Account who will be receiving the stream
     */
    function executeCliffAndFlow(ISuperToken superToken, address sender, address receiver)
        external
        returns (bool success);

    /**
     * @dev Emitted when the end of a scheduled vesting is executed
     * @param superToken The superToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     * @param endDate The timestamp when the stream should stop
     * @param earlyEndCompensation adjusted close amount transferred to receiver.
     * @param didCompensationFail adjusted close amount transfer fail.
     */
    event VestingEndExecuted(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 endDate,
        uint256 earlyEndCompensation,
        bool didCompensationFail
    );

    /**
     * @dev Executes the end of a vesting (stop stream)
     * @notice Intended to be invoked by a backend service
     * @param superToken The superToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     */
    function executeEndVesting(ISuperToken superToken, address sender, address receiver)
        external
        returns (bool success);

    /**
     * @dev Gets data currently stored for a vesting schedule
     * @param superToken The superToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     */
    function getVestingSchedule(address superToken, address sender, address receiver)
        external
        view
        returns (VestingSchedule memory);

    /**
     * @dev Estimates the maximum possible ERC-20 token allowance needed for the vesting schedule 
     * @dev to work properly under all circumstances.
     * @param vestingSchedule A vesting schedule (doesn't have to exist)
     */
    function getMaximumNeededTokenAllowance(
        VestingSchedule memory vestingSchedule
    ) external returns (uint256);
}
