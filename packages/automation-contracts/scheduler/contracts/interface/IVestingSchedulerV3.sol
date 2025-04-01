// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IVestingSchedulerV2} from "./IVestingSchedulerV2.sol";

interface IVestingSchedulerV3 is IVestingSchedulerV2 {
    // FIXME Add comments
    error InvalidNewTotalAmount();

    /**
     * @dev Event emitted when a vesting schedule's total amount is updated
     * @param superToken The superToken being vested
     * @param sender The vesting sender
     * @param receiver The vesting receiver
     * @param previousFlowRate The flow rate before the update
     * @param newFlowRate The flow rate after the update
     * @param previousTotalAmount The total amount to be vested before the update
     * @param newTotalAmount The total amount to be vested after the update
     * @param remainderAmount The remainder amount that cannot be streamed
     */
    event VestingScheduleTotalAmountUpdated(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        int96 previousFlowRate,
        int96 newFlowRate,
        uint256 previousTotalAmount,
        uint256 newTotalAmount,
        uint96 remainderAmount
    );

    /**
     * @dev Event emitted when a vesting schedule's end date is updated
     * @param superToken The superToken being vested
     * @param sender The vesting sender
     * @param receiver The vesting receiver
     * @param oldEndDate The end date before the update
     * @param endDate The end date after the update
     * @param previousFlowRate The flow rate before the update
     * @param newFlowRate The flow rate after the update
     * @param remainderAmount The remainder amount that cannot be streamed
     */
    event VestingScheduleEndDateUpdated(
        ISuperToken indexed superToken,
        address indexed sender,
        address indexed receiver,
        uint32 oldEndDate,
        uint32 endDate,
        int96 previousFlowRate,
        int96 newFlowRate,
        uint96 remainderAmount
    );

    /**
     * @dev See IVestingSchedulerV2.createVestingScheduleFromAmountAndDuration overload for more details.
     */
    function createVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod,
        uint256 cliffAmount,
        bytes memory ctx
    ) external returns (bytes memory newCtx);

    /**
     * @dev See IVestingSchedulerV2.createVestingScheduleFromAmountAndDuration overload for more details.
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
     * @dev Updates a vesting schedule flow rate based on a new total amount to be vested
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param newTotalAmount The new total amount to be vested
     * @param ctx Superfluid context used when batching operations. (or bytes(0) if not SF batching)
     */
    function updateVestingScheduleFlowRateFromAmount(
        ISuperToken superToken,
        address receiver,
        uint256 newTotalAmount,
        bytes memory ctx
    ) external returns (bytes memory newCtx);

    /**
     * @dev Updates the end date for a vesting schedule which already reached the cliff
     * @notice When updating, there's no restriction to the end date other than not being in the past
     * @param superToken SuperToken to be vested
     * @param receiver Vesting receiver
     * @param endDate The timestamp when the stream should stop
     * @param ctx Superfluid context used when batching operations. (or bytes(0) if not SF batching)
     */
    function updateVestingScheduleFlowRateFromEndDate(
        ISuperToken superToken,
        address receiver,
        uint32 endDate,
        bytes memory ctx
    ) external returns (bytes memory newCtx);

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
}
