// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { UUPSProxiable } from "../upgradability/UUPSProxiable.sol";
import { ISuperAgreement } from "../interfaces/superfluid/ISuperAgreement.sol";

/**
 * @title Superfluid agreement base boilerplate contract
 * @author Superfluid
 */
abstract contract AgreementBase is
    UUPSProxiable,
    ISuperAgreement
{
    address immutable internal _host;

    // Custom Erorrs
    error AGREEMENT_BASE_ONLY_HOST(); // 0x1601d91e

    constructor(address host)
    {
        _host = host;
    }

    function proxiableUUID()
        public view override
        returns (bytes32)
    {
        return ISuperAgreement(this).agreementType();
    }

    function updateCode(address newAddress)
        external override
    {
        if (msg.sender != _host) revert AGREEMENT_BASE_ONLY_HOST();
        return _updateCodeAddress(newAddress);
    }

}
