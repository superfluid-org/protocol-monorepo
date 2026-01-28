// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { ISuperfluid } from "../superfluid/ISuperfluid.sol";

/**
 * @dev User-defined macro used in implementations of TrustedMacros.
 */
interface IUserDefinedMacro {
    /**
     * @dev Build batch operations according to the parameters provided.
     * It's up to the macro contract to map the provided params (can also be empty) to any
     * valid list of operations.
     * @param  host       The executing host contract.
     * @param  params     The encoded form of the parameters.
     * @param  msgSender  The msg.sender of the call to the MacroForwarder.
     * @return operations The batch operations built.
     */
    function buildBatchOperations(ISuperfluid host, bytes memory params, address msgSender) external view
        returns (ISuperfluid.Operation[] memory operations);

    /**
     * @dev A post-check function which is called after execution.
     * It allows to do arbitrary checks based on the state after execution,
     * and to revert if the result is not as expected.
     * Can be an empty implementation if no check is needed.
     * @param  host       The host contract set for the executing MacroForwarder.
     * @param  params     The encoded parameters as provided to `MacroForwarder.runMacro()`
     * @param  msgSender  The msg.sender of the call to the MacroForwarder.
     */
    function postCheck(ISuperfluid host, bytes memory params, address msgSender) external view;

    /*
     * Additional to the required interface, we recommend to implement one or multiple view functions
     * which take operation specific typed arguments and return the abi encoded bytes.
     * As a convention, the name of those functions shall start with `params`.
     *
     * Implementing this view function(s) has several advantages:
     * - Allows to build more complex macros with internally encapsulated dispatching logic
     * - Allows to use generic tooling like Explorers to interact with the macro
     * - Allows to build auto-generated UIs based on the contract ABI
     * - Makes it easier to interface with the macro from Dapps
     *
     * You can consult the related test code in `MacroForwarderTest.t.sol` for examples.
     */
}

interface IUserDefined712Macro is IUserDefinedMacro {
    // TODO: this probably needs to be a function of the message, for the dispatching pattern
    // the metaphor being: a macro is like an api, an action is like an endpoint (defining the set of arguments)
    function getMessageTypeHash() external view returns (bytes32);
    // TODO: should it take the known and required fields already decoded instead?
    function getMessageStructHash(bytes memory message) external view returns (bytes32);
}