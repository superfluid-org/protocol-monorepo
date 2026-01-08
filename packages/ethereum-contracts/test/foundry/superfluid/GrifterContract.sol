// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    ISuperToken
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import {
    IERC20
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";

import { ISETH } from "../../../contracts/interfaces/tokens/ISETH.sol";

import "forge-std/console.sol";

contract GrifterContract {
    ISuperToken public immutable superToken;
    IERC20 public immutable underlyingToken;
    IERC20 public immutable aToken;
    uint256 public immutable amount;

    constructor(ISuperToken _superToken, IERC20 _aToken, uint256 _amount) {
        superToken = _superToken;
        aToken = _aToken;
        underlyingToken = IERC20(superToken.getUnderlyingToken());
        amount = _amount;

        if (address(underlyingToken) != address(0)) {
            // Approve SuperToken to move underlying
            underlyingToken.approve(address(superToken), type(uint256).max);
        }
    }

    receive() external payable {}

    function grift(uint256 iterations) external {
        if (address(underlyingToken) == address(0)) {
            // Native ETH path
            for (uint256 i = 0; i < iterations; ++i) {
                uint256 bal0 = aToken.balanceOf(address(superToken));

                // Upgrade ETH
                ISETH(address(superToken)).upgradeByETH{ value: amount }();

                uint256 bal1 = aToken.balanceOf(address(superToken));

                // Downgrade ETH
                ISETH(address(superToken)).downgradeToETH(amount);

                uint256 bal2 = aToken.balanceOf(address(superToken));

                // Analyze Downgrade
                if (bal2 < bal1) {
                    uint256 burned = bal1 - bal2;
                    if (burned > amount) {
                        uint256 diff = burned - amount;
                        console.log("ETHx Downgrade Excess FOUND:");
                        console.log(" Req: %s", amount);
                        console.log(" Burn: %s", burned);
                        console.log(" Diff: %s", diff);
                        revert("FOUND EXCESS BURN");
                    }
                }
            }
        } else {
            // ERC20 Path
            for (uint256 i = 0; i < iterations; ++i) {
                uint256 bal0 = aToken.balanceOf(address(superToken));

                superToken.upgrade(amount);

                uint256 bal1 = aToken.balanceOf(address(superToken));

                superToken.downgrade(amount);
                uint256 bal2 = aToken.balanceOf(address(superToken));

                // Analyze Downgrade
                if (bal2 < bal1) {
                    uint256 burned = bal1 - bal2;
                    if (burned > amount) {
                        uint256 diff = burned - amount;
                        console.log("ERC20 Downgrade Excess FOUND:");
                        console.log(" Req: %s", amount);
                        console.log(" Burn: %s", burned);
                        console.log(" Diff: %s", diff);
                        revert("FOUND EXCESS BURN");
                    }
                }
            }
        }
    }
}
