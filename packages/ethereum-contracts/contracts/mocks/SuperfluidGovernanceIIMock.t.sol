// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { SuperfluidGovernanceII } from "../gov/SuperfluidGovernanceII.sol";

contract SuperfluidGovernanceIIUpgradabilityTester is SuperfluidGovernanceII {
    // @dev Make sure the storage layout never changes over the course of the development
    function validateStorageLayout() external pure {
        uint256 slot;
        uint256 offset;

        // Initializable _initialized and _initialized

        // SuperfluidToken storages

        assembly { slot:= _configs.slot offset := _configs.offset }
        require (slot == 1 && offset == 0, "_configs changed location");
        // slot 0 offset 0-19: Ownable, offset 20-22: Initializable
        // _configs aligned to slot 1
    }
}
