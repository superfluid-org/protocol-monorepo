// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { AaveYieldBackend } from "../contracts/superfluid/AaveYieldBackend.sol";
import { AaveETHYieldBackend } from "../contracts/superfluid/AaveETHYieldBackend.sol";
import { SparkYieldBackend, ISparkVault } from "../contracts/superfluid/SparkYieldBackend.sol";
import { IERC20 } from "../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";

/**
 * @title DeployYieldBackend
 * @dev Deploys AaveYieldBackend, AaveETHYieldBackend (native underlying), or SparkYieldBackend.
 *
 * Usage (with wrapper):
 *   new-ops-scripts/deploy-yield-backend.sh <network> aave <underlyingToken> <aavePool> <surplusReceiver>
 *   Use underlyingToken = address(0) for native token (e.g. ETHx) -> AaveETHYieldBackend.
 *   new-ops-scripts/deploy-yield-backend.sh <network> spark <vault> <surplusReceiver> <referralId>
 *
 * Or directly:
 *   forge script scripts/DeployYieldBackend.s.sol:DeployYieldBackend --sig "runAave(address,address,address)" \\
 *     <assetToken> <aavePool> <surplusReceiver> --rpc-url <url> --broadcast
 *   forge script scripts/DeployYieldBackend.s.sol:DeployYieldBackend --sig "runSpark(address,address,uint16)" \\
 *     <vault> <surplusReceiver> <referralId> --rpc-url <url> --broadcast
 *   forge script scripts/DeployYieldBackend.s.sol:DeployYieldBackend --sig "runAaveETH(address,address)" \\
 *     <aavePool> <surplusReceiver> --rpc-url <url> --broadcast
 */
contract DeployYieldBackend is Script {
    function runAave(
        address assetToken,
        address aavePool,
        address surplusReceiver
    )
        external
        returns (address deployed)
    {
        _requireNonZero(assetToken, "assetToken");
        _requireNonZero(aavePool, "aavePool");
        _requireNonZero(surplusReceiver, "surplusReceiver");

        console.log("Deploying AaveYieldBackend");
        console.log("  assetToken:     ", assetToken);
        console.log("  aavePool:       ", aavePool);
        console.log("  surplusReceiver:", surplusReceiver);

        vm.startBroadcast();
        AaveYieldBackend backend = new AaveYieldBackend(
            IERC20(assetToken),
            IPool(aavePool),
            surplusReceiver
        );
        vm.stopBroadcast();

        deployed = address(backend);
        console.log("Deployed AaveYieldBackend at:", deployed);
        console.log(deployed); // for scripting: capture with tail -n 1
    }

    function runAaveETH(address aavePool, address surplusReceiver)
        external
        returns (address deployed)
    {
        _requireNonZero(aavePool, "aavePool");
        _requireNonZero(surplusReceiver, "surplusReceiver");

        console.log("Deploying AaveETHYieldBackend");
        console.log("  aavePool:       ", aavePool);
        console.log("  surplusReceiver:", surplusReceiver);

        vm.startBroadcast();
        AaveETHYieldBackend backend = new AaveETHYieldBackend(IPool(aavePool), surplusReceiver);
        vm.stopBroadcast();

        deployed = address(backend);
        console.log("Deployed AaveETHYieldBackend at:", deployed);
        console.log(deployed); // for scripting: capture with tail -n 1
    }

    function runSpark(
        address vault,
        address surplusReceiver,
        uint16 referralId
    )
        external
        returns (address deployed)
    {
        _requireNonZero(vault, "vault");
        _requireNonZero(surplusReceiver, "surplusReceiver");

        console.log("Deploying SparkYieldBackend");
        console.log("  vault:          ", vault);
        console.log("  surplusReceiver:", surplusReceiver);
        console.log("  referralId:     ", referralId);

        vm.startBroadcast();
        SparkYieldBackend backend = new SparkYieldBackend(
            ISparkVault(vault),
            surplusReceiver,
            referralId
        );
        vm.stopBroadcast();

        deployed = address(backend);
        console.log("Deployed SparkYieldBackend at:", deployed);
        console.log(deployed); // for scripting: capture with tail -n 1
    }

    function _requireNonZero(address a, string memory label) internal pure {
        require(a != address(0), string.concat(label, " cannot be address(0)"));
    }
}
