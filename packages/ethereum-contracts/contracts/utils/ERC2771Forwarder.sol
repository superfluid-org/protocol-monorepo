// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Forwards calls preserving the original msg.sender according to ERC-2771
 */
contract ERC2771Forwarder is Ownable {
    /**
     * @dev Forwards a call passing along the original msg.sender encoded as specified in ERC-2771.
     * @param target The target contract to call
     * @param msgSender The original msg.sender passed along by the trusted contract owner
     * @param data The call data
     */
    function forward2771Call(address target, address msgSender, bytes memory data)
        external payable onlyOwner
        returns(bool success, bytes memory returnData)
    {
        // solhint-disable-next-line avoid-low-level-calls
        (success, returnData) = target.call{value: msg.value}(abi.encodePacked(data, msgSender));
    }

    /**
     * @dev Allows to withdraw native tokens (ETH) which got stuck in this contract.
     * This could happen if a call fails, but the caller doesn't revert the tx.
     */
    function withdrawLostNativeTokens(address payable receiver) external onlyOwner {
        receiver.transfer(address(this).balance);
    }
}