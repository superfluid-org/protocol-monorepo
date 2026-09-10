pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import { CallbackUtils } from "../../../contracts/libs/CallbackUtils.sol";

contract CallbackUtilsTest is Test {
    function testInsufficientCbGasZone(bool isStaticCall, uint256 callbackGasLimit) external {
        callbackGasLimit = _boundCallbackGasLimit(callbackGasLimit);
        // Non-exhaustive binary search for a counter case
        for (uint256 gasLimit = callbackGasLimit / 2;
             gasLimit <= callbackGasLimit;
             gasLimit += (callbackGasLimit - gasLimit) / 2 + 1) {
            try this._stubCall{ gas: gasLimit }(callbackGasLimit, isStaticCall)
                returns (bool success, bool insufficientCallbackGasProvided, bytes memory) {
                assertFalse(success, "Unexpected success");
                assertTrue(insufficientCallbackGasProvided, "Expected insufficientCallbackGasProvided");
            } catch { }
        }
    }

    function testOutOfCbGasZone(bool isStaticCall, uint256 callbackGasLimit) external {
        callbackGasLimit = _boundCallbackGasLimit(callbackGasLimit);
        // Heuristically, it should not take more than few steps going from transitional zone to
        // out-of-callback-gas zone
        bool transitioned = false;
        for (uint256 i = 0; i < 20; i++) {
            uint256 gasLimit  = callbackGasLimit
                + callbackGasLimit / (CallbackUtils.EIP150_MAGIC_N - i);
            (bool success, bool insufficientCallbackGasProvided, bytes memory reason) =
                this._stubCall{ gas: gasLimit } (callbackGasLimit, isStaticCall);
            if (success) {
                console.log("GasLimit %d / %d", gasLimit, callbackGasLimit);
                assertTrue(false, "Unexpected success");
                break;
            } else {
                console.log("GasLimit %d / %d = %d, ", gasLimit, callbackGasLimit,
                            callbackGasLimit * 100 / (gasLimit - callbackGasLimit));
                console.log("reason length %d", reason.length);
                if (!insufficientCallbackGasProvided) {
                    transitioned = true;
                    break;
                }
            }
        }
        assertTrue(transitioned, "out-of-callback-gas zone not found");
    }

    function _boundCallbackGasLimit(uint256 callbackGasLimit) internal pure returns (uint256) {
        return bound(callbackGasLimit, 500e3, 10e6); // 500k to 10M
    }

    // This is the opcode 0xfe consumes all the rest of the gas
    function _gasUnlimitedEater() external pure { CallbackUtils.consumeAllGas(); }

    function _stubCall(uint256 callbackGasLimit, bool isStaticCall) external
        returns (bool success, bool insufficientCallbackGasProvided, bytes memory returnedData)
    {
        bytes memory callData = abi.encodeCall(this._gasUnlimitedEater, ());
        if (isStaticCall) {
            (success, insufficientCallbackGasProvided, returnedData) =
                CallbackUtils.staticCall(address(this), callData, callbackGasLimit);
        } else {
            (success, insufficientCallbackGasProvided, returnedData) =
                CallbackUtils.externalCall(address(this), callData, callbackGasLimit);
        }
        if (insufficientCallbackGasProvided)
            assertFalse(success, "insufficientCallbackGasProvided only when !success");
    }

    function _returnNBytes(uint256 n) external pure returns (bytes memory) {
        return new bytes(n);
    }

    function _returnRaw(uint256 n) external pure {
        assembly {
            return(0, n)
        }
    }

    function _revertRaw(uint256 n) external pure {
        assembly {
            revert(0, n)
        }
    }

    function _invoke(bool isStaticCall, bytes memory callData, uint256 callbackGasLimit) internal
        returns (bool success, bool insufficientCallbackGasProvided, bytes memory returnedData)
    {
        if (isStaticCall) {
            return CallbackUtils.staticCall(address(this), callData, callbackGasLimit);
        }
        return CallbackUtils.externalCall(address(this), callData, callbackGasLimit);
    }

    function testOversizedReturn_notCopied_successUnchanged(bool isStaticCall) external {
        // ABI-encoded `bytes` of length CAP is 64+CAP > default cap; callData is tiny.
        bytes memory callData = abi.encodeCall(this._returnNBytes, (CallbackUtils.CALLBACK_RETURNDATA_CAP));
        (bool success, bool insufficientCallbackGasProvided, bytes memory returnedData) =
            _invoke(isStaticCall, callData, 500_000);
        assertTrue(success, "oversized success must keep CALL success bit");
        assertFalse(insufficientCallbackGasProvided, "oversized success must not set EIP-150 flag");
        assertEq(returnedData.length, 0, "oversized returndata must not be copied");
    }

    function testOversizedRevert_notCopied_eip150Unpoisoned(bool isStaticCall) external {
        bytes memory callData = abi.encodeCall(this._revertRaw, (CallbackUtils.CALLBACK_RETURNDATA_CAP + 1));
        (bool success, bool insufficientCallbackGasProvided, bytes memory returnedData) =
            _invoke(isStaticCall, callData, 500_000);
        assertFalse(success, "oversized revert must keep CALL success=false");
        assertFalse(insufficientCallbackGasProvided, "EIP-150 flag only when actually gas-starved");
        assertEq(returnedData.length, 0, "oversized revert data must not be copied");
    }

    function testReturnAtCap_isCopied(bool isStaticCall) external {
        uint256 cap = CallbackUtils.CALLBACK_RETURNDATA_CAP;
        bytes memory callData = abi.encodeCall(this._returnRaw, (cap));
        (bool success, bool insufficientCallbackGasProvided, bytes memory returnedData) =
            _invoke(isStaticCall, callData, 500_000);
        assertTrue(success);
        assertFalse(insufficientCallbackGasProvided);
        assertEq(returnedData.length, cap, "equal-to-cap must still copy");
    }

    function testReturnWithinCap_isCopied() external view {
        bytes memory callData = abi.encodeCall(this._returnNBytes, (100));
        (bool success, bool insufficient, bytes memory data) =
            CallbackUtils.staticCall(address(this), callData, 500_000);
        assertTrue(success);
        assertFalse(insufficient);
        // Solidity `returns (bytes)` → abi.encode(bytes): 32 offset + 32 len + padded payload.
        assertEq(data.length, 64 + 128);
        bytes memory decoded = abi.decode(data, (bytes));
        assertEq(decoded.length, 100);
    }

    function testLargeCallDataDoesNotRaiseReturnCap(bool isStaticCall) external {
        uint256 cap = CallbackUtils.CALLBACK_RETURNDATA_CAP;
        uint256 callDataSize = cap + 512;
        bytes memory atCap = abi.encodeCall(this._returnRaw, (cap));
        atCap = bytes.concat(atCap, new bytes(callDataSize - atCap.length));
        assertEq(atCap.length, callDataSize);

        (bool success, bool insufficient, bytes memory data) = _invoke(isStaticCall, atCap, 1_000_000);
        assertTrue(success);
        assertFalse(insufficient);
        assertEq(data.length, cap, "return size == fixed cap must copy");

        bytes memory overCap = abi.encodeCall(this._returnRaw, (cap + 1));
        overCap = bytes.concat(overCap, new bytes(callDataSize - overCap.length));
        assertEq(overCap.length, callDataSize);

        (success, insufficient, data) = _invoke(isStaticCall, overCap, 1_000_000);
        assertTrue(success);
        assertFalse(insufficient);
        assertEq(data.length, 0, "oversized returndata must not copy even when smaller than calldata");
    }
}
