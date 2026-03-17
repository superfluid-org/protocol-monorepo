// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ERC4626YieldBackend } from "./ERC4626YieldBackend.sol";
import { IERC4626 } from "@openzeppelin-v5/contracts/interfaces/IERC4626.sol";


/**
 * @title Minimal interface for Spark Protocol vaults with referral-tracked deposits.
 * @dev Subset of the full Spark vault interface. Adds only the deposit(assets, receiver, referral)
 *      overload and Referral event required by SparkYieldBackend.
 */
interface ISparkVault is IERC4626 {
    event Referral(uint16 indexed referral, address indexed owner, uint256 assets, uint256 shares);

    function deposit(uint256 assets, address receiver, uint256 minShares, uint16 referral)
        external
        returns (uint256 shares);
}

/**
 * @title A SuperToken yield backend for Spark Protocol vaults (SparkVault).
 * Extends ERC4626YieldBackend with a slight modification: provide a referral when calling deposit().
 */
contract SparkYieldBackend is ERC4626YieldBackend {
    uint16 public immutable REFERRAL_ID;

    /**
     * @param vault The Spark vault (ERC4626 with referral deposit)
     * @param surplusReceiver The address to receive surplus yield
     * @param referralId The referral ID passed to deposit() for tracking
     */
    constructor(ISparkVault vault, address surplusReceiver, uint16 referralId)
        ERC4626YieldBackend(IERC4626(address(vault)), surplusReceiver)
    {
        REFERRAL_ID = referralId;
    }

    function deposit(uint256 amount) external override {
        require(amount > 0, "amount must be greater than 0");
        // since the non-overloaded deposit() sets minShares to 0, we do that too
        ISparkVault(address(VAULT)).deposit(amount, address(this), 0, REFERRAL_ID);
    }
}
