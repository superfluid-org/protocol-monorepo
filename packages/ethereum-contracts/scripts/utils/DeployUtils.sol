// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin-v5/contracts/utils/Strings.sol";

import {Resolver} from "../../contracts/utils/Resolver.sol";
import {IMultiSigWallet} from "../../contracts/interfaces/utils/IMultiSigWallet.sol";
import {ISafe} from "../../contracts/interfaces/utils/ISafe.sol";

/**
 * @title DeployUtils
 * @notice Utility library for deployment scripts including admin action execution and version string handling
 */
library DeployUtils {
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
            // TODO: Implement Safe transaction execution
            console.log("  Safe admin type detected but not yet implemented");
            revert("Safe admin type not yet implemented");
            
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
        bytes32 ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000;
        uint256 adminCount = resolver.getRoleMemberCount(ADMIN_ROLE);
        
        if (adminCount > 0) {
            // Get the last admin (following the legacy pattern)
            adminAddress = resolver.getRoleMember(ADMIN_ROLE, adminCount - 1);
        } else {
            console.log("!!! resolver.getRoleMemberCount() returned 0. Using deployer as resolver admin.");
            adminAddress = msg.sender;
        }
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

    /****************************************************************
     * Version string encoding/decoding utilities
     ****************************************************************/
    
    /**
     * @dev Encode version string to pseudo address
     * Format: [x]x.[y]y.[z]z-rrrr... -> 0x000000000000000000MMPPSSRRRR...
     * @param versionString The version string to encode
     * @return Encoded version as address
     */
    function versionStringToPseudoAddress(string memory versionString) internal pure returns (address) {
        bytes memory v = bytes(versionString);
        uint256 dot1;
        uint256 dot2;
        uint256 dash;
        
        for (uint256 i = 0; i < v.length; i++) {
            if (v[i] == "." && dot1 == 0) {
                dot1 = i;
            } else if (v[i] == "." && dot2 == 0) {
                dot2 = i;
            } else if (v[i] == "-") {
                dash = i;
                break;
            }
        }
        require(dot1 > 0 && dot2 > dot1 && dash > dot2, "Invalid version format");
        
        // Parse version numbers and build hex string: "000000000000000000" + MM + PP + SS + revision
        bytes memory hexStr = abi.encodePacked(
            "000000000000000000",
            _pad2(v, 0, dot1),
            _pad2(v, dot1 + 1, dot2),
            _pad2(v, dot2 + 1, dash),
            _slice(v, dash + 1, v.length)
        );
        
        // Convert hex string to address
        uint160 result;
        for (uint256 i = 0; i < 40 && i < hexStr.length; i++) {
            result = result * 16 + _hexVal(hexStr[i]);
        }
        return address(result);
    }
    
    /**
     * @dev Decode pseudo address back to version string
     * @param addr The pseudo address to decode
     * @return The decoded version string
     */
    function pseudoAddressToVersionString(address addr) internal pure returns (string memory) {
        if (addr == address(0)) return "";
        bytes memory b = abi.encodePacked(addr);
        
        // Check prefix zeros
        for (uint256 i = 0; i < 9; i++) {
            if (b[i] != 0) return "";
        }
        
        // Convert to hex and parse: bytes 9-11 contain MM PP SS as hex chars
        bytes memory hexStr = bytes(Strings.toHexString(uint160(addr), 20));
        uint256 maj = (uint8(hexStr[20]) - 48) * 10 + (uint8(hexStr[21]) - 48);
        uint256 min = (uint8(hexStr[22]) - 48) * 10 + (uint8(hexStr[23]) - 48);
        uint256 pat = (uint8(hexStr[24]) - 48) * 10 + (uint8(hexStr[25]) - 48);
        
        // Extract revision (trim trailing zeros)
        uint256 len = 16;
        for (uint256 i = 41; i >= 26 && i < 42; i--) {
            if (hexStr[i] != "0") {
                len = i - 25;
                break;
            }
        }
        
        return string(abi.encodePacked(
            Strings.toString(maj), ".",
            Strings.toString(min), ".",
            Strings.toString(pat), "-",
            _slice(hexStr, 26, 26 + len)
        ));
    }
    
    /****************************************************************
     * Private helper functions for version string encoding
     ****************************************************************/
    
    /**
     * @dev Pad number to 2 digits
     */
    function _pad2(bytes memory s, uint256 start, uint256 end) private pure returns (bytes memory) {
        uint256 n;
        for (uint256 i = start; i < end; i++) {
            n = n * 10 + uint8(s[i]) - 48;
        }
        return bytes(n < 10 ? string(abi.encodePacked("0", Strings.toString(n))) : Strings.toString(n));
    }
    
    /**
     * @dev Slice bytes array
     */
    function _slice(bytes memory s, uint256 start, uint256 end) private pure returns (bytes memory) {
        bytes memory r = new bytes(end - start);
        for (uint256 i = 0; i < r.length; i++) {
            r[i] = s[start + i];
        }
        return r;
    }
    
    /**
     * @dev Convert hex character to value
     */
    function _hexVal(bytes1 c) private pure returns (uint8) {
        uint8 v = uint8(c);
        if (v >= 48 && v <= 57) return v - 48;
        if (v >= 97 && v <= 102) return v - 87;
        if (v >= 65 && v <= 70) return v - 55;
        revert("Invalid hex char");
    }
}
