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
}

