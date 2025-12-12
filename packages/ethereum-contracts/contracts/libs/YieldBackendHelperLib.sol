// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IYieldBackend } from "../interfaces/superfluid/IYieldBackend.sol";


/**
 * @dev Helper to delegatecall yield backend methods.
 * Reverts if the call fails.
 * Does NOT return anything!
 */
library YieldBackendHelperLib {
    function dCall(IYieldBackend yieldBackend, bytes memory callData) internal {
        (bool success,) = address(yieldBackend).delegatecall(callData);
        require(success, "yield backend delegatecall failed");
    }
}