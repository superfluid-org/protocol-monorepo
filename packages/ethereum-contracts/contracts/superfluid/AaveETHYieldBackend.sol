// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AaveYieldBackend } from "./AaveYieldBackend.sol";
import { IERC20 } from "../interfaces/superfluid/ISuperfluid.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";
import { IWETH } from "aave-v3/src/contracts/helpers/interfaces/IWETH.sol";

/**
 * @title a SuperToken yield backend for the Aave protocol for ETH/native tokens.
 * This contract extends AaveYieldBackend to support native ETH by wrapping it to WETH.
 * WETH addresses are hardcoded by chain id.
 * 
 * NOTE: "WETH" is to be interpreted in a technical sense: the native token wrapper.
 * On chains with ETH not being the native token, the ERC20 token with symbol "WETH" may be an ordinary ERC20
 * while the ERC20 wrapper of the native token may have a different symbol. We mean the latter!
 *
 * NOTE: Surplus WETH will NOT be unwrapped by `withdrawSurplus` (which is inherited from the Base contract)
 * before transferring it to the configured SURPLUS_RECEIVER.
 */
contract AaveETHYieldBackend is AaveYieldBackend {
    AaveETHYieldBackend internal immutable _SELF;

    // THIS CONTRACT CANNOT HAVE STATE VARIABLES!
    // IF STATE IS NEEDED, USE NAMESPACED STORAGE LAYOUT (EIP-7201)

    /**
     * @param aavePool the Aave pool
     * @param surplusReceiver the address to receive the surplus asset when withdrawing the surplus
     */
    constructor(IPool aavePool, address surplusReceiver) 
        AaveYieldBackend(IERC20(getWETHAddress()), aavePool, surplusReceiver)
    {
        _SELF = this;
    }

    /// get the canonical native token ERC20 wrapper contract address based on the chain id and Aave deployment.
    /// Implemented for chains with official deployments of Aave and Superfluid.
    function getWETHAddress() internal view returns (address) {
        if (block.chainid == 1) { // Ethereum
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        if (block.chainid == 10 || block.chainid == 8453) {
            return 0x4200000000000000000000000000000000000006;
        }
        if (block.chainid == 137) { // Polygon
            return 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
        }
        if (block.chainid == 42161) { // Arbitrum
            return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        }
        if (block.chainid == 100) { // Gnosis Chain
            // Note this token has the symbol WXDAI, wrapping the native token xDAI
            return 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
        }
        if (block.chainid == 43114) { // Avalanche C-Chain
            // Note this token has the symbol WAVAX, wrapping the native token AVAX
            return 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
        }
        if (block.chainid == 56) { // BNB
            // Note this token has the symbol WBNB, wrapping the native token BNB
            return 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        }
        if (block.chainid == 534352) { // Scroll
            return 0x5300000000000000000000000000000000000004;
        }
        // Celo: WCELO does not implement IWETH

        revert("chain not supported");
    }

    function deposit(uint256 amount) public override {
        // wrap ETH to WETH
        IWETH(address(ASSET_TOKEN)).deposit{ value: amount }();
        // Deposit asset and get back aTokens
        super.deposit(amount);
    }

    function withdraw(uint256 amount) public override {
        // withdraw WETH by redeeming the corresponding aTokens amount.
        // the receiver is set to the address of the implementation contract in order to not trigger the
        // fallback function of the SuperToken contract.
        uint256 withdrawnAmount = AAVE_POOL.withdraw(address(ASSET_TOKEN), amount, address(_SELF));
        // unwrap to ETH and transfer it to the calling SuperToken contract
        _SELF.unwrapWETHAndForwardETH(withdrawnAmount, address(this));
    }

    // ============ functions operating on this contract itself (NOT in delegatecall context) ============

    // allow unwrapping from WETH to this contract
    receive() external payable { }

    // To be invoked by `withdraw` which is executed via delegatecall in a SuperToken context.
    // WETH deposited or withdrawn by the SuperToken never stays in this contract beyond the lifetime of the tx.
    // Thus it is not necessary to restrict msg.sender.
    // We accept that an alien caller may withdraw WETH deposited to this contract (for whatever reason).
    function unwrapWETHAndForwardETH(uint256 amount, address recipient) external {
        IWETH(address(ASSET_TOKEN)).withdraw(amount);
        (bool success,) = recipient.call{ value: amount }("");
        require(success, "call failed");
    }
}

