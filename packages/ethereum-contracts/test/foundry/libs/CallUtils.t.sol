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

    /// No filtering: malformed offsets, truncated heads, and arbitrary lengths must not panic.
    function testIsValidAbiEncodedBytes_arbitraryInputDoesNotPanic(bytes memory data) public pure {
        _assertAbiEncodedBytesValidation(data);
    }

    /// Random bytes almost never contain offset 32. Force it to exercise the untrusted length path.
    function testIsValidAbiEncodedBytes_untrustedLengthDoesNotPanic(bytes memory payload, uint256 claimedLength)
        public pure
    {
        bytes memory data = abi.encode(payload);
        assembly ("memory-safe") {
            mstore(add(data, 64), claimedLength)
        }
        _assertAbiEncodedBytesValidation(data);
    }

    function _assertAbiEncodedBytesValidation(bytes memory data) internal pure {
        bool expected;
        if (data.length >= 64) {
            uint256 offset;
            uint256 claimedLength;
            assembly ("memory-safe") {
                offset := mload(add(data, 32))
                claimedLength := mload(add(data, 64))
            }
            uint256 available = data.length - 64;
            // Independent layout oracle: whole words, a payload that fits, and less than one word of padding.
            // Do not use padLength32 here: its safety on hostile lengths is what we are testing.
            expected = offset == 32 && claimedLength <= available
                && available % 32 == 0 && available - claimedLength < 32;
        }
        bool valid = CallUtils.isValidAbiEncodedBytes(data);
        assertEq(valid, expected, "validator must return the expected boolean without reverting");
        if (valid) {
            assertEq(CallUtils.unwrapAbiEncodedBytes(data), abi.decode(data, (bytes)));
        }
    }

    /// Hostile `returns (bytes)`: 64-byte ABI head with offset 32 and inner length `uint256.max`.
    /// Must return false, not panic in `padLength32`, so Host terminate can jail-and-continue.
    function testIsValidAbiEncodedBytes_maxInnerLengthDoesNotPanic() public pure {
        bytes memory data = new bytes(64);
        assembly {
            mstore(add(data, 32), 32)
            mstore(add(data, 64), not(0))
        }
        assertFalse(CallUtils.isValidAbiEncodedBytes(data));
    }

    function testUnwrapAbiEncodedBytes_matchesDecode(bytes memory inner) public pure {
        bytes memory encoded = abi.encode(inner);
        assertTrue(CallUtils.isValidAbiEncodedBytes(encoded));
        bytes memory unwrapped = CallUtils.unwrapAbiEncodedBytes(encoded);
        assertEq(unwrapped, inner);
        assertEq(unwrapped, abi.decode(encoded, (bytes)));
        uint256 encodedPtr;
        uint256 unwrappedPtr;
        assembly {
            encodedPtr := encoded
            unwrappedPtr := unwrapped
        }
        assertEq(unwrappedPtr, encodedPtr + 0x40, "unwrap must alias inner length word");
    }

    /// isValid does not require padding zeros. Dirty pad bytes must not change unwrap vs decode.
    function testUnwrapAbiEncodedBytes_dirtyPaddingStillMatchesDecode(bytes memory inner, uint8 dirt) public pure {
        vm.assume(inner.length % 32 != 0);
        bytes memory encoded = abi.encode(inner);
        uint256 innerLen = inner.length;
        assembly {
            // encoded+96 is start of inner data; pad begins at +innerLen
            mstore8(add(encoded, add(96, innerLen)), dirt)
        }
        assertTrue(CallUtils.isValidAbiEncodedBytes(encoded));
        assertEq(CallUtils.unwrapAbiEncodedBytes(encoded), abi.decode(encoded, (bytes)));
        assertEq(CallUtils.unwrapAbiEncodedBytes(encoded), inner);
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
}
