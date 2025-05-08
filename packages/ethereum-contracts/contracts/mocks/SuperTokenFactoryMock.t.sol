// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import {
    ISuperfluid,
    ISuperToken,
    IPoolAdminNFT,
    IPoolMemberNFT
} from "../interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenFactoryBase, IConstantOutflowNFT, IConstantInflowNFT } from "../superfluid/SuperTokenFactory.sol";

contract SuperTokenFactoryStorageLayoutTester is SuperTokenFactoryBase {
    constructor(
        ISuperfluid host,
        ISuperToken superTokenLogic,
        IConstantOutflowNFT constantOutflowNFT,
        IConstantInflowNFT constantInflowNFT,
        IPoolAdminNFT poolAdminNFT,
        IPoolMemberNFT poolMemberNFT
    )
        SuperTokenFactoryBase(host, superTokenLogic, constantOutflowNFT, constantInflowNFT, poolAdminNFT, poolMemberNFT)
    // solhint-disable-next-line no-empty-blocks
    { }

    // @dev Make sure the storage layout never change over the course of the development
    function validateStorageLayout() external pure {
        uint256 slot;
        uint256 offset;

        // Initializable bool _initialized and bool _initialized

        assembly { slot:= _superTokenLogicDeprecated.slot offset := _superTokenLogicDeprecated.offset }
        require (slot == 0 && offset == 2, "_superTokenLogicDeprecated changed location");

        assembly { slot := _canonicalWrapperSuperTokens.slot offset := _canonicalWrapperSuperTokens.offset }
        require(slot == 1 && offset == 0, "_canonicalWrapperSuperTokens changed location");
    }
}

contract SuperTokenFactoryUpdateLogicContractsTester is SuperTokenFactoryBase {
    uint256 public newVariable;

    constructor(
        ISuperfluid host,
        ISuperToken superTokenLogic,
        IConstantOutflowNFT constantOutflowNFT,
        IConstantInflowNFT constantInflowNFT,
        IPoolAdminNFT poolAdminNFT,
        IPoolMemberNFT poolMemberNFT
    )
        SuperTokenFactoryBase(host, superTokenLogic, constantOutflowNFT, constantInflowNFT, poolAdminNFT, poolMemberNFT)
    // solhint-disable-next-line no-empty-blocks
    { }
}

contract SuperTokenFactoryMock is SuperTokenFactoryBase {
    constructor(
        ISuperfluid host,
        ISuperToken superTokenLogic,
        IConstantOutflowNFT constantOutflowNFT,
        IConstantInflowNFT constantInflowNFT,
        IPoolAdminNFT poolAdminNFT,
        IPoolMemberNFT poolMemberNFT
    )
        SuperTokenFactoryBase(host, superTokenLogic, constantOutflowNFT, constantInflowNFT, poolAdminNFT, poolMemberNFT)
    // solhint-disable-next-line no-empty-blocks
    { }
}

contract SuperTokenFactoryMock42 is SuperTokenFactoryBase {
    constructor(
        ISuperfluid host,
        ISuperToken superTokenLogic,
        IConstantOutflowNFT constantOutflowNFT,
        IConstantInflowNFT constantInflowNFT,
        IPoolAdminNFT poolAdminNFT,
        IPoolMemberNFT poolMemberNFT
    )
        SuperTokenFactoryBase(host, superTokenLogic, constantOutflowNFT, constantInflowNFT, poolAdminNFT, poolMemberNFT)
    // solhint-disable-next-line no-empty-blocks
    { }
}
