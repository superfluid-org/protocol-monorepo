// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract NoGetUnderlyingToken {

    // solhint-disable-next-line var-name-mixedcase
    address public CONSTANT_OUTFLOW_NFT;

    // solhint-disable-next-line var-name-mixedcase
    address public CONSTANT_INFLOW_NFT;

    function symbol() public pure returns (string memory) {
        return "NOGET";
    }
}
