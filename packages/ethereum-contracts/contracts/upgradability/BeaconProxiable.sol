// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract BeaconProxiable is Initializable {

    // allows to mark logic contracts as initialized
    // solhint-disable-next-line no-empty-blocks
    function castrate() external initializer { }

    /**
     * @dev Proxiable UUID marker function, this would help to avoid wrong logic
     *      contract to be used for upgrading.
     */
    function proxiableUUID() public pure virtual returns (bytes32);
}