// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { Resolver } from "./Resolver.sol";

/// @title TestResolver contract
/// @author Superfluid
/// @notice A Resolver specifically used for testing
/// @dev Used by the SuperfluidFrameworkDeployer to grant admin privileges to its deployer
contract TestResolver is Resolver {
    constructor(address _additionalAdmin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _additionalAdmin);
    }

    function addAdmin(address _additionalAdmin) external {
        _grantRole(DEFAULT_ADMIN_ROLE, _additionalAdmin);
    }
}
