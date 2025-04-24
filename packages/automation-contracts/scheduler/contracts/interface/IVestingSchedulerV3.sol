// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

interface IVestingSchedulerV3 {
    //     ______           __                     ______
    //    / ____/_  _______/ /_____  ____ ___     / ____/_____________  __________
    //   / /   / / / / ___/ __/ __ \/ __ `__ \   / __/ / ___/ ___/ __ \/ ___/ ___/
    //  / /___/ /_/ (__  ) /_/ /_/ / / / / / /  / /___/ /  / /  / /_/ / /  (__  )
    //  \____/\__,_/____/\__/\____/_/ /_/ /_/  /_____/_/  /_/   \____/_/  /____/

    /// @notice Thrown when the new total amount is less than or equal to the amount already vested
    error InvalidNewTotalAmount();

    /// @notice Thrown when the time window for an operation is invalid
    error TimeWindowInvalid();

    /// @notice Thrown when an account is invalid (e.g. sender = receiver)
    error AccountInvalid();

    /// @notice Thrown when a required address parameter is the zero address
    error ZeroAddress();

    /// @notice Thrown when a flow rate is invalid (e.g. zero or negative)
    error FlowRateInvalid();

    /// @notice Thrown when cliff parameters are invalid
    error CliffInvalid();

    /// @notice Thrown when trying to create a schedule that already exists
    error ScheduleAlreadyExists();

    /// @notice Thrown when trying to operate on a non-existent schedule
    error ScheduleDoesNotExist();

    /// @notice Thrown when trying to operate on a schedule that is not flowing
    error ScheduleNotFlowing();

    /// @notice Thrown when trying to claim a schedule on behalf of another account
    error CannotClaimScheduleOnBehalf();

    /// @notice Thrown when trying to execute an already executed operation
    error AlreadyExecuted();

    /// @notice Thrown when trying to operate on an unclaimed schedule
    error ScheduleNotClaimed();

    //      ____        __        __
    //     / __ \____ _/ /_____ _/ /___  ______  ___  _____
    //    / / / / __ `/ __/ __ `/ __/ / / / __ \/ _ \/ ___/
    //   / /_/ / /_/ / /_/ /_/ / /_/ /_/ / /_/ /  __(__  )
    //  /_____/\__,_/\__/\__,_/\__/\__, / .___/\___/____/
    //                            /____/_/

