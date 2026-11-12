// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {SimpleACL} from "../contracts/utils/SimpleACL.sol";

contract ACLAction is Script {
    function grant(SimpleACL acl, bytes32 role, address grantee) external {
        if (acl.hasRole(role, grantee)) return;
        vm.startBroadcast(vm.envAddress("DEPLOYER"));
        acl.grantRole(role, grantee);
        vm.stopBroadcast();
    }

    function transferAdmin(SimpleACL acl, address recipient) external {
        address sender = vm.envAddress("DEPLOYER");
        require(recipient != address(0), "Zero ACL successor");
        if (recipient == sender) return;
        bytes32 appAdmin = keccak256("ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN");
        bool moveApp = acl.hasRole(appAdmin, sender);
        vm.startBroadcast(sender);
        acl.grantRole(bytes32(0), recipient);
        if (moveApp) {
            acl.grantRole(appAdmin, recipient);
            acl.renounceRole(appAdmin, sender);
        }
        acl.renounceRole(bytes32(0), sender);
        vm.stopBroadcast();
    }
}
