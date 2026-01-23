// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IYieldBackend } from "../interfaces/superfluid/IYieldBackend.sol";
import { IERC20, ISuperToken } from "../interfaces/superfluid/ISuperfluid.sol";
import { IERC4626 } from "@openzeppelin-v5/contracts/interfaces/IERC4626.sol";


/**
 * @title A SuperToken yield backend for ERC4626 compliant vaults.
 *
 * In order to learn about the limitations and constraints of this implementation, see
 * https://github.com/superfluid-org/protocol-monorepo/wiki/Yield-Backend
 */
contract ERC4626YieldBackend is IYieldBackend {
    IERC20 public immutable ASSET_TOKEN;
    IERC4626 public immutable VAULT;
    address public immutable SURPLUS_RECEIVER;

    constructor(IERC4626 vault, address surplusReceiver) {
        VAULT = vault;
        ASSET_TOKEN = IERC20(vault.asset());
        SURPLUS_RECEIVER = surplusReceiver;
    }

    function enable() external {
        ASSET_TOKEN.approve(address(VAULT), type(uint256).max);
    }

    function disable() external {
        ASSET_TOKEN.approve(address(VAULT), 0);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "amount must be greater than 0");
        VAULT.deposit(amount, address(this));
    }

    function withdraw(uint256 amount) external {
        VAULT.withdraw(amount, address(this), address(this));
    }

    function withdrawMax() external {
        uint256 balance = VAULT.maxWithdraw(address(this));
        if (balance > 0) {
            VAULT.withdraw(balance, address(this), address(this));
        }
    }

    function withdrawSurplus(uint256 totalSupply) external {
        (uint256 normalizedTotalSupply, ) = ISuperToken(address(this))
            .toUnderlyingAmount(totalSupply);

        uint256 vaultAssets = VAULT.convertToAssets(
            VAULT.balanceOf(address(this))
        );

        uint256 surplusAmount = vaultAssets + ASSET_TOKEN.balanceOf(address(this)) - normalizedTotalSupply;
        VAULT.withdraw(surplusAmount, SURPLUS_RECEIVER, address(this));
    }
}