    /**
     * @dev Vesting Schedule Parameters
     * @param cliffAndFlowDate Date of flow start and cliff execution (if a cliff was specified)
     * @param endDate End date of the vesting
     * @param flowRate For the stream
     * @param cliffAmount Amount to be transferred at the cliff
     * @param remainderAmount Amount transferred during early end to achieve an accurate "total vested amount"
     * @param claimValidityDate Date before which the claimable schedule must be claimed
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

    //      ______                 __
    //     / ____/   _____  ____  / /______
    //    / __/ | | / / _ \/ __ \/ __/ ___/
    //   / /___ | |/ /  __/ / / / /_(__  )
    //  /_____/ |___/\___/_/ /_/\__/____/

    /**
     * @dev Event emitted on creation of a new vesting schedule
     * @param superToken SuperToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     * @param startDate Timestamp when the vesting starts
     * @param cliffDate Timestamp of the cliff
     * @param flowRate The flowRate for the stream
     * @param endDate The timestamp when the stream should stop
     * @param cliffAmount The amount to be transferred at the cliff
     * @param claimValidityDate Date before which the claimable schedule must be claimed
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
     * @dev Event emitted on update of a vesting schedule
     * @param superToken The superToken to be vested
     * @param sender Vesting sender - the account that created and funds the vesting schedule
     * @param receiver Vesting receiver - the account that receives the vested tokens
     * @param endDate New timestamp when the stream should stop
     * @param remainderAmount The remainder amount that cannot be streamed due to flow rate precision
     * @param flowRate The new flow rate for the updated vesting schedule
     * @param totalAmount The total amount to be vested over the entire schedule
     * @param settledAmount The amount that has already been vested up to the update
     */
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
        ISuperToken indexed superToken, address indexed sender, address indexed receiver, address claimer
    );

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

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

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
     * @dev If a non-zero cliffDate is set, the startDate has no effect other than being logged in an event.
     * @dev If cliffDate is set to zero, the startDate becomes the cliff (transfer cliffAmount and start stream).
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param startDate Timestamp when the vesting should start
     * @param cliffDate Timestamp of cliff execution - if 0, startDate acts as cliff
     * @param flowRate The flowRate for the stream
     * @param cliffAmount The amount to be transferred at the cliff
     * @param endDate The timestamp when the stream should stop.
     */
    function createVestingSchedule(
        ISuperToken superToken,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate
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
     * @dev Creates a new vesting schedule
     * @dev The function makes it more intuitive to create a vesting schedule compared to the original function.
     * @dev The function calculates the endDate, cliffDate, flowRate, etc, based on the input arguments.
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param totalAmount The total amount to be vested
     * @param totalDuration The total duration of the vestingß
     * @param startDate Timestamp when the vesting should start
     * @param cliffPeriod The cliff period of the vesting
     * @param claimPeriod The claim availability period
     * @param cliffAmount The cliff amount of the vesting
     */
    function createVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod,
        uint256 cliffAmount
    ) external;

    /**
     * @dev Creates a new vesting schedule
     * @dev The function calculates the endDate, cliffDate, cliffAmount, flowRate, etc, based on the input arguments.
     * @dev The function creates the vesting schedule with start date set to current timestamp,
     * @dev and executes the start (i.e. creation of the flow) immediately.
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param totalAmount The total amount to be vested
     * @param totalDuration The total duration of the vesting
     */
    function createAndExecuteVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration
    ) external;

    /**
     * @dev Updates the end date for a vesting schedule which already reached the cliff
     * @notice When updating, there's no restriction to the end date other than not being in the past
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param endDate The timestamp when the stream should stop
     */
    function updateVestingSchedule(ISuperToken superToken, address receiver, uint32 endDate) external;

    /**
     * @dev Deletes a vesting schedule
     * @param superToken The superToken to be vested
     * @param receiver Vesting receiver
     */
    function deleteVestingSchedule(ISuperToken superToken, address receiver) external;

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
     * @dev Updates a vesting schedule flow rate based on a new total amount to be vested and a new end date
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param newTotalAmount The new total amount to be vested
     * @param newEndDate The new end date
     */
    function updateVestingScheduleFlowRateFromAmountAndEndDate(
        ISuperToken superToken,
        address receiver,
        uint256 newTotalAmount,
        uint32 newEndDate
    ) external;

    /**
     * @dev Updates a vesting schedule flow rate based on a new total amount to be vested
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param newTotalAmount The new total amount to be vested
     */
    function updateVestingScheduleFlowRateFromAmount(ISuperToken superToken, address receiver, uint256 newTotalAmount)
        external;

    /**
     * @dev Updates the end date for a vesting schedule which already reached the cliff
     * @notice When updating, there's no restriction to the end date other than not being in the past
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param endDate The timestamp when the stream should stop
     */
    function updateVestingScheduleFlowRateFromEndDate(ISuperToken superToken, address receiver, uint32 endDate)
        external;

    /**
     * @dev Updates vesting schedule to the current block and executes end (if not claimable) immediately,
     * @dev and/or executes cliff and flow (if not claimable and cliff and flow not yet executed).
     * @notice When ending, the remaining amount will be transferred to the receiver
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     */
    function endVestingScheduleNow(ISuperToken superToken, address receiver)
        external;

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

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
     * @return params The parameters for the vesting schedule creation
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
    ) external pure returns (ScheduleCreationParams memory params);

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
     * @param cliffAmount The cliff amount of the vesting
     * @return params The parameters for the vesting schedule creation
     */
    function mapCreateVestingScheduleParams(
        ISuperToken superToken,
        address sender,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod,
        uint256 cliffAmount
    ) external pure returns (ScheduleCreationParams memory params);

    /**
     * @dev Returns the total amount of vested tokens for a given vesting schedule
     * @param superToken The superToken being vested
     * @param sender The vesting sender
     * @param receiver The vesting receiver
     * @return totalVestedAmount The total amount of vested tokens
     */
    function getTotalVestedAmount(ISuperToken superToken, address sender, address receiver)
        external
        view
        returns (uint256 totalVestedAmount);

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
     * @dev Returns the maximum possible ERC-20 token allowance needed for the vesting schedule
     * @dev to work properly under all circumstances.
     * @param superToken SuperToken to be vested
     * @param sender Vesting sender
     * @param receiver Vesting receiver
     * @return maxNeededAllowance The maximum possible ERC-20 token allowance needed for the vesting schedule
     */
    function getMaximumNeededTokenAllowance(ISuperToken superToken, address sender, address receiver)
        external
        view
        returns (uint256 maxNeededAllowance);

    /**
     * @dev Returns the maximum possible ERC-20 token allowance needed for the vesting schedule
     * @dev to work properly under all circumstances.
     * @param vestingSchedule A vesting schedule (doesn't have to exist)
     * @return maxNeededAllowance The maximum possible ERC-20 token allowance needed for the vesting schedule
     */
    function getMaximumNeededTokenAllowance(VestingSchedule memory vestingSchedule)
        external
        view
        returns (uint256 maxNeededAllowance);
}
