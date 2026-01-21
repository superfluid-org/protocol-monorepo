// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { YieldBackendIntegrationTestBase } from "./YieldBackendIntegrationTestBase.sol";
import { ERC4626YieldBackend } from "../../../../contracts/superfluid/ERC4626YieldBackend.sol";
import { IYieldBackend } from "../../../../contracts/interfaces/superfluid/IYieldBackend.sol";
import { IERC4626 } from "@openzeppelin-v5/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title ERC4626YieldBackendIntegrationTestBase
 * @notice Abstract base for ERC4626YieldBackend integration tests. Concrete contracts provide
 *         chain-specific config (RPC, vault, superToken, underlyingToken) via the virtual getters.
 * @author Superfluid
 */
abstract contract ERC4626YieldBackendIntegrationTestBase is YieldBackendIntegrationTestBase {
    function _vault() internal pure virtual returns (address);

    function _createBackend() internal override returns (IYieldBackend) {
        return IYieldBackend(address(new ERC4626YieldBackend(IERC4626(_vault()), SURPLUS_RECEIVER)));
    }

    function _getYieldAssets(address superToken_) internal view override returns (uint256) {
        return IERC4626(_vault()).convertToAssets(IERC4626(_vault()).balanceOf(superToken_));
    }

    function _getYieldPositionForSurplusAssert(address superToken_) internal view override returns (uint256) {
        return IERC4626(_vault()).balanceOf(superToken_);
    }

    function _assertYieldPositionZeroOrDustAfterDisable() internal view override {
        IERC4626 vault = IERC4626(_vault());
        uint256 vaultSharesAfter = vault.balanceOf(address(superToken));
        uint256 vaultDecimals = vault.decimals();
        uint256 underlyingDecimals = IERC20Metadata(vault.asset()).decimals();
        uint256 decimalsGap = vaultDecimals >= underlyingDecimals
            ? vaultDecimals - underlyingDecimals
            : underlyingDecimals - vaultDecimals;
        uint256 dustTolerance = 10 ** decimalsGap;
        assertLe(
            vaultSharesAfter,
            dustTolerance,
            "vault shares should be zero or dust from decimals conversion"
        );
    }
}

/// @notice ERC4626 yield backend integration tests with sUSDC vault on Base
contract ERC4626YieldBackendIntegrationTestBaseSUSDC is ERC4626YieldBackendIntegrationTestBase {
    function _chainId() internal pure override returns (uint256) { return 8453; }
    function _rpcUrl() internal pure override returns (string memory) { return "https://mainnet.base.org"; }
    function _vault() internal pure override returns (address) { return 0x3128a0F7f0ea68E7B7c9B00AFa7E41045828e858; }
    function _superToken() internal pure override returns (address) { return 0xD04383398dD2426297da660F9CCA3d439AF9ce1b; }
    function _underlyingToken() internal pure override returns (address) { return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; }
}

/// @notice ERC4626 yield backend integration tests with sUSDC on Ethereum
contract ERC4626YieldBackendIntegrationTestEthereumSUSDC is ERC4626YieldBackendIntegrationTestBase {
    function _chainId() internal pure override returns (uint256) { return 1; }
    function _rpcUrl() internal pure override returns (string memory) { return "https://eth.drpc.org"; }
    function _vault() internal pure override returns (address) { return 0xBc65ad17c5C0a2A4D159fa5a503f4992c7B545FE; }
    function _superToken() internal pure override returns (address) { return 0x1BA8603DA702602A8657980e825A6DAa03Dee93a; }
    function _underlyingToken() internal pure override returns (address) { return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; }
}
