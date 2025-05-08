// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import { CallUtils } from "../../../contracts/libs/CallUtils.sol";

contract CallUtilsAnvil is Test {
    function testPadLength32(uint256 len) public pure {
        // rounding up the maximum value will overflow the function, so we skip these values
        vm.assume(len <= type(uint256).max - 32);
        assertTrue(CallUtils.padLength32(len) % 32 == 0);
    }

    function testIsValidAbiEncodedBytes(bytes memory data) public pure {
        assertTrue(CallUtils.isValidAbiEncodedBytes(abi.encode(data)));
    }

    // TODO this is a hard fuzzing case, because we need to know if there is a case that:
    // 1. CallUtils.isValidAbiEncodedBytes returns true
    // 2. and abi.decode reverts
    /* function testNegativeIsValidAbiEncodedBytes(bytes memory data) public {
        vm.assume(CallUtils.isValidAbiEncodedBytes(data) == true);
    } */
}
