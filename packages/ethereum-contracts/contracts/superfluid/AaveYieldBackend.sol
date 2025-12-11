// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IYieldBackend } from "../interfaces/superfluid/IYieldBackend.sol";
import { IPool } from "aave-v3/interfaces/IPool.sol";
import { IERC20 } from "../interfaces/superfluid/ISuperfluid.sol";


/**
 * Aave supports a simple deposit/withdraw workflow nicely matching the IYieldBackend interface.
 * Deposits are represented by transferrable aTokens.
 *
 * This contract is conceptually a hot-pluggable library.
 * All methods are supposed to be invoked as delegatecall.
 */
contract AaveYieldBackend is IYieldBackend {
    IERC20 public immutable ASSET_TOKEN;
    IPool public immutable AAVE_POOL;
    IERC20 public immutable A_TOKEN;

    // THIS CONTRACT CANNOT HAVE STATE VARIABLES!
    // IF STATE IS NEEDED, USE NAMESPACED STORAGE LAYOUT (EIP-7201)

    /**
     * @param assetToken the asset (Aave terminology) supplied to Aave for yield. Typically, this will be 
     * the underlyingToken of a SuperToken.
     * @param aavePool the Aave pool
     */
    constructor(IERC20 assetToken, IPool aavePool) {
        // TODO: any checks to be done?
        ASSET_TOKEN = assetToken;
        AAVE_POOL = IPool(aavePool);
        A_TOKEN = IERC20(aavePool.getReserveAToken(address(assetToken)));
    }

    function init() external {
        // approve Aave pool to fetch asset
        ASSET_TOKEN.approve(address(AAVE_POOL), type(uint256).max);
    }

    function deinit() external {
        // Revoke approval
        ASSET_TOKEN.approve(address(AAVE_POOL), 0);
    }

    function deposit(uint256 amount) external {
        // TODO: can this constraint break anything?
        require(amount > 0, "amount must be greater than 0");
        // Deposit asset and get back aTokens
        AAVE_POOL.supply(address(ASSET_TOKEN), amount, address(this), 0);
    }

    function depositMax() external {
        uint256 amount = ASSET_TOKEN.balanceOf(address(this));
        if (amount > 0) {
            AAVE_POOL.supply(address(ASSET_TOKEN), amount, address(this), 0);
        }
    }

    function withdraw(uint256 amount) external {
        // withdraw amount asset by redeeming the corresponding aTokens amount
        AAVE_POOL.withdraw(address(ASSET_TOKEN), amount, address(this));
    }

    function withdrawMax() external {
        // We can delegate the max calculation to the Aave pool by setting amount to type(uint256).max
        AAVE_POOL.withdraw(address(ASSET_TOKEN), type(uint256).max, address(this));
    }
}
