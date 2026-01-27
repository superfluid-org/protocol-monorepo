// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import { CallUtils } from "../../../contracts/libs/CallUtils.sol";
import { delegateCallChecked } from "../../../contracts/libs/CallUtils.sol";

// Helper contract to test delegateCallChecked
contract DelegateCallTarget {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }

    function revertAlways() external pure {
        revert("Target revert");
    }

    function revertWithCustomError() external pure {
        revert CustomError("Custom error message");
    }

    function panicAlways() external pure {
        assert(false);
    }

    error CustomError(string message);
}

// Contract that uses delegateCallChecked
contract DelegateCallChecker {
    uint256 public value;

    function delegateCallSetValue(address target, uint256 _value) external {
        delegateCallChecked(target, abi.encodeWithSelector(DelegateCallTarget.setValue.selector, _value));
    }

    function delegateCallRevert(address target) external {
        delegateCallChecked(target, abi.encodeWithSelector(DelegateCallTarget.revertAlways.selector));
    }

    function delegateCallCustomError(address target) external {
        delegateCallChecked(target, abi.encodeWithSelector(DelegateCallTarget.revertWithCustomError.selector));
    }

    function delegateCallPanic(address target) external {
        delegateCallChecked(target, abi.encodeWithSelector(DelegateCallTarget.panicAlways.selector));
    }
}

contract CallUtilsAnvil is Test {
    function testPadLength32(uint256 len) public pure {
        // rounding up the maximum value will overflow the function, so we skip these values
        vm.assume(len <= type(uint256).max - 32);
        assertTrue(CallUtils.padLength32(len) % 32 == 0);
    }

    function testIsValidAbiEncodedBytes(bytes memory data) public pure {
        assertTrue(CallUtils.isValidAbiEncodedBytes(abi.encode(data)));
    }

    function testDelegateCallChecked_Success() public {
        DelegateCallTarget target = new DelegateCallTarget();
        DelegateCallChecker checker = new DelegateCallChecker();

        uint256 testValue = 42;
        checker.delegateCallSetValue(address(target), testValue);

        // The value should be set in the checker contract (not the target) due to delegatecall
        assertEq(checker.value(), testValue);
        assertEq(target.value(), 0);
    }

    function testDelegateCallChecked_Revert() public {
        DelegateCallTarget target = new DelegateCallTarget();
        DelegateCallChecker checker = new DelegateCallChecker();

        // Verify that the actual error message is propagated
        vm.expectRevert("Target revert");
        checker.delegateCallRevert(address(target));
    }

    function testDelegateCallChecked_CustomError() public {
        DelegateCallTarget target = new DelegateCallTarget();
        DelegateCallChecker checker = new DelegateCallChecker();

        // Verify that custom errors are properly propagated
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateCallTarget.CustomError.selector,
                "Custom error message"
            )
        );
        checker.delegateCallCustomError(address(target));
    }

    function testDelegateCallChecked_Panic() public {
        DelegateCallTarget target = new DelegateCallTarget();
        DelegateCallChecker checker = new DelegateCallChecker();

        // Verify that panic errors are properly propagated with error information
        // Panic code 0x01 is for assert(false)
        // The error should be formatted as "CallUtils: target panicked: 0x01"
        vm.expectRevert("CallUtils: target panicked: 0x01");
        checker.delegateCallPanic(address(target));
    }

    // TODO this is a hard fuzzing case, because we need to know if there is a case that:
    // 1. CallUtils.isValidAbiEncodedBytes returns true
    // 2. and abi.decode reverts
    /* function testNegativeIsValidAbiEncodedBytes(bytes memory data) public {
        vm.assume(CallUtils.isValidAbiEncodedBytes(data) == true);
    } */
}
