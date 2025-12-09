// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IYieldBackend } from "../interfaces/superfluid/IYieldBackend.sol";
import { DataTypes } from "aave-v3/protocol/libraries/types/DataTypes.sol";
import { IPool } from "aave-v3/interfaces/IPool.sol";
import { Ownable } from "@openzeppelin-v5/contracts/access/Ownable.sol";
import { IERC20 } from "../interfaces/superfluid/ISuperfluid.sol";


struct Config {
    address assetTokenAddr;
    address aTokenAddr;
    address spender;
}

contract AaveYieldBackend is Ownable, IYieldBackend {
    IERC20 public immutable ASSET_TOKEN;
    IPool public immutable AAVE_POOL;
    IERC20 public immutable A_TOKEN;

    // TODO: what preconditions shall be checked?
    /**
     * @param assetToken the asset (Aave terminology) supplied to Aave for yield. Typically, this will be 
     * the underlyingToken of a SuperToken.
     * @param aavePool the Aave pool
     * @param owner the account allowed to deposit and withdraw via this contract. To be set to a SuperToken.
     */
    constructor(IERC20 assetToken, IPool aavePool, address owner)
        Ownable(owner)
    {
        ASSET_TOKEN = assetToken;
        AAVE_POOL = IPool(aavePool);

        // Grant unlimited approval to Aave pool
        // (safe pattern: immutable approval reduces gas & friction)
        assetToken.approve(address(aavePool), type(uint256).max);

        A_TOKEN = IERC20(aavePool.getReserveAToken(address(assetToken)));
    }

    // returns the config to be provided to delegate init() and deinit() calls
    function getConfig() external view returns (bytes memory config) {
        return abi.encode(Config({
            aTokenAddr: address(A_TOKEN), spender: address(this), assetTokenAddr: address(ASSET_TOKEN)
        }));
    }

    // to be invoked as delegatecall
    // CANNOT ACCESS STATE OF THIS CONTRACT!
    // TODO: how can we single this out such that it can't access state?
    function init(bytes memory config) external {
        Config memory c = abi.decode(config, (Config));
        IERC20(c.assetTokenAddr).approve(c.spender, type(uint256).max);
        IERC20(c.aTokenAddr).approve(c.spender, type(uint256).max);
    }

    // to be invoked as delegatecall
    // CANNOT ACCESS STATE OF THIS CONTRACT!
    function deinit(bytes memory config) external {
        Config memory c = abi.decode(config, (Config));
        IERC20(c.assetTokenAddr).approve(c.spender, 0);
        IERC20(c.aTokenAddr).approve(c.spender, 0);
    }

    /// @notice Caller deposits tokens into Aave V3
    function deposit(uint256 amount) public onlyOwner {
        require(amount > 0, "amount must be greater than 0");
        // TODO: how to handle 0 amount?

        // Pull tokens from caller
        require(ASSET_TOKEN.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        // Deposit into Aave on behalf of this contract
        AAVE_POOL.supply(address(ASSET_TOKEN), amount, owner(), 0);
    }

    function depositMax() external onlyOwner {
        // determine max amount: all of the underlying
        // TODO: take into account the max supported by the pool
        
        uint256 amount = ASSET_TOKEN.balanceOf(owner());
        deposit(amount);
    }

    /// @notice Caller withdraws tokens from Aave V3
    function withdraw(uint256 amount) public onlyOwner {
        // TODO: how to handle 0 amount?

        A_TOKEN.transferFrom(owner(), address(this), A_TOKEN.balanceOf(owner()));

        // Withdraw from Aave to this contract
        uint256 withdrawnAmount = AAVE_POOL.withdraw(address(ASSET_TOKEN), amount, address(this));

        // Transfer to caller
        require(ASSET_TOKEN.transfer(msg.sender, withdrawnAmount), "transfer failed");
    }

    function withdrawMax() external onlyOwner {
        // we can delegate the calculation to the pool by setting amount to type(uint256).max
        withdraw(type(uint256).max);
    }
}
