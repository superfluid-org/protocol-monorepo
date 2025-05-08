// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import {
    ISuperToken,
    CustomSuperTokenBase
}
from "../interfaces/superfluid/CustomSuperTokenBase.sol";
import { ISETHCustom } from "../interfaces/tokens/ISETH.sol";
import { UUPSProxy } from "../upgradability/UUPSProxy.sol";

/**
 * @dev Super ETH (SETH) custom super token implementation
 * @author Superfluid
 *
 * It is also called a Native-Asset Super Token.
 */
contract SETHProxy is ISETHCustom, CustomSuperTokenBase, UUPSProxy {
    event TokenUpgraded(address indexed account, uint256 amount);
    event TokenDowngraded(address indexed account, uint256 amount);

    /// fallback function which mints Super Tokens for received ETH
    // solhint-disable-next-line no-complex-fallback
    receive() external payable override {
        ISuperToken(address(this)).selfMint(msg.sender, msg.value, new bytes(0));
        emit TokenUpgraded(msg.sender, msg.value);
    }

    function upgradeByETH() external override payable {
        ISuperToken(address(this)).selfMint(msg.sender, msg.value, new bytes(0));
        emit TokenUpgraded(msg.sender, msg.value);
    }

    function upgradeByETHTo(address to) external override payable {
        ISuperToken(address(this)).selfMint(to, msg.value, new bytes(0));
        emit TokenUpgraded(to, msg.value);
    }

    function downgradeToETH(uint wad) external override {
        ISuperToken(address(this)).selfBurn(msg.sender, wad, new bytes(0));
        payable(msg.sender).transfer(wad);
        emit TokenDowngraded(msg.sender, wad);
    }
}
