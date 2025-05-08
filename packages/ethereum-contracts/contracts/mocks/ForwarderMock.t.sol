// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { CallUtils } from "../libs/CallUtils.sol";
import { IRelayRecipient } from "../interfaces/utils/IRelayRecipient.sol";

/**
 * @dev A test forwarder that can impersonate any account needed.
 *
 * It is obviously not secure for any production use.
 */
contract ForwarderMock {

    // mocked forward request, we don't emulate the signature flow here
    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        bytes data;
    }

    function execute(
        ForwardRequest memory req
    )
        external payable
    {
        bool success;
        bytes memory ret;
        require(
            keccak256(abi.encodePacked(IRelayRecipient(req.to).versionRecipient())) ==
            keccak256("v1"),
            "unknown IRelayRecipient.versionRecipient");
        // solhint-disable-next-line avoid-low-level-calls
        (success, ret) = req.to.call{gas : req.gas, value : req.value}(abi.encodePacked(req.data, req.from));
        if (!success) CallUtils.revertFromReturnedData(ret);
    }

}
