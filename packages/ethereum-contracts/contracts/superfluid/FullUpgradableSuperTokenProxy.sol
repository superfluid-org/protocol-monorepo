// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ISuperTokenFactory } from "../interfaces/superfluid/ISuperTokenFactory.sol";
import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";


/**
 * @title Full upgradable super token proxy contract
 * @author Superfluid
 */
contract FullUpgradableSuperTokenProxy is Proxy {

    // web3.utils.keccak256("org.superfluid-finance.FullUpgradableSuperTokenWrapper.factory_slot")
    bytes32 internal constant _FACTORY_SLOT = 0xb8fcd5719b3ddf8626f3664705a89b7fc476129a58c1aa5eda57c600cc1821a0;

    error FUSTP_ALREADY_INITIALIZED();

    function initialize() external
    {
        address factory;
        assembly { // solium-disable-line
            factory := sload(_FACTORY_SLOT)
        }
        if (address(factory) != address(0)) revert FUSTP_ALREADY_INITIALIZED();
        factory = msg.sender;
        assembly { // solium-disable-line
            sstore(_FACTORY_SLOT, factory)
        }
    }

    function _implementation() internal override view returns (address impl) {
        ISuperTokenFactory factory;
        assembly { // solium-disable-line
            factory := sload(_FACTORY_SLOT)
        }
        assert(address(factory) != address(0));
        return address(factory.getSuperTokenLogic());
    }

}
