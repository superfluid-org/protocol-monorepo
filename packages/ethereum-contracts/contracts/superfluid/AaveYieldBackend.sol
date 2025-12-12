// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IYieldBackend } from "../interfaces/superfluid/IYieldBackend.sol";
import { IERC20, ISuperToken } from "../interfaces/superfluid/ISuperfluid.sol";
import { IPool } from "aave-v3/interfaces/IPool.sol";
import { IWETH } from "aave-v3//helpers/interfaces/IWETH.sol";


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
    bool public immutable USING_WETH;
    // TODO: make an immutable
    address constant SURPLUS_RECEIVER = 0xac808840f02c47C05507f48165d2222FF28EF4e1; // dao.superfluid.eth

    AaveYieldBackend internal immutable _SELF;

    // THIS CONTRACT CANNOT HAVE STATE VARIABLES!
    // IF STATE IS NEEDED, USE NAMESPACED STORAGE LAYOUT (EIP-7201)

    /**
     * @param assetToken the asset (Aave terminology) supplied to Aave for yield. Typically, this will be 
     * the underlyingToken of a SuperToken.
     * @param aavePool the Aave pool
     */
    constructor(IERC20 assetToken, IPool aavePool) {
        // TODO: any checks to be done?
        if (address(assetToken) == address(0)) {
            // native token, need to wrap to WETH
            USING_WETH = true;
            // This implementation currently only supports Base
            if (block.chainid == 10 || block.chainid == 8453) {
                // base, optimism
                ASSET_TOKEN = IERC20(0x4200000000000000000000000000000000000006);
            } else {
                revert("not supported");
            }
        } else {
            ASSET_TOKEN = assetToken;
        }
        AAVE_POOL = IPool(aavePool);
        A_TOKEN = IERC20(aavePool.getReserveAToken(address(ASSET_TOKEN)));

        _SELF = this;
    }

    function enable() external {
        // approve Aave pool to fetch asset
        ASSET_TOKEN.approve(address(AAVE_POOL), type(uint256).max);
    }

    function disable() external {
        // Revoke approval
        ASSET_TOKEN.approve(address(AAVE_POOL), 0);
    }

    function deposit(uint256 amount) public {
        // TODO: can this constraint break anything?
        require(amount > 0, "amount must be greater than 0");
        if (USING_WETH) {
            // wrap ETH to WETH
            IWETH(address(ASSET_TOKEN)).deposit{value: amount}();
        }
        // Deposit asset and get back aTokens
        AAVE_POOL.supply(address(ASSET_TOKEN), amount, address(this), 0);
    }

    function depositMax() external {
        uint256 amount = USING_WETH ? 
            address(this).balance :
            ASSET_TOKEN.balanceOf(address(this));
        if (amount > 0) {
            deposit(amount);
        }
    }

    function withdraw(uint256 amount) external {
        // withdraw amount asset by redeeming the corresponding aTokens amount
        if (USING_WETH) {
            AAVE_POOL.withdraw(address(ASSET_TOKEN), amount, address(_SELF));
            _SELF.unwrapAndForwardWETH(amount);
        } else {
            AAVE_POOL.withdraw(address(ASSET_TOKEN), amount, address(this));
        }
    }

    function withdrawMax() external {
        // We can delegate the max calculation to the Aave pool by setting amount to type(uint256).max
        AAVE_POOL.withdraw(address(ASSET_TOKEN), type(uint256).max, address(this));
    }

    function withdrawSurplus(uint256 totalSupply) external {
        // totalSupply is always 18 decimals while assetToken and aToken may not
        (uint256 normalizedTotalSupply,) = ISuperToken(address(this)).toUnderlyingAmount(totalSupply);
        // decrement by 1 in order to offset Aave's rounding up
        uint256 surplusAmount = A_TOKEN.balanceOf(address(this)) - normalizedTotalSupply - 1;
        AAVE_POOL.withdraw(address(ASSET_TOKEN), surplusAmount, SURPLUS_RECEIVER);
    }

    // ============ functions operating on this contract itself (NOT in delegatecall context) ============

    // allow unwrapping from WETH to this contract
    receive() external payable {}

    // To be invoked by `withdraw` executed via delegatecall in a SuperToken context.
    // Since WETH never stays in this contract, no validation of msg.sender is necessary.
    function unwrapAndForwardWETH(uint256 amount) external {
        IWETH(address(ASSET_TOKEN)).withdraw(amount);
        (bool success, ) = address(msg.sender).call{value: amount}("");
        require(success, "call failed");
    }
}
