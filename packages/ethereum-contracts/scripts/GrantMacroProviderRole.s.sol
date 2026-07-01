// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IAccessControl } from "@openzeppelin-v5/contracts/access/IAccessControl.sol";
import { ISuperfluid } from "../contracts/interfaces/superfluid/ISuperfluid.sol";

/**
 * @title GrantMacroProviderRole
 * @dev Grants the macro provider role in SimpleACL for a given provider string (e.g. "macros.superfluid.eth").
 *      The role is keccak256(provider). Caller must have DEFAULT_ADMIN_ROLE on SimpleACL.
 *
 * Usage (with wrapper):
 *   tasks/grant-macro-provider-role.sh <network> <grantee-address> [provider]
 *
 * Or directly:
 *   forge script scripts/GrantMacroProviderRole.s.sol --sig "run(address,address,string)" \\
 *     <host> <grantee> [provider] --rpc-url <url> --broadcast
 */
contract GrantMacroProviderRole is Script {
    string public constant DEFAULT_PROVIDER = "macros.superfluid.eth";

    function run(address host, address grantee, string memory provider) external {
        if (bytes(provider).length == 0) {
            provider = DEFAULT_PROVIDER;
        }

        IAccessControl simpleACL = ISuperfluid(host).getSimpleACL();
        bytes32 role = keccak256(bytes(provider));

        console.log("Host:        ", host);
        console.log("SimpleACL:   ", address(simpleACL));
        console.log("Grantee:     ", grantee);
        console.log("Provider:    ", provider);
        console.log("Role (hex):");
        console.logBytes32(role);

        if (simpleACL.hasRole(role, grantee)) {
            console.log("Grantee already has the role; no-op.");
            return;
        }

        vm.startBroadcast();
        simpleACL.grantRole(role, grantee);
        vm.stopBroadcast();

        console.log("Granted macro provider role to", grantee);
    }
}
