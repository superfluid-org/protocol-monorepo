// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IMacro } from "../interfaces/utils/IMacro.sol";
import { ISuperfluid } from "../interfaces/superfluid/ISuperfluid.sol";
import { ForwarderBase } from "../utils/ForwarderBase.sol";


/**
 * @dev This is a minimal macro forwarder without meta-tx capabilities,
 * requiring users to _blind sign_ encoded macro actions.
 */
contract BlindMacroForwarder is ForwarderBase {
    /// @dev Emitted after a macro is executed on behalf of the caller.
    event MacroExecuted(address indexed account, address indexed macroContract);

    constructor(ISuperfluid host) ForwarderBase(host) {}

    /**
     * @dev A convenience view wrapper for building the batch operations using a macro.
     * @param  m          Target macro.
     * @param  params     Parameters to simulate the macro; passed directly to the macro.
     * @return operations Operations returned by the macro after the simulation.
     */
    function buildBatchOperations(IMacro m, bytes calldata params) public view
        returns (ISuperfluid.Operation[] memory operations)
    {
        operations = m.buildBatchOperations(_host, params, msg.sender);
    }

    /**
     * @dev Run the macro defined by the provided macro contract and params.
     * @param  m      Target macro.
     * @param  params Parameters to run the macro; passed directly to the macro.
     * If value (native coins) is provided, it is forwarded.
     */
    function runMacro(IMacro m, bytes calldata params) external payable returns (bool)
    {
        ISuperfluid.Operation[] memory operations = buildBatchOperations(m, params);
        bool retVal = _forwardBatchCallWithSenderAndValue(operations, msg.sender, msg.value);
        m.postCheck(_host, params, msg.sender);
        emit MacroExecuted(msg.sender, address(m));
        return retVal;
    }
}
