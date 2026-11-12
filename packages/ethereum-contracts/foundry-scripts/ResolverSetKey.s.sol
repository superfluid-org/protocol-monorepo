// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {Resolver} from "../contracts/utils/Resolver.sol";

contract ResolverSetKey is Script {
    function run(Resolver resolver, string calldata key, address value, bool allowUpdate) external {
        require(resolver.get(key) == address(0) || allowUpdate, "ALLOW_UPDATE=1 required");
        vm.startBroadcast(vm.envAddress("DEPLOYER"));
        DeployUtils.setResolverValue(resolver, key, value);
        vm.stopBroadcast();
    }
}
