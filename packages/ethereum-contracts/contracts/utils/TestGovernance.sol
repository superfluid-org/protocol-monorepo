// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import {
    ISuperfluid,
    ISuperfluidToken
} from "../interfaces/superfluid/ISuperfluid.sol";
import { SuperfluidGovernanceBase } from "../gov/SuperfluidGovernanceBase.sol";

import { Ownable } from "@openzeppelin-v5/contracts/access/Ownable.sol";


/**
 * @title Test governance contract
 * @author Superfluid
 * @dev A initializable version of the governance for testing purpose
 */
contract TestGovernance is
    Ownable,
    SuperfluidGovernanceBase
{
    ISuperfluid private _host;

    constructor() Ownable(_msgSender()) {}

    function initialize(
        ISuperfluid host,
        address rewardAddress,
        uint256 liquidationPeriod,
        uint256 patricianPeriod,
        address[] calldata trustedForwarders
    )
        external
    {
        // can initialize only once
        assert(address(host) != address(0));
        assert(address(_host) == address(0));

        _host = host;

        setRewardAddress(_host, ISuperfluidToken(address(0)), rewardAddress);

        setPPPConfig(host, ISuperfluidToken(address(0)), liquidationPeriod, patricianPeriod);

        for (uint i = 0; i < trustedForwarders.length; ++i) {
            enableTrustedForwarder(_host, ISuperfluidToken(address(0)), trustedForwarders[i]);
        }
    }

    function _requireAuthorised(ISuperfluid host)
        internal view override
    {
        assert(address(host) == address(_host));
        assert(owner() == _msgSender());
    }
}
