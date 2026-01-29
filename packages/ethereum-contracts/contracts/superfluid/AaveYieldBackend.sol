// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IYieldBackend } from "../interfaces/superfluid/IYieldBackend.sol";
import { IERC20, ISuperToken } from "../interfaces/superfluid/ISuperfluid.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";

/**
 * @title a SuperToken yield backend for the Aave protocol.
 * Aave supports a simple deposit/withdraw workflow nicely matching the IYieldBackend interface.
 * Deposits are represented by transferrable aTokens.
 *
 * This contract is conceptually a hot-pluggable library.
 * All methods are supposed to be invoked as delegatecall.
 *
 * In order to learn about the limitations and constraints of this implementation, see
 * https://github.com/superfluid-org/protocol-monorepo/wiki/Yield-Backend
 */
contract AaveYieldBackend is IYieldBackend {
    IERC20 public immutable ASSET_TOKEN;
    IPool public immutable AAVE_POOL;
    IERC20 public immutable A_TOKEN;
    address public immutable SURPLUS_RECEIVER;

    // THIS CONTRACT CANNOT HAVE STATE VARIABLES!
    // IF STATE IS NEEDED, USE NAMESPACED STORAGE LAYOUT (EIP-7201)

    /**
     * @param assetToken the asset (Aave terminology) supplied to Aave for yield. Typically, this will be
     * the underlyingToken of a SuperToken. Must be a valid ERC20 token address.
     * @param aavePool the Aave pool
     * @param surplusReceiver the address to receive the surplus asset when withdrawing the surplus
     */
    constructor(IERC20 assetToken, IPool aavePool, address surplusReceiver) {
        require(address(assetToken) != address(0), "assetToken cannot be address(0)");
        ASSET_TOKEN = assetToken;
        AAVE_POOL = IPool(aavePool);
        SURPLUS_RECEIVER = surplusReceiver;
        A_TOKEN = IERC20(aavePool.getReserveAToken(address(ASSET_TOKEN)));
    }

    function enable() external {
        // approve Aave pool to fetch asset
        ASSET_TOKEN.approve(address(AAVE_POOL), type(uint256).max);
    }

    function disable() external {
        // Revoke approval
        ASSET_TOKEN.approve(address(AAVE_POOL), 0);
    }

    function deposit(uint256 amount) public virtual {
        // TODO: can this constraint break anything?
        require(amount > 0, "amount must be greater than 0");
        // Deposit asset and get back aTokens
        AAVE_POOL.supply(address(ASSET_TOKEN), amount, address(this), 0);
    }

    function withdraw(uint256 amount) public virtual {
        // withdraw amount asset by redeeming the corresponding aTokens amount
        AAVE_POOL.withdraw(address(ASSET_TOKEN), amount, address(this));
    }

    function withdrawMax() external virtual {
        // We can delegate the max calculation to the Aave pool by setting amount to type(uint256).max
        withdraw(type(uint256).max);
    }

    function withdrawSurplus(uint256 totalSupply) external {
        // totalSupply is always 18 decimals while assetToken and aToken may not
        (uint256 normalizedTotalSupply,) = ISuperToken(address(this)).toUnderlyingAmount(totalSupply);
        // decrement by 100 in order to give ample of margin for offsetting Aave's potential rounding error
        // If there's no surplus, this will simply revert due to arithmetic underflow.
        uint256 surplusAmount = A_TOKEN.balanceOf(address(this)) + ASSET_TOKEN.balanceOf(address(this))
            - normalizedTotalSupply - 100;
        AAVE_POOL.withdraw(address(ASSET_TOKEN), surplusAmount, SURPLUS_RECEIVER);
    }
}
