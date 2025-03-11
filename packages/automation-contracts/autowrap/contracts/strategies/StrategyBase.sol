// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Mod } from "../interfaces/IERC20Mod.sol";
import { IStrategy } from "../interfaces/IStrategy.sol";

/// @title Base abstract contract for all strategies.
abstract contract StrategyBase is IStrategy, Ownable {

    using SafeERC20 for IERC20Mod;

    /// @dev IStrategy.manager implementation.
    address public override manager;

    /// @dev IStrategy.changeManager implementation.
    function changeManager(address newManager)
        external
        override
        onlyOwner
    {
        if (newManager == address(0)) revert ZeroAddress();

        emit ManagerChanged(manager, newManager);

        manager = newManager;
    }

    /// @dev IStrategy.emergencyWithdraw implementation.
    function emergencyWithdraw(address token) external override onlyOwner {
        uint256 tokenBalance = IERC20Mod(token).balanceOf(address(this));
        IERC20Mod(token).safeTransfer(msg.sender, tokenBalance);
        emit EmergencyWithdrawInitiated(msg.sender, token, tokenBalance);
    }

    function _toUnderlyingAmount(uint256 amount, uint256 underlyingDecimals)
        internal
        pure
        returns (uint256 underlyingAmount, uint256 adjustedAmount)
    {
        uint256 factor;
        if (underlyingDecimals < 18) {
            // If underlying has less decimals
            // one can upgrade less "granular" amount of tokens
            factor = 10**(18 - underlyingDecimals);
            underlyingAmount = amount / factor;
            // remove precision errors
            adjustedAmount = underlyingAmount * factor;
        } else if (underlyingDecimals > 18) {
            // If underlying has more decimals
            // one can upgrade more "granular" amount of tokens
            factor = 10**(underlyingDecimals - 18);
            underlyingAmount = amount * factor;
            adjustedAmount = amount;
        } else {
            underlyingAmount = adjustedAmount = amount;
        }
    }
}
