// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Mod is IERC20 {
    function decimals() external view returns (uint8);
}
