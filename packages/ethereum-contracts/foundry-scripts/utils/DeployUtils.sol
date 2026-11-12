// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {Strings} from "@openzeppelin-v5/contracts/utils/Strings.sol";

import {Resolver} from "../../contracts/utils/Resolver.sol";
import {IMultiSigWallet} from "../../contracts/interfaces/utils/IMultiSigWallet.sol";
import {ISafe} from "../../contracts/interfaces/utils/ISafe.sol";

/**
 * @title DeployUtils
 * @notice Deployment admin routing and chain-bound Safe payloads.
 */
library DeployUtils {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /****************************************************************
     * Admin type detection and action execution utilities
     ****************************************************************/

    /**
     * @dev Admin type enum
     */
    enum AdminType {
        OWNABLE,
        MULTISIG,
        SAFE
    }

    /**
     * @dev Probes the given account to see what kind of admin it is
     * @param account The account address to probe
     * @return adminType The detected admin type
     */
    function autodetectAdminType(address account) internal view returns (AdminType adminType) {
        console.log("  Auto detecting admin type of", account);

        // Check if account is a contract
        if (account.code.length == 0) {
            console.log("  Account has no code, assuming ownable contract.");
            return AdminType.OWNABLE;
        }

        // Try to detect MultiSig wallet
        try IMultiSigWallet(account).required() returns (uint256) {
            console.log("  Detected MultiSig wallet");
            return AdminType.MULTISIG;
        } catch {
            console.log("  Not detecting MultiSig wallet fingerprint.");
        }

        // Try to detect Safe wallet
        try ISafe(account).VERSION() returns (string memory version) {
            console.log("  Detected Safe version", version);
            return AdminType.SAFE;
        } catch {
            console.log("  Not detecting Safe fingerprint.");
        }

        revert("Unknown admin contract type");
    }

    /**
     * @dev Execute admin action based on admin type (shared logic for governance and resolver)
     * @param targetContract The target contract address
     * @param actionData The encoded action data
     * @param adminAddress The admin address
     * @param actionType The type of action for logging (e.g., "Governance", "Resolver")
     */
    function executeAdminAction(
        address targetContract,
        bytes memory actionData,
        address adminAddress,
        string memory actionType
    ) internal {
        console.log("  %s address: %s", actionType, targetContract);
        console.log("  %s admin: %s", actionType, adminAddress);

        AdminType adminType = autodetectAdminType(adminAddress);

        if (adminType == AdminType.MULTISIG) {
            console.log("  %s Admin Type: MultiSig", actionType);
            IMultiSigWallet multis = IMultiSigWallet(adminAddress);
            console.log("  MultiSig address: %s", adminAddress);
            console.log("  MultiSig data:");
            console.logBytes(actionData);
            console.log("  Sending %s action to multisig...", actionType);
            multis.submitTransaction(targetContract, 0, actionData);
            console.log("*** %s action sent, but it may still need confirmation(s). ***", actionType);

        } else if (adminType == AdminType.OWNABLE) {
            console.log("  %s Admin Type: Direct Ownership (default)", actionType);
            console.log("  Executing %s action...", actionType);
            // For ownable contracts, we need to call the function directly
            (bool success, ) = targetContract.call(actionData);
            require(success, string(abi.encodePacked(actionType, " action failed")));
            console.log("*** %s action executed. ***", actionType);

        } else if (adminType == AdminType.SAFE) {
            console.log("  %s Admin Type: Safe", actionType);
            console.log("  Safe address: %s", adminAddress);
            console.log("  Target contract: %s", targetContract);
            console.log("  Safe transaction data:");
            console.logBytes(actionData);

            (, address sender,) = VM.readCallers();
            string memory safeTxJson = string(abi.encodePacked(
                "{\"safeAddress\":\"", Strings.toChecksumHexString(adminAddress), "\",",
                "\"chainId\":\"", Strings.toString(block.chainid), "\",",
                "\"deployer\":\"", Strings.toChecksumHexString(VM.envOr("DEPLOYER", sender)), "\",",
                "\"simulated\":", VM.envOr("SAFE_PAYLOAD_SIMULATED", true) ? "true" : "false", ",",
                ""));
            safeTxJson = string(abi.encodePacked(safeTxJson,
                "\"to\":\"", Strings.toChecksumHexString(targetContract), "\",",
                "\"value\":\"0\",",
                "\"data\":\"0x", _bytesToHex(actionData), "\",",
                "\"operation\":\"0\",",
                "\"actionType\":\"", actionType, "\"}"
            ));

            string memory safePayloadsFile = VM.envOr("SAFE_PAYLOADS_FILE", string(""));
            if (bytes(safePayloadsFile).length > 0) {
                VM.writeLine(safePayloadsFile, safeTxJson);
                console.log("  Safe payload written to: %s", safePayloadsFile);
            } else {
                console.log("  Safe payload JSON:");
                console.log("%s", safeTxJson);
            }
            console.log("*** Payload only: review and explicitly submit with safe-ops.ts ***");

        } else {
            revert("Unknown admin type");
        }
    }

    /**
     * @dev Execute governance action based on admin type
     * @param governance The governance contract
     * @param actionData The encoded action data
     * @param adminAddress The admin address
     */
    function executeGovernanceAction(
        address governance,
        bytes memory actionData,
        address adminAddress
    ) internal {
        executeAdminAction(governance, actionData, adminAddress, "Governance");
    }

    /**
     * @dev Execute resolver action based on admin type
     * @param resolver The resolver contract
     * @param actionData The encoded action data
     * @param adminAddress The admin address
     */
    function executeResolverAction(
        address resolver,
        bytes memory actionData,
        address adminAddress
    ) internal {
        executeAdminAction(resolver, actionData, adminAddress, "Resolver");
    }

    /**
     * @dev Get resolver admin address from AccessControlEnumerable
     * @param resolver The resolver contract
     * @return adminAddress The admin address
     */
    function getResolverAdmin(Resolver resolver) internal view returns (address adminAddress) {
        bytes32 adminRole = bytes32(0);
        address selected = VM.envOr("RESOLVER_ADMIN", address(0));
        if (selected != address(0)) {
            require(resolver.hasRole(adminRole, selected), "RESOLVER_ADMIN does not hold DEFAULT_ADMIN_ROLE");
            return selected;
        }
        uint256 adminCount = resolver.getRoleMemberCount(adminRole);
        require(adminCount == 1, "Expected one resolver admin; select authorized RESOLVER_ADMIN explicitly");
        return resolver.getRoleMember(adminRole, 0);
    }

    /**
     * @dev Set resolver key-value with multisig support
     * @param resolver The resolver contract
     * @param key The key to set
     * @param value The value to set
     */
    function setResolverValue(Resolver resolver, string memory key, address value) internal {
        console.log("Setting resolver %s -> %s ...", key, value);

        // Get resolver admin
        address resolverAdmin = getResolverAdmin(resolver);

        // Encode the set call
        bytes memory actionData = abi.encodeWithSelector(
            resolver.set.selector,
            key,
            value
        );

        // Execute resolver action
        executeResolverAction(address(resolver), actionData, resolverAdmin);
    }

    /**
     * @dev Convert bytes to hex string (without 0x prefix)
     */
    function _bytesToHex(bytes memory data) private pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory str = new bytes(data.length * 2);

        for (uint256 i = 0; i < data.length; i++) {
            str[i * 2] = hexChars[uint8(data[i] >> 4)];
            str[i * 2 + 1] = hexChars[uint8(data[i] & 0x0f)];
        }

        return string(str);
    }
}
