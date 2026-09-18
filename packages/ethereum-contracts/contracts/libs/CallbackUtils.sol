// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

/**
 * @title Callback utilities solidity library
 * @notice An internal library used to handle different types of out of gas errors in callbacks
 *
 * @dev
 *
 * ## Problem Statement
 *
 * When calling an untrusted external callback (or hook), gas limit is usually provided to prevent
 * grief attack from them. However, such gas limits are nested. From the callback invoking site, one
 * might need to differentiate the cases between the outer-layer induced out-of-gas vs. the callback
 * resulted out-of-gas.
 *
 * This library solves such challenge by safely marking the second case with an explicit flag of
 * insufficient-callback-gas-provided. In order to use this library, one must first understand the
 * concept of callback gas limit zones.
 *
 * ## Definitions: callback gas limit zones
 *
 * +---------------------------+--------------+---------------------+
 * | insufficient-callback-gas | transitional | out-of-callback-gas |
 * +---------------------------+--------------+---------------------+
 *
 * - insufficient-callback-gas zone
 *
 *   This zone includes all outer gas limits that are below callback gas limit. The invariance of
 *   this zone is that calling the callback shall return with the insufficient-callback-gas-provided
 *   set to true if more gas is needed to execute the callback.
 *
 * - out-of-callback-gas zone
 *
 *   Within this continuous zone, the invariance is that calling the callback shall never return
 *   with the insufficient-callback-gas-provided flag set to true.
 *
 * - transitional zone
 *
 *   Between the insufficient-callback-gas zone to the out-of-callback-gas zone, there is a zone of
 *   unspecified size where insufficient-callback-gas-provided may be set to true. This is due the
 *   factors of EIP-150 Magic N and callback setup overhead.
 *
 * ## EIP-150 Magic N
 *
 * "If a call asks for more gas than the maximum allowed amount (i.e. the total amount of gas
 * remaining in the parent after subtracting the gas cost of the call and memory expansion), do not
 * return an OOG error; instead, if a call asks for more gas than all but one 64th of the maximum
 * allowed amount, call with all but one 64th of the maximum allowed amount of gas (this is
 * equivalent to a version of EIP-90 plus EIP-114). CREATE only provides all but one 64th of the
 * parent gas to the child call."
 *
 * Another article about this topic:
 * https://medium.com/%40wighawag/ethereum-the-concept-of-gas-and-its-dangers-28d0eb809bb2
 *
 * ## Callback returndata cap
 *
 * Copying callback returndata consumes gas for memory allocation and copying in the caller.
 * `CALLBACK_RETURNDATA_CAP` bounds the bytes copied after each CALL or STATICCALL, including
 * revert data. If `returndatasize()` exceeds the cap, the result is empty bytes.
 * `success` reports the CALL/STATICCALL result. The Host validates successful responses
 * and handles callback failures. EIP-150 detection runs after the copy.
 *
 */
library CallbackUtils {
    /// The magic N constant from the EIP-150
    uint256 internal constant EIP150_MAGIC_N = 64;

    /// Maximum context length supplied to a SuperApp callback.
    uint256 internal constant CALLBACK_CONTEXT_CAP = 32 * 1024;

    /// Fixed cap on total ABI-encoded callback returndata, regardless of calldata size.
    uint256 internal constant CALLBACK_RETURNDATA_CAP = 128 * 1024;

    /// Make a call to the target with a callback gas limit.
    function externalCall(address target, bytes memory callData, uint256 callbackGasLimit) internal
        returns (bool success, bool insufficientCallbackGasProvided, bytes memory returnedData)
    {
        uint256 gasLeftBefore = gasleft();
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            success := call(callbackGasLimit, target, 0, add(callData, 0x20), mload(callData), 0, 0)
        }
        returnedData = _copyCallbackReturndata();
        if (!success) {
            if (gasleft() <= gasLeftBefore / EIP150_MAGIC_N) insufficientCallbackGasProvided = true;
        }
    }

    /// Make a staticcall to the target with a callback gas limit.
    function staticCall(address target, bytes memory callData, uint256 callbackGasLimit) internal view
        returns (bool success, bool insufficientCallbackGasProvided, bytes memory returnedData)
    {
        uint256 gasLeftBefore = gasleft();
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            success := staticcall(callbackGasLimit, target, add(callData, 0x20), mload(callData), 0, 0)
        }
        returnedData = _copyCallbackReturndata();
        if (!success) {
            if (gasleft() <= gasLeftBefore / EIP150_MAGIC_N) insufficientCallbackGasProvided = true;
        }
    }

    /// Copy returndata within the cap; otherwise return empty bytes.
    /// Must run immediately after the CALL/STATICCALL (output size 0, 0); internal, so returndata is preserved.
    function _copyCallbackReturndata() private pure
        returns (bytes memory returnedData)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            let rds := returndatasize()
            returnedData := mload(0x40)
            switch gt(rds, CALLBACK_RETURNDATA_CAP)
            case 1 {
                mstore(returnedData, 0)
                mstore(0x40, add(returnedData, 0x20))
            }
            default {
                mstore(returnedData, rds)
                returndatacopy(add(returnedData, 0x20), 0, rds)
                mstore(0x40, add(returnedData, and(add(rds, 0x3f), not(0x1f))))
            }
        }
    }

    /// Reliably consume all the gas given.
    function consumeAllGas() internal pure {
        // Neither revert or assert consume all gas since Solidity 0.8.20
        // https://docs.soliditylang.org/en/v0.8.20/control-structures.html#panic-via-assert-and-error-via-require
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") { invalid() }
    }
}
