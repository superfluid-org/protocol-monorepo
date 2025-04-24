// SPDX-License-Identifier: AGPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

/// @dev OpenZeppelin Imports
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @dev Superfluid Protocol Imports
import {
    ISuperfluid,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {IRelayRecipient} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/utils/IRelayRecipient.sol";

/// @dev Automation Contracts Imports
import {IVestingSchedulerV3} from "./interface/IVestingSchedulerV3.sol";

using SuperTokenV1Library for ISuperToken;

/**
 * @title Superfluid Vesting Scheduler (V3)
 * @author Superfluid
 * @notice Use precise time and amount based vesting schedules using Super Tokens and real-time continuous streaming.
 * Optional features include:
 * - Vesting cliffs
 * - Receiver claiming
 * - Updating schedules (increasing/decreasing vested amount, increasing/decreasing duration)
 * @dev All token amounts are in wei; flow rates are wei per second; 
 * timestamps are Unix‐epoch seconds; durations/periods are in seconds.
 * The contract uses ERC-20 allowance and Superfluid ACL flow operator permissions
 * to automate the vesting on behalf of the sender.
 * The contract is designed to be used with an off-chain automation to execute the vesting start and end.
 * The start and end executions are permisionless.
 * Execution delays are handled with token transfer compensations, but watch out for complete expiries!
 * @custom:metadata The official addresses and subgraphs can be found from @superfluid-finance/metadata package.
 */
contract VestingSchedulerV3 is IVestingSchedulerV3, IRelayRecipient {
    //      ____        __        __
    //     / __ \____ _/ /_____ _/ /___  ______  ___  _____
    //    / / / / __ `/ __/ __ `/ __/ / / / __ \/ _ \/ ___/
    //   / /_/ / /_/ / /_/ /_/ / /_/ /_/ / /_/ /  __(__  )
    //  /_____/\__,_/\__/\__,_/\__/\__, / .___/\___/____/
    //                            /____/_/

    /**
     * @notice Aggregate struct containing all schedule-related data
     * @param superToken The SuperToken being vested
     * @param sender The vesting sender
     * @param receiver The vesting receiver
     * @param id The unique identifier for this schedule
     * @param schedule The vesting schedule details
     * @param accounting The accounting details for this schedule
     */
    struct ScheduleAggregate {
        ISuperToken superToken;
        address sender;
        address receiver;
        bytes32 id;
        VestingSchedule schedule;
        ScheduleAccounting accounting;
    }

    /**
     * @notice Struct containing accounting details for a schedule
     * @param settledAmount The amount already vested/settled
     * @param settledDate The timestamp of the last settling
     */
    struct ScheduleAccounting {
        uint256 settledAmount;
        uint256 settledDate;
    }

    //      ____                          __        __    __        _____ __        __
    //     /  _/___ ___  ____ ___  __  __/ /_____ _/ /_  / /__     / ___// /_____ _/ /____  _____
    //     / // __ `__ \/ __ `__ \/ / / / __/ __ `/ __ \/ / _ \    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   _/ // / / / / / / / / / / /_/ / /_/ /_/ / /_/ / /  __/   ___/ / /_/ /_/ / /_/  __(__  )
    //  /___/_/ /_/ /_/_/ /_/ /_/\__,_/\__/\__,_/_.___/_/\___/   /____/\__/\__,_/\__/\___/____/

    /// @notice The Superfluid host contract.
    ISuperfluid public immutable HOST;

    /// @notice The minimum vesting duration.
    uint32 public constant MIN_VESTING_DURATION = 7 days;

    /// @notice Delay after the start date after which the vesting cannot be executed.
    uint32 public constant START_DATE_VALID_AFTER = 3 days;

    /// @notice Delay before the end date before which the vesting cannot be terminated.
    uint32 public constant END_DATE_VALID_BEFORE = 1 days;

    //     _____ __        __
    //    / ___// /_____ _/ /____  _____
    //    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   ___/ / /_/ /_/ / /_/  __(__  )
    //  /____/\__/\__,_/\__/\___/____/

    /// @notice The vesting schedules.
    /// @dev id = keccak(supertoken, sender, receiver)
    mapping(bytes32 vestingId => VestingSchedule) public vestingSchedules;

    /// @notice The vesting schedule accounting.
    /// @dev id = keccak(supertoken, sender, receiver)
    mapping(bytes32 vestingId => ScheduleAccounting) public accountings;

    //     ______                 __                  __
    //    / ____/___  ____  _____/ /________  _______/ /_____  _____
    //   / /   / __ \/ __ \/ ___/ __/ ___/ / / / ___/ __/ __ \/ ___/
    //  / /___/ /_/ / / / (__  ) /_/ /  / /_/ / /__/ /_/ /_/ / /
    //  \____/\____/_/ /_/____/\__/_/   \__,_/\___/\__/\____/_/

    /**
     * @notice VestingSchedulerV3 contract constructor
     *  @param host The Superfluid host contract
     */
    constructor(ISuperfluid host) {
        HOST = host;
    }

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc IVestingSchedulerV3
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
                sender: _msgSender(),
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

    /// @inheritdoc IVestingSchedulerV3
    function createVestingSchedule(
        ISuperToken superToken,
        address receiver,
        uint32 startDate,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate
    ) external {
        _validateAndCreateVestingSchedule(
            ScheduleCreationParams({
                superToken: superToken,
                sender: _msgSender(),
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

    /// @inheritdoc IVestingSchedulerV3
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
                _msgSender(),
                receiver,
                totalAmount,
                totalDuration,
                _normalizeStartDate(startDate),
                cliffPeriod,
                claimPeriod
            )
        );
    }

    /// @inheritdoc IVestingSchedulerV3
    function createVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration,
        uint32 startDate,
        uint32 cliffPeriod,
        uint32 claimPeriod,
        uint256 cliffAmount
    ) external {
        if (cliffPeriod != 0 && cliffAmount == 0) revert CliffInvalid();

        _validateAndCreateVestingSchedule(
            mapCreateVestingScheduleParams(
                superToken,
                _msgSender(),
                receiver,
                totalAmount,
                totalDuration,
                _normalizeStartDate(startDate),
                cliffPeriod,
                claimPeriod,
                cliffAmount
            )
        );
    }

    /// @inheritdoc IVestingSchedulerV3
    function createAndExecuteVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration
    ) external {
        _validateAndCreateAndExecuteVestingScheduleFromAmountAndDuration(
            superToken, receiver, totalAmount, totalDuration
        );
    }

    struct UpdateVestingScheduleParams {
        uint32 newEndDate;
        uint256 newTotalAmount;
        int96 newFlowRate;
    }

    /// @inheritdoc IVestingSchedulerV3
    function updateVestingScheduleFlowRateFromAmountAndEndDate(
        ISuperToken superToken,
        address receiver,
        uint256 newTotalAmount,
        uint32 newEndDate
    ) external {
        address sender = _msgSender();
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);

        _updateVestingSchedule(agg, UpdateVestingScheduleParams({
            newEndDate: newEndDate,
            newTotalAmount: newTotalAmount,
            newFlowRate: 0 // Note: 0 means it will be re-calculated.
        }));
    }

    function updateVestingScheduleFlowRateFromAmount(
        ISuperToken superToken,
        address receiver,
        uint256 newTotalAmount
    ) external {
        address sender = _msgSender();
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);

        uint32 currentEndDate = agg.schedule.endDate;
        _updateVestingSchedule(agg, UpdateVestingScheduleParams({
            newEndDate: currentEndDate,
            newTotalAmount: newTotalAmount,
            newFlowRate: 0 // Note: 0 means it will be re-calculated.
        }));
    }

    /// @inheritdoc IVestingSchedulerV3
    function updateVestingScheduleFlowRateFromEndDate(ISuperToken superToken, address receiver, uint32 newEndDate)
        external
    {
        address sender = _msgSender();
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);

        uint256 currentTotalAmount = _getTotalVestedAmount(vestingSchedules[agg.id], agg.accounting);
        _updateVestingSchedule(agg, UpdateVestingScheduleParams({
            newEndDate: newEndDate,
            newTotalAmount: currentTotalAmount,
            newFlowRate: 0 // Note: 0 means it will be re-calculated.
        }));
    }

    /// @inheritdoc IVestingSchedulerV3
    function updateVestingSchedule(ISuperToken superToken, address receiver, uint32 newEndDate) external {
        address sender = _msgSender();
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);

        int96 currentFlowRate = agg.schedule.flowRate;
        _updateVestingSchedule(agg, UpdateVestingScheduleParams({
            newEndDate: newEndDate,
            newTotalAmount: 0, // Note: 0 means it will be re-calculated.
            newFlowRate: currentFlowRate
        }));
    }

    function _updateVestingSchedule(ScheduleAggregate memory agg, UpdateVestingScheduleParams memory update) private {

        if (agg.schedule.endDate == 0)
            revert ScheduleDoesNotExist();

        /*
        Schedule update is not allowed if :
            - the current end date has passed
            - the new end date is in the past
            - the cliff and flow date is in the future
        */
        if (
            agg.schedule.endDate < block.timestamp ||
            update.newEndDate < block.timestamp ||
            block.timestamp < agg.schedule.cliffAndFlowDate ||
            (agg.schedule.claimValidityDate != 0 && block.timestamp > agg.schedule.claimValidityDate)
        )
            revert TimeWindowInvalid();

        vestingSchedules[agg.id].endDate = update.newEndDate;

        // Settle the amount already vested
        uint256 settledAmount = _settle(agg);
        uint256 timeLeftToVest = update.newEndDate - block.timestamp;

        if (update.newTotalAmount == 0 && update.newFlowRate != 0) {
            update.newTotalAmount = settledAmount + (SafeCast.toUint256(update.newFlowRate) * timeLeftToVest);
        }

        // Ensure that the new total amount is larger than the amount already vested
        if (update.newTotalAmount < settledAmount)
            revert InvalidNewTotalAmount();

        uint256 amountLeftToVest = update.newTotalAmount - settledAmount;

        if (update.newFlowRate == 0) {
            update.newFlowRate = _calculateFlowRate(amountLeftToVest, timeLeftToVest);
        }

        if (update.newFlowRate != vestingSchedules[agg.id].flowRate) {
            vestingSchedules[agg.id].flowRate = update.newFlowRate;

            // If the schedule is started, update the existing flow rate to the new calculated flow rate
            if (agg.schedule.cliffAndFlowDate == 0) {
                _updateVestingFlowRate(agg.superToken, agg.sender, agg.receiver, update.newFlowRate);
            }
        }

        vestingSchedules[agg.id].remainderAmount =
            _calculateRemainderAmount(amountLeftToVest, timeLeftToVest, update.newFlowRate);

        emit VestingScheduleUpdated(
            agg.superToken,
            agg.sender,
            agg.receiver,
            update.newEndDate,
            vestingSchedules[agg.id].remainderAmount,
            update.newFlowRate,
            update.newTotalAmount,
            settledAmount
        );
    }

    /// @inheritdoc IVestingSchedulerV3
    function deleteVestingSchedule(ISuperToken superToken, address receiver) external {
        address sender = _msgSender();

        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);
        VestingSchedule memory schedule = agg.schedule;

        if (schedule.endDate != 0) {
            _deleteVestingSchedule(agg.id);
            emit VestingScheduleDeleted(superToken, sender, receiver);
        } else {
            revert ScheduleDoesNotExist();
        }
    }

    /// @inheritdoc IVestingSchedulerV3
    function executeCliffAndFlow(ISuperToken superToken, address sender, address receiver)
        public
        returns (bool success)
    {
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

    /// @inheritdoc IVestingSchedulerV3
    function executeEndVesting(ISuperToken superToken, address sender, address receiver)
        public
        returns (bool success)
    {
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);
        VestingSchedule memory schedule = agg.schedule;
        ScheduleAccounting memory accounting = agg.accounting;

        _validateBeforeEndVesting(schedule, /* disableClaimCheck: */ false);

        uint256 settledAmount = _settle(agg);
        uint256 totalVestedAmount = _getTotalVestedAmount(schedule, accounting);

        // Invalidate configuration straight away -- avoid any chance of re-execution or re-entry.
        _deleteVestingSchedule(agg.id);

        // If vesting is not running, we can't do anything, just emit failing event.
        if (_isFlowOngoing(superToken, sender, receiver)) {
            // delete first the stream and unlock deposit amount.
            superToken.deleteFlowFrom(sender, receiver);

            // Note: we consider the compensation as failed if the stream is still ongoing after the end date.
            bool didCompensationFail = schedule.endDate < block.timestamp;
            uint256 earlyEndCompensation = totalVestedAmount - settledAmount;

            if (earlyEndCompensation != 0) {
                // Note: Super Tokens revert, not return false, i.e. we expect always true here.
                assert(superToken.transferFrom(sender, receiver, earlyEndCompensation));
            }

            emit VestingEndExecuted(
                superToken, sender, receiver, schedule.endDate, earlyEndCompensation, didCompensationFail
            );
        } else {
            emit VestingEndFailed(superToken, sender, receiver, schedule.endDate);
        }

        success = true;
    }

    /// @inheritdoc IVestingSchedulerV3
    function endVestingScheduleNow(ISuperToken superToken, address receiver) external {
        address sender = _msgSender();
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);

        // Execute cliff and flow if not yet executed.
        // The flow will end up streaming 0 as it will be deleted immediately.
        if (agg.schedule.claimValidityDate == 0) {
            if (agg.schedule.cliffAndFlowDate != 0) {
                assert(executeCliffAndFlow(superToken, sender, receiver));
            }
        }

        _updateVestingSchedule(agg, UpdateVestingScheduleParams({
            newEndDate: uint32(block.timestamp),
            newTotalAmount: 0, // Note: 0 means it will be re-calculated.
            newFlowRate: agg.schedule.flowRate
        }));

        // Execute end vesting if not claimable.
        if (agg.schedule.claimValidityDate == 0) {
	        assert(executeEndVesting(superToken, sender, receiver));
        }
    }

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc IVestingSchedulerV3
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
        return mapCreateVestingScheduleParams(
            superToken, sender, receiver, totalAmount, totalDuration, startDate, cliffPeriod, claimPeriod, 0
        );
    }

    /// @inheritdoc IVestingSchedulerV3
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
    ) public pure override returns (ScheduleCreationParams memory params) {
        uint32 claimValidityDate = claimPeriod != 0 ? startDate + claimPeriod : 0;
        uint32 endDate = startDate + totalDuration;

        if (cliffAmount == 0) {
            int96 flowRate = SafeCast.toInt96(SafeCast.toInt256(totalAmount / totalDuration));
            uint96 remainderAmount = SafeCast.toUint96(totalAmount - (SafeCast.toUint256(flowRate) * totalDuration));

            if (cliffPeriod == 0) {
                // No Cliff
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
                // Linear Default Cliff (calculated based on the overall vesting flow rate)
                cliffAmount = SafeMath.mul(cliffPeriod, SafeCast.toUint256(flowRate));
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
        } else {
            // Non-Linear Cliff (user defined cliff amount)
            int96 flowRate =
                SafeCast.toInt96(SafeCast.toInt256((totalAmount - cliffAmount) / (totalDuration - cliffPeriod)));
            uint96 remainderAmount = SafeCast.toUint96(
                (totalAmount - cliffAmount) - (SafeCast.toUint256(flowRate) * (totalDuration - cliffPeriod))
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

    /// @inheritdoc IVestingSchedulerV3
    function getTotalVestedAmount(ISuperToken superToken, address sender, address receiver)
        external
        view
        returns (uint256 totalVestedAmount)
    {
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);
        VestingSchedule memory schedule = agg.schedule;
        ScheduleAccounting memory accounting = agg.accounting;

        totalVestedAmount = _getTotalVestedAmount(schedule, accounting);
    }

    /// @inheritdoc IVestingSchedulerV3
    function getVestingSchedule(address superToken, address sender, address receiver)
        external
        view
        returns (VestingSchedule memory schedule)
    {
        schedule = vestingSchedules[_getId(address(superToken), sender, receiver)];
    }

    /// @inheritdoc IVestingSchedulerV3
    function getMaximumNeededTokenAllowance(VestingSchedule memory schedule)
        external
        pure
        returns (uint256 maxNeededAllowance)
    {
        maxNeededAllowance =
            _getMaximumNeededTokenAllowance(schedule, ScheduleAccounting({settledAmount: 0, settledDate: 0}));
    }

    /// @inheritdoc IVestingSchedulerV3
    function getMaximumNeededTokenAllowance(ISuperToken superToken, address sender, address receiver)
        external
        view
        returns (uint256 maxNeededAllowance)
    {
        ScheduleAggregate memory agg = _getVestingScheduleAggregate(superToken, sender, receiver);

        maxNeededAllowance = _getMaximumNeededTokenAllowance(agg.schedule, agg.accounting);
    }

    /// @inheritdoc IRelayRecipient
    function isTrustedForwarder(address forwarder) public view override returns (bool isForwarderTrusted) {
        isForwarderTrusted = forwarder == HOST.getERC2771Forwarder();
    }

    /// @inheritdoc IRelayRecipient
    function versionRecipient() external pure override returns (string memory version) {
        version = "v1";
    }

    //      ____      __                        __   ______                 __  _
    //     /  _/___  / /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //     / // __ \/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   _/ // / / / /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /___/_/ /_/\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    function _validateAndCreateVestingSchedule(ScheduleCreationParams memory params) private {
        if (params.startDate < block.timestamp) revert TimeWindowInvalid();
        if (params.endDate <= END_DATE_VALID_BEFORE) revert TimeWindowInvalid();

        if (params.receiver == address(0) || params.receiver == params.sender) revert AccountInvalid();
        if (address(params.superToken) == address(0)) revert ZeroAddress();
        if (params.flowRate <= 0) revert FlowRateInvalid();
        if (params.cliffDate != 0 && params.startDate > params.cliffDate) revert TimeWindowInvalid();
        if (params.cliffDate == 0 && params.cliffAmount != 0) revert CliffInvalid();

        uint32 cliffAndFlowDate = params.cliffDate == 0 ? params.startDate : params.cliffDate;
        if (
            cliffAndFlowDate < block.timestamp || cliffAndFlowDate >= params.endDate
                || cliffAndFlowDate + START_DATE_VALID_AFTER >= params.endDate - END_DATE_VALID_BEFORE
                || params.endDate - cliffAndFlowDate < MIN_VESTING_DURATION
        ) revert TimeWindowInvalid();

        if (params.claimValidityDate != 0 && params.claimValidityDate < cliffAndFlowDate) {
            revert TimeWindowInvalid();
        }

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

    function _validateAndCreateAndExecuteVestingScheduleFromAmountAndDuration(
        ISuperToken superToken,
        address receiver,
        uint256 totalAmount,
        uint32 totalDuration
    ) internal {
        address sender = _msgSender();

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

    function _settle(ScheduleAggregate memory agg) private returns (uint256 settledAmount) {
        // Ensure that the cliff and flow date has passed
        assert(block.timestamp >= agg.schedule.cliffAndFlowDate);

        // Delete the cliff amount and account for it in the already vested amount
        delete vestingSchedules[agg.id].cliffAmount;

        // Update the timestamp of the last schedule update
        accountings[agg.id].settledDate = block.timestamp;

        if (block.timestamp > agg.schedule.endDate) {
            // If the schedule end date has passed, settle the total amount vested
            accountings[agg.id].settledAmount = _getTotalVestedAmount(agg.schedule, agg.accounting);
        } else {
            // If the schedule end date has not passed, accrue the amount already vested
            uint256 settledDate =
                agg.accounting.settledDate == 0 ? agg.schedule.cliffAndFlowDate : agg.accounting.settledDate;

            // Accrue the amount already vested
            accountings[agg.id].settledAmount +=
                ((block.timestamp - settledDate) * uint96(agg.schedule.flowRate)) + agg.schedule.cliffAmount;
        }
        settledAmount = accountings[agg.id].settledAmount;
    }

    function _calculateFlowRate(uint256 amountLeftToVest, uint256 timeLeftToVest)
        private
        pure
        returns (int96 flowRate)
    {
        // Calculate the new flow rate
        flowRate = SafeCast.toInt96(SafeCast.toInt256(amountLeftToVest) / SafeCast.toInt256(timeLeftToVest));
    }

    function _calculateRemainderAmount(uint256 amountLeftToVest, uint256 timeLeftToVest, int96 flowRate)
        private
        pure
        returns (uint96 remainderAmount)
    {
        // Calculate the remainder amount
        remainderAmount = SafeCast.toUint96(amountLeftToVest - (SafeCast.toUint256(flowRate) * timeLeftToVest));
    }

    function _updateVestingFlowRate(ISuperToken superToken, address sender, address receiver, int96 newFlowRate)
        private
    {
        superToken.flowFrom(sender, receiver, newFlowRate);
    }

    function _validateBeforeCliffAndFlow(VestingSchedule memory schedule, bool disableClaimCheck) private view {
        if (schedule.cliffAndFlowDate == 0) {
            revert AlreadyExecuted();
        }

        if (!disableClaimCheck && schedule.claimValidityDate != 0) {
            revert ScheduleNotClaimed();
        }

        // Ensure that that the claming date is after the cliff/flow date and before the claim validity date
        if (schedule.cliffAndFlowDate > block.timestamp || _lteDateToExecuteCliffAndFlow(schedule) < block.timestamp) {
            revert TimeWindowInvalid();
        }
    }

    function _lteDateToExecuteCliffAndFlow(VestingSchedule memory schedule) private pure returns (uint32 date) {
        if (schedule.cliffAndFlowDate == 0) {
            revert AlreadyExecuted();
        }

        if (schedule.claimValidityDate != 0) {
            date = schedule.claimValidityDate;
        } else {
            date = schedule.cliffAndFlowDate + START_DATE_VALID_AFTER;
        }
    }

    function _validateAndClaim(ScheduleAggregate memory agg) private {
        VestingSchedule memory schedule = agg.schedule;

        // Ensure that the caller is the sender or the receiver if the vesting schedule requires claiming.
        if (_msgSender() != agg.sender && _msgSender() != agg.receiver) {
            revert CannotClaimScheduleOnBehalf();
        }

        if (schedule.claimValidityDate < block.timestamp) {
            revert TimeWindowInvalid();
        }

        delete vestingSchedules[agg.id].claimValidityDate;
        emit VestingClaimed(agg.superToken, agg.sender, agg.receiver, _msgSender());
    }

    /// @dev IVestingScheduler.executeCliffAndFlow implementation.
    function _executeCliffAndFlow(ScheduleAggregate memory agg) private returns (bool success) {
        VestingSchedule memory schedule = agg.schedule;

        // Settle the amount already vested
        uint256 settledAmount = _settle(agg);

        // Invalidate configuration straight away -- avoid any chance of re-execution or re-entry.
        delete vestingSchedules[agg.id].cliffAndFlowDate;

        // Transfer the amount already vested (includes the cliff, if any)
        if (settledAmount != 0) {
            // Note: Super Tokens revert, not return false, i.e. we expect always true here.
            assert(agg.superToken.transferFrom(agg.sender, agg.receiver, settledAmount));
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
            settledAmount - schedule.cliffAmount
        );

        success = true;
    }

    function _executeVestingAsSingleTransfer(ScheduleAggregate memory agg) private returns (bool success) {
        VestingSchedule memory schedule = agg.schedule;
        ScheduleAccounting memory accounting = agg.accounting;

        _deleteVestingSchedule(agg.id);

        uint256 totalVestedAmount = _getTotalVestedAmount(schedule, accounting);

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
        success = true;
    }

    function _getTotalVestedAmount(VestingSchedule memory schedule, ScheduleAccounting memory accounting)
        private
        pure
        returns (uint256 totalVestedAmount)
    {
        uint256 actualLastUpdate = accounting.settledDate == 0 ? schedule.cliffAndFlowDate : accounting.settledDate;

        uint256 currentFlowDuration = schedule.endDate - actualLastUpdate;
        uint256 currentFlowAmount = currentFlowDuration * SafeCast.toUint256(schedule.flowRate);

        totalVestedAmount =
            accounting.settledAmount + schedule.cliffAmount + schedule.remainderAmount + currentFlowAmount;
    }

    function _validateBeforeEndVesting(VestingSchedule memory schedule, bool disableClaimCheck) private view {
        if (schedule.endDate == 0) {
            revert AlreadyExecuted();
        }

        if (!disableClaimCheck && schedule.claimValidityDate != 0) {
            revert ScheduleNotClaimed();
        }

        if (_gteDateToExecuteEndVesting(schedule) > block.timestamp) {
            revert TimeWindowInvalid();
        }
    }

    function _gteDateToExecuteEndVesting(VestingSchedule memory schedule) private pure returns (uint32 date) {
        if (schedule.endDate == 0) {
            revert AlreadyExecuted();
        }
        date = schedule.endDate - END_DATE_VALID_BEFORE;
    }

    function _getVestingScheduleAggregate(ISuperToken superToken, address sender, address receiver)
        private
        view
        returns (ScheduleAggregate memory agg)
    {
        bytes32 id = _getId(address(superToken), sender, receiver);
        agg = ScheduleAggregate({
            superToken: superToken,
            sender: sender,
            receiver: receiver,
            id: id,
            schedule: vestingSchedules[id],
            accounting: accountings[id]
        });
    }

    function _normalizeStartDate(uint32 startDate) private view returns (uint32 normalizedStartDate) {
        // Default to current block timestamp if no start date is provided.
        if (startDate == 0) {
            normalizedStartDate = uint32(block.timestamp);
        } else {
            normalizedStartDate = startDate;
        }
    }

    function _getMaximumNeededTokenAllowance(VestingSchedule memory schedule, ScheduleAccounting memory accounting)
        private
        pure
        returns (uint256 maxNeededAllowance)
    {
        uint256 maxFlowDelayCompensationAmount =
            schedule.cliffAndFlowDate == 0 ? 0 : START_DATE_VALID_AFTER * SafeCast.toUint256(schedule.flowRate);
        uint256 maxEarlyEndCompensationAmount =
            schedule.endDate == 0 ? 0 : END_DATE_VALID_BEFORE * SafeCast.toUint256(schedule.flowRate);

        if (schedule.claimValidityDate == 0) {
            maxNeededAllowance = schedule.cliffAmount + schedule.remainderAmount + maxFlowDelayCompensationAmount
                + maxEarlyEndCompensationAmount;
        } else if (schedule.claimValidityDate >= _gteDateToExecuteEndVesting(schedule)) {
            maxNeededAllowance = _getTotalVestedAmount(schedule, accounting);
        } else {
            maxNeededAllowance = schedule.cliffAmount + schedule.remainderAmount
                + (schedule.claimValidityDate - schedule.cliffAndFlowDate) * SafeCast.toUint256(schedule.flowRate)
                + maxEarlyEndCompensationAmount;
        }
    }

    function _isFlowOngoing(ISuperToken superToken, address sender, address receiver)
        private
        view
        returns (bool isFlowOngoing)
    {
        isFlowOngoing = superToken.getFlowRate(sender, receiver) != 0;
    }

    function _getId(address superToken, address sender, address receiver)
        private
        pure
        returns (bytes32 vestingScheduleId)
    {
        vestingScheduleId = keccak256(abi.encodePacked(superToken, sender, receiver));
    }

    function _deleteVestingSchedule(bytes32 id) private {
        delete vestingSchedules[id];
        delete accountings[id];
    }

    /// @dev gets the relayed sender from calldata as specified by EIP-2771, falling back to msg.sender
    function _msgSender() internal view virtual returns (address sender) {
        if (msg.data.length >= 20 && isTrustedForwarder(msg.sender)) {
            sender = address(bytes20(msg.data[msg.data.length - 20:]));
        } else {
            sender = msg.sender;
        }
    }
}
