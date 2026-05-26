// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { DeployUtils } from "./utils/DeployUtils.sol";
import { Resolver } from "../contracts/utils/Resolver.sol";

/**
 * @notice Set a resolver registry key (multisig / Safe / direct admin via DeployUtils).
 *
 * Env: RESOLVER_ADDRESS, RESOLVER_KEY, RESOLVER_VALUE
 *      ALLOW_UPDATE=1 to overwrite an existing non-zero entry
 */
contract ResolverSetKey is Script {
    function run() external {
        address resolverAddr = vm.envAddress("RESOLVER_ADDRESS");
        string memory key = vm.envString("RESOLVER_KEY");
        address value = vm.envAddress("RESOLVER_VALUE");

        Resolver resolver = Resolver(resolverAddr);
        address prev = resolver.get(key);

        console.log("======== Set resolver key ========");
        console.log("Resolver: %s", resolverAddr);
        console.log("Key: %s", key);
        console.log("Value: %s", value);

        if (prev != address(0)) {
            console.log("Previous value: %s", prev);
            require(bytes(vm.envOr("ALLOW_UPDATE", string(""))).length > 0, "ALLOW_UPDATE not set");
        }

        vm.startBroadcast();
        DeployUtils.setResolverValue(resolver, key, value);
        vm.stopBroadcast();

        console.log("======== Resolver action complete ========");
    }
}
