// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {ISuperToken} from "../contracts/interfaces/superfluid/ISuperToken.sol";
import {SuperToken} from "../contracts/superfluid/SuperToken.sol";
import {IYieldBackend} from "../contracts/interfaces/superfluid/IYieldBackend.sol";

contract SuperTokenAdminAction is Script {
    function _execute(ISuperToken token, address overrideAdmin, bytes memory data) internal {
        address admin = overrideAdmin == address(0) ? token.getAdmin() : overrideAdmin;
        require(admin != address(0), "SuperToken has no admin");
        vm.startBroadcast(vm.envAddress("DEPLOYER"));
        DeployUtils.executeAdminAction(address(token), data, admin, "SuperTokenAdmin");
        vm.stopBroadcast();
    }

    function enableYieldBackend(ISuperToken token, IYieldBackend backend, address overrideAdmin) external {
        _execute(token, overrideAdmin, abi.encodeCall(SuperToken.enableYieldBackend, (backend)));
    }

    function disableYieldBackend(ISuperToken token, address overrideAdmin) external {
        _execute(token, overrideAdmin, abi.encodeCall(SuperToken.disableYieldBackend, ()));
    }

    function withdrawSurplusFromYieldBackend(ISuperToken token, address overrideAdmin) external {
        _execute(token, overrideAdmin, abi.encodeCall(SuperToken.withdrawSurplusFromYieldBackend, ()));
    }
}
