// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {

    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 initDecimals)
    ERC20(name, symbol)
    {
        _decimals = initDecimals;
    }

    /**
     * @dev See {ERC20-_mint}.
     */
    function mint(address account, uint256 amount) public returns (bool) {
        ERC20._mint(account, amount);
        return true;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setDecimals(uint8 newDecimals) public {
        _decimals = newDecimals;
    }

}
