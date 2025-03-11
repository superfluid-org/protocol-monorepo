// SPDX-License-Identifier: AGPL-3.0-only
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import {
    ISuperToken,
    IConstantFlowAgreementV1
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IERC20Mod } from "./interfaces/IERC20Mod.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IManager } from "./interfaces/IManager.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";


contract Manager is IManager, Ownable {

    IConstantFlowAgreementV1 public immutable cfaV1;

    /// @dev IManager.minLower implementation.
    uint64 public override minLower;

    /// @dev IManager.minUpper implementation.
    uint64 public override minUpper;

    /// @dev IManager.approvedStrategies implementation.
    mapping(address => bool) public override approvedStrategies;

    mapping(bytes32 => WrapSchedule) private wrapSchedule;

    constructor(
        address _cfa,
        uint64 _minLower,
        uint64 _minUpper
    ) {
        if (_cfa == address(0)) revert ZeroAddress();
        if (_minLower >= _minUpper) revert WrongLimits(_minLower, _minUpper);

        cfaV1 = IConstantFlowAgreementV1(_cfa);
        minLower = _minLower;
        minUpper = _minUpper;
    }

    /// @dev IManager.createWrapSchedule implementation.
    function createWrapSchedule(
        address superToken,
        address strategy,
        address liquidityToken,
        uint64 expiry,
        uint64 lowerLimit,
        uint64 upperLimit
    ) external override {
        if (expiry <= block.timestamp)
            revert InvalidExpirationTime(expiry, block.timestamp);

        if (lowerLimit < minLower)
            revert InsufficientLimits(lowerLimit, minLower);

        if (upperLimit < minUpper)
            revert InsufficientLimits(upperLimit, minUpper);

        bytes32 index = getWrapScheduleIndex(msg.sender, superToken, liquidityToken);

        // If index owner/user is address(0), we are creating a new wrap schedule.
        if (wrapSchedule[index].user != msg.sender) {
            if (
                superToken == address(0) ||
                strategy == address(0) ||
                liquidityToken == address(0)
            ) revert ZeroAddress();

            if (!approvedStrategies[strategy])
                revert InvalidStrategy(strategy);
            if (
                !IStrategy(strategy).isSupportedSuperToken(
                    ISuperToken(superToken)
                )
            ) revert UnsupportedSuperToken(address(superToken));

            WrapSchedule memory wrap = WrapSchedule( // create new Wrap or update wrap
                msg.sender,
                ISuperToken(superToken),
                IStrategy(strategy),
                liquidityToken,
                expiry,
                lowerLimit,
                upperLimit
            );

            wrapSchedule[index] = wrap;
        } else {
            // Else just update the limits and expiry, save gas.

            wrapSchedule[index].expiry = expiry;
            wrapSchedule[index].lowerLimit = lowerLimit;
            wrapSchedule[index].upperLimit = upperLimit;
        }

        emit WrapScheduleCreated(
            index,
            msg.sender,
            superToken,
            strategy,
            liquidityToken,
            expiry,
            lowerLimit,
            upperLimit
        );
    }

    /// @dev IManager.executeWrap implementation.
    function executeWrap(
        address user,
        address superToken,
        address liquidityToken
    ) external override {
        executeWrapByIndex(getWrapScheduleIndex(user, superToken, liquidityToken));
    }

    /// @dev IManager.deleteWrapSchedule implementation.
    function deleteWrapSchedule(
        address user,
        address superToken,
        address liquidityToken
    ) external override {
        deleteWrapScheduleByIndex(getWrapScheduleIndex(user, superToken, liquidityToken));
    }

    /// @dev IManager.addApprovedStrategy implementation.
    function addApprovedStrategy(address strategy)
        external
        override
        onlyOwner
    {
        if (strategy == address(0)) revert InvalidStrategy(strategy);
        if (!approvedStrategies[strategy]) {
            approvedStrategies[strategy] = true;
            emit AddedApprovedStrategy(strategy);
        }
    }

    /// @dev IManager.removeApprovedStrategy implementation.
    function removeApprovedStrategy(address strategy) external onlyOwner {
        if (approvedStrategies[strategy]) {
            delete approvedStrategies[strategy];
            emit RemovedApprovedStrategy(strategy);
        }
    }

    /// @dev IManager.setLimits implementation.
    function setLimits(uint64 lowerLimit, uint64 upperLimit)
        external
        onlyOwner
    {
        if (lowerLimit >= upperLimit)
            revert WrongLimits(lowerLimit, upperLimit);

        minLower = lowerLimit;
        minUpper = upperLimit;

        emit LimitsChanged(lowerLimit, upperLimit);
    }

    /// @dev IManager.getWrapSchedule implementation.
    function getWrapSchedule(
        address user,
        address superToken,
        address liquidityToken
    ) external view returns (WrapSchedule memory) {
        return
            getWrapScheduleByIndex(getWrapScheduleIndex(user, superToken, liquidityToken));
    }

    /// @dev IManager.checkWrap implementation.
    function checkWrap(
        address user,
        address superToken,
        address liquidityToken
    ) external view override returns (uint256) {
        return
            checkWrapByIndex(
                getWrapScheduleIndex(user, superToken, liquidityToken)
            );
    }

    /// @dev IManager.executeWrapByIndex implementation.
    function executeWrapByIndex(bytes32 index) public {
        uint256 wrapAmount = checkWrapByIndex(index);

        if (wrapAmount == 0) revert WrapNotRequired(index);

        WrapSchedule storage wrap = wrapSchedule[index];

        ISuperToken superToken = wrap.superToken;
        IStrategy strategy = wrap.strategy;

        if (!strategy.isSupportedSuperToken(superToken))
            revert UnsupportedSuperToken(address(superToken));

        strategy.wrap(wrap.user, superToken, wrapAmount);
        emit WrapExecuted(index, wrapAmount);
    }

    /// @dev IManager.deleteWrapSchedule implementation.
    function deleteWrapScheduleByIndex(bytes32 index) public {
        WrapSchedule storage wrap = wrapSchedule[index];

        address user = wrap.user;

        if (user == address(0)) revert ZeroAddress();

        if (user != msg.sender && wrap.expiry >= block.timestamp)
            revert UnauthorizedCaller(msg.sender, user);

        emit WrapScheduleDeleted(
            index,
            wrap.user,
            address(wrap.superToken),
            address(wrap.strategy),
            wrap.liquidityToken
        );

        delete wrapSchedule[index];
    }

    /// @dev IManager.getWrapScheduleByIndex implementation.
    function getWrapScheduleByIndex(bytes32 index)
        public
        view
        returns (WrapSchedule memory)
    {
        return wrapSchedule[index];
    }

    /// @dev IManager.checkWrapByIndex implementation.
    function checkWrapByIndex(bytes32 index)
        public
        view
        returns (uint256 amount)
    {
        WrapSchedule storage wrap = wrapSchedule[index];

        if (
            wrap.user == address(0) || // Task exists and has a valid user
            wrap.expiry <= block.timestamp || // Task exists and current time is before task end time
            IERC20Mod(wrap.liquidityToken).allowance(
                wrap.user,
                address(wrap.strategy) // contract is allowed to spend
            ) ==
            0 ||
            IERC20Mod(wrap.liquidityToken).balanceOf(wrap.user) == 0 || // check user balance
            !IStrategy(wrap.strategy).isSupportedSuperToken(wrap.superToken) // Supertoken isn't supported anymore.
        ) return 0;

        int96 flowRate = cfaV1.getNetFlow(wrap.superToken, wrap.user);

        if (flowRate < 0) {
            uint256 superBalance = wrap.superToken.balanceOf(wrap.user);
            uint256 positiveFlowRate = uint256(uint96(-1 * flowRate));

            // Selecting max between user defined limits and global limits.
            uint64 maxLowerLimit = (wrap.lowerLimit < minLower)? minLower: wrap.lowerLimit;
            uint64 maxUpperLimit = (wrap.upperLimit < minUpper)? minUpper: wrap.upperLimit;

            if (superBalance <= (positiveFlowRate * maxLowerLimit)) {
                return positiveFlowRate * maxUpperLimit;
            }
        }

        return 0;
    }

    /// @dev IManager.getWrapScheduleIndex implementation.
    function getWrapScheduleIndex(
        address user,
        address superToken,
        address liquidityToken
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(user, superToken, liquidityToken));
    }
}
