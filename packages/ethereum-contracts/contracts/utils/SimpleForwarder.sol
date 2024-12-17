// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title Forwards arbitrary calls
 * @dev The purpose of this contract is to let accounts forward arbitrary calls,
 * without themselves being the msg.sender from the perspective of the call target.
 * This is necessary for security reasons if the calling account has privileged access anywhere.
 */
contract SimpleForwarder {
    /**
     * @dev Forwards a call for which msg.sender doesn't matter
     * @param target The target contract to call
     * @param data The call data
     * If forwarded native tokens aren't "consumed" by the target, they are sent back to the caller.
     * This will make the transaction revert if neither the target nor the caller take them.
     */
    function forwardCall(address target, bytes calldata data)
        external payable
        returns (bool success, bytes memory returnData)
    {
        // solhint-disable-next-line avoid-low-level-calls
        (success, returnData) = target.call{value: msg.value}(data);
        if (address(this).balance != 0) {
            msg.sender.transfer(address(this).balance);
        }
    }
}