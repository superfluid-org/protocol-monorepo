// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { SparkYieldBackend, ISparkVault } from "../../../../contracts/superfluid/SparkYieldBackend.sol";
import { IYieldBackend } from "../../../../contracts/interfaces/superfluid/IYieldBackend.sol";
import { ERC4626YieldBackendIntegrationTestEthereumSUSDC } from "./ERC4626YieldBackendIntegration.t.sol";

contract SparkYieldBackendUnitTestEthereumSUSDC is ERC4626YieldBackendIntegrationTestEthereumSUSDC {
    uint16 internal constant REFERRAL_ID = 42;

    event Referral(uint16 indexed referral, address indexed owner, uint256 assets, uint256 shares);

    function _createBackend() internal override returns (IYieldBackend) {
        return IYieldBackend(
            address(new SparkYieldBackend(ISparkVault(_vault()), SURPLUS_RECEIVER, REFERRAL_ID))
        );
    }

    function testDepositEmitsReferral() public {
        vm.expectEmit(true, true, false, false, _vault());
        emit Referral(REFERRAL_ID, address(superToken), 0, 0);
        _enableYieldBackend();
    }
}
