// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IUserDefinedMacro } from "../interfaces/utils/IUserDefinedMacro.sol";
import { ISuperfluid } from "../interfaces/superfluid/ISuperfluid.sol";
import { ForwarderBase } from "./ForwarderBase.sol";

/**
 * @dev EIP-712-aware macro forwarder (clear signing).
 * In this minimal iteration: decodes payload as appParams and passes through to the macro.
 * Envelope verification, nonce, and registry checks to be added in follow-up.
 */
contract Only712MacroForwarder is ForwarderBase {
    constructor(ISuperfluid host, address /*registry*/) ForwarderBase(host) {}

    /**
     * @dev Run the macro with encoded payload (envelope + app params; envelope verification TBD).
     * @param m Target macro.
     * @param params Encoded payload. Minimal format: abi.encode(appParams).
     */
    function runMacro(IUserDefinedMacro m, bytes calldata params) external payable returns (bool) {
        bytes memory appParams = abi.decode(params, (bytes));

        ISuperfluid.Operation[] memory operations = m.buildBatchOperations(_host, appParams, msg.sender);
        bool retVal = _forwardBatchCallWithValue(operations, msg.value);
        m.postCheck(_host, appParams, msg.sender);
        return retVal;
    }
}
