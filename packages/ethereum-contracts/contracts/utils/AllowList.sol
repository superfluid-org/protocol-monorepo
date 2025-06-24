// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract AllowList is Ownable {
    mapping(address => bool) internal _map;

    function givePermission(address account) external onlyOwner {
        _map[account] = true;
    }

    function revokePermission(address account) external onlyOwner {
        _map[account] = false;
    }

    function hasPermission(address account) external view returns (bool) {
        return _map[account];
    }
}