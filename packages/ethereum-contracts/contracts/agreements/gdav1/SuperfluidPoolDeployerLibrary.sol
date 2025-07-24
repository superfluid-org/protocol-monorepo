// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { ISuperfluidToken } from "../../interfaces/superfluid/ISuperfluidToken.sol";
import { SuperfluidPool } from "./SuperfluidPool.sol";
import { PoolConfig } from "../../interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import { ISuperToken } from "../../interfaces/superfluid/ISuperToken.sol";
import { ISuperfluidPool } from "../../interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { IPoolAdminNFT } from "../../interfaces/agreements/gdav1/IPoolAdminNFT.sol";

library SuperfluidPoolDeployerLibrary {
    function deploy(
        address beacon,
        address admin,
        ISuperfluidToken token,
        PoolConfig calldata config,
        string calldata name,
        string calldata symbol,
        uint8 decimals
    ) external returns (SuperfluidPool pool) {
        bytes memory initializeCallData = abi.encodeWithSelector(
            SuperfluidPool.initialize.selector,
            admin,
            token,
            config.transferabilityForUnitsOwner,
            config.distributionFromAnyAddress,
            name,
            symbol,
            decimals
        );
        BeaconProxy superfluidPoolBeaconProxy = new BeaconProxy(
            beacon,
            initializeCallData
        );
        pool = SuperfluidPool(address(superfluidPoolBeaconProxy));
    }

    // This was moved out of GeneralDistributionAgreementV1.sol to reduce the contract size.
    function mintPoolAdminNFT(ISuperfluidToken token, ISuperfluidPool pool) external {
        address poolAdminNFTAddress;
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) =
            address(token).staticcall(abi.encodeWithSelector(ISuperToken.POOL_ADMIN_NFT.selector));

        if (success) {
            // @note We are aware this may revert if a Custom SuperToken's
            // POOL_ADMIN_NFT does not return data that can be
            // decoded to an address. This would mean it was intentionally
            // done by the creator of the Custom SuperToken logic and is
            // fully expected to revert in that case as the author desired.
            poolAdminNFTAddress = abi.decode(data, (address));
        }

        if (poolAdminNFTAddress != address(0)) {
            IPoolAdminNFT(poolAdminNFTAddress).mint(address(pool));
        }
    }
}
