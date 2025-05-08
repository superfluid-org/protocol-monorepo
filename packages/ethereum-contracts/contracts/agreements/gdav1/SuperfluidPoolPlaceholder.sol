// SPDX-License-Identifier: AGPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.23;

import { BeaconProxiable } from "../../upgradability/BeaconProxiable.sol";

/**
 * @title used on first deployment (upgrade case) of GDA
 * in order to solve the circular dependency between GDA and SuperfluidPool
 */
contract SuperfluidPoolPlaceholder is BeaconProxiable {
    // don't allow to create instances of the placeholder
    function initialize(address, address, bool ,bool) external pure {
        // solhint-disable-next-line reason-string
        revert();
    }

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("org.superfluid-finance.contracts.SuperfluidPool.implementation");
    }
}
