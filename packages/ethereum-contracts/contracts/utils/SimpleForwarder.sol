// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Forwards arbitrary calls
 * @dev The purpose of this contract is to let accounts forward arbitrary calls,
 * without themselves being the msg.sender from the perspective of the call target.
 * This is necessary for security reasons if the calling account has privileged access anywhere.
 */
contract SimpleForwarder is Ownable {
    /**
     * @dev Forwards a call for which msg.sender doesn't matter
     * @param target The target contract to call
     * @param data The call data
     * Note: restricted to `onlyOwner` in order to minimize attack surface
     */
    function forwardCall(address target, bytes calldata data)
        external payable onlyOwner
        returns (bool success, bytes memory returnData)
    {
        // solhint-disable-next-line avoid-low-level-calls
        (success, returnData) = target.call{value: msg.value}(data);
    }

    /**
     * @dev Allows to withdraw native tokens (ETH) which got stuck in this contract.
     * This could happen if a call fails, but the caller doesn't revert the tx.
     */
    function withdrawLostNativeTokens(address payable receiver) external onlyOwner {
        receiver.transfer(address(this).balance);
    }
}