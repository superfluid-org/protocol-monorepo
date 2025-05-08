// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { CallUtils } from "../libs/CallUtils.sol";

contract CallUtilsTester {
    function testIsValidAbiEncodedBytes() external pure {
        require(!CallUtils.isValidAbiEncodedBytes(abi.encode(1, 2, 3)), "bad data");
        require(CallUtils.isValidAbiEncodedBytes(abi.encode(new bytes(0))), "0");
        require(CallUtils.isValidAbiEncodedBytes(abi.encode(new bytes(1))), "1");
        require(CallUtils.isValidAbiEncodedBytes(abi.encode(new bytes(32))), "32");
        require(CallUtils.isValidAbiEncodedBytes(abi.encode(new bytes(33))), "33");
    }
}
