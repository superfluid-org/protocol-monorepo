// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployUtils} from "./utils/DeployUtils.sol";
import {ISuperToken} from "../contracts/interfaces/superfluid/ISuperToken.sol";
import {SuperToken} from "../contracts/superfluid/SuperToken.sol";
import {IYieldBackend} from "../contracts/interfaces/superfluid/IYieldBackend.sol";

/**
 * @title SuperTokenAdminAction
 * @notice Executes SuperToken admin actions (enableYieldBackend, disableYieldBackend).
 *         Uses DeployUtils to route based on admin type (Ownable/MultiSig/Safe).
 *
 * Usage (with wrapper):
 *   new-ops-scripts/super-token-admin-action.sh <network> enableYieldBackend <superToken> <yieldBackend>
 *   new-ops-scripts/super-token-admin-action.sh <network> disableYieldBackend <superToken>
 */
contract SuperTokenAdminAction is Script {
    struct BaseConfig {
        address superToken;
        address admin;
    }

    function run() external {
        string memory actionTypeStr = vm.envOr("ACTION_TYPE", string(""));
        require(bytes(actionTypeStr).length > 0, "ACTION_TYPE must be set");

        console.log("======== Executing SuperToken Admin Action ========");
        console.log("Action Type: %s", actionTypeStr);

        BaseConfig memory baseConfig = _loadBaseConfig();
        _executeAction(actionTypeStr, baseConfig);

        console.log("======== SuperToken Admin Action Complete ========");
    }

    function _loadBaseConfig() internal view returns (BaseConfig memory config) {
        config.superToken = vm.envOr("SUPER_TOKEN_ADDRESS", address(0));
        require(config.superToken != address(0), "SUPER_TOKEN_ADDRESS must be set");

        address overrideAdmin = vm.envOr("SUPER_TOKEN_ADMIN_OVERRIDE", address(0));
        if (overrideAdmin != address(0)) {
            config.admin = overrideAdmin;
            console.log("SuperToken: %s", config.superToken);
            console.log("SuperToken Admin (override): %s", config.admin);
        } else {
            config.admin = ISuperToken(config.superToken).getAdmin();
            require(config.admin != address(0), "SuperToken has no admin");
            console.log("SuperToken: %s", config.superToken);
            console.log("SuperToken Admin: %s", config.admin);
        }
    }

    function _executeAction(string memory actionTypeStr, BaseConfig memory baseConfig) internal {
        bytes32 hash = keccak256(bytes(actionTypeStr));
        if (hash == keccak256(bytes("enableYieldBackend"))) {
            _executeEnableYieldBackend(baseConfig);
        } else if (hash == keccak256(bytes("disableYieldBackend"))) {
            _executeDisableYieldBackend(baseConfig);
        } else {
            revert("Unknown action type");
        }
    }

    function _executeEnableYieldBackend(BaseConfig memory baseConfig) internal {
        address yieldBackend = vm.envOr("YIELD_BACKEND_ADDRESS", address(0));
        require(yieldBackend != address(0), "YIELD_BACKEND_ADDRESS must be set");
        console.log("YieldBackend: %s", yieldBackend);

        bytes memory actionData = abi.encodeWithSelector(
            SuperToken.enableYieldBackend.selector,
            IYieldBackend(yieldBackend)
        );

        DeployUtils.executeAdminAction(
            baseConfig.superToken,
            actionData,
            baseConfig.admin,
            "SuperTokenAdmin"
        );
    }

    function _executeDisableYieldBackend(BaseConfig memory baseConfig) internal {
        bytes memory actionData = abi.encodeWithSelector(SuperToken.disableYieldBackend.selector);

        DeployUtils.executeAdminAction(
            baseConfig.superToken,
            actionData,
            baseConfig.admin,
            "SuperTokenAdmin"
        );
    }
}
