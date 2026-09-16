// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.8.0;

import {ISuperfluidPool} from
    "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import {PoolConfig} from
    "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import "./ConstantFlowAgreementV1.hott.sol";
import "./GeneralDistributionAgreementV1.hott.sol";
import "./SuperToken.hott.sol";

// Combine all the hot fuzzes
contract SuperHotFuzz is HotFuzzBase(10), CFAHotFuzzMixin, GDAHotFuzzMixin, SuperTokenHotFuzzMixin {
    uint256 public constant NUM_INITIAL_POOLS = 3;

    constructor() {
        _initTesters();

        PoolConfig memory config = PoolConfig({transferabilityForUnitsOwner: true, distributionFromAnyAddress: true});
        for (uint256 i; i < NUM_INITIAL_POOLS; i++) {
            SuperfluidTester tester = _getOneTester(uint8(i));
            ISuperfluidPool pool = tester.createPool(address(tester), config);
            _addPool(pool);
        }
    }
}
