// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    ISuperfluid,
    SuperAppBase,
    SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

contract SuperAppTester is SuperAppBase {

    uint256 public val;
    ISuperfluid public host;

    error OnlyHost();

    constructor(ISuperfluid _host) {

        uint256 configWord =
            SuperAppDefinitions.APP_LEVEL_FINAL;

        host = _host;

        host.registerAppWithKey(configWord, "");
    }

    function setVal(uint256 _newVal, bytes calldata ctx)
        external
        onlyHost
        returns (bytes memory newCtx)
    {
        val = _newVal;
        return ctx;
    }

    modifier onlyHost() {
        if (msg.sender != address(host)) revert OnlyHost();
        _;
    }
}
