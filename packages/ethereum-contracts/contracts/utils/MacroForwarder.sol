// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IUserDefinedMacro } from "../interfaces/utils/IUserDefinedMacro.sol";
import { ISuperfluid } from "../interfaces/superfluid/ISuperfluid.sol";
import { ForwarderBase } from "../utils/ForwarderBase.sol";


/**
 * @dev This is a minimal version of a trusted forwarder with high degree of extensibility
 * through permissionless and user-defined "macro contracts".
 */
contract MacroForwarder is ForwarderBase {
    constructor(ISuperfluid host) ForwarderBase(host) {}

    /**
     * @dev A convenience view wrapper for building the batch operations using a macro.
     * @param  m          Target macro.
     * @param  params     Parameters to simulate the macro.
     * @return operations Operations returned by the macro after the simulation.
     */
    function buildBatchOperations(IUserDefinedMacro m, bytes calldata params) public view
        returns (ISuperfluid.Operation[] memory operations)
    {
        operations = m.buildBatchOperations(_host, params, msg.sender);
    }

    /**
     * @dev Run the macro defined by the provided macro contract and params.
     * @param  m      Target macro.
     * @param  params Parameters to run the macro.
     * If value (native coins) is provided, it is forwarded.
     */
    function runMacro(IUserDefinedMacro m, bytes calldata params) external payable returns (bool)
    {
        ISuperfluid.Operation[] memory operations = buildBatchOperations(m, params);
        bool retVal = _forwardBatchCallWithValue(operations, msg.value);
        m.postCheck(_host, params, msg.sender);
        return retVal;
    }
}
