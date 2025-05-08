// SPDX-License-Identifier: AGPLv3
// solhint-disable reason-string
// solhint-disable func-name-mixedcase
pragma solidity >= 0.8.0;

import "../HotFuzzBase.sol";

contract ConstantFlowAgreementV1Mock is ConstantFlowAgreementV1 {
    // solhint-disable-next-line no-empty-blocks
    constructor() ConstantFlowAgreementV1(ISuperfluid(address(0))) {}

    function getMaximumFlowRateFromDepositPure(
        uint256 liquidationPeriod,
        uint256 deposit)
        external pure
        returns (int96 flowRate)
    {
        return _getMaximumFlowRateFromDepositPure(liquidationPeriod, deposit);
    }

    function getDepositRequiredForFlowRatePure(
        uint256 minimumDeposit,
        uint256 liquidationPeriod,
        int96 flowRate)
        external pure
        returns (uint256 deposit)
    {
        return _getDepositRequiredForFlowRatePure(minimumDeposit, liquidationPeriod, flowRate);
    }
}

contract CFAProperties {

    ConstantFlowAgreementV1Mock immutable private cfa;

    constructor() {
        cfa = new ConstantFlowAgreementV1Mock();
    }

    function testMaximumFlowRateAllowedForDeposit(
        uint32 liquidationPeriod,
        uint96 depositAllowed)
        public view
    {
        require(liquidationPeriod > 0, "FOUNDRY::ASSUME");
        require(depositAllowed >= uint96(1 << 32), "FOUNDRY::ASSUME");
        require(uint256(liquidationPeriod) * uint256(depositAllowed)
            <= uint256(uint96(type(int96).max)), "FOUNDRY::ASSUME");
        int96 flowRate = cfa.getMaximumFlowRateFromDepositPure(liquidationPeriod, depositAllowed);
        assert(flowRate > 0);
        uint256 deposit = cfa.getDepositRequiredForFlowRatePure(0, liquidationPeriod, flowRate);
        assert(uint256(depositAllowed) >= deposit);
    }

    function testMinimumDeposit(
        uint64 minimumDeposit,
        uint32 liquidationPeriod,
        int96 flowRate)
        public view
    {
        require(uint96(minimumDeposit) >= uint96(1 << 32), "FOUNDRY::ASSUME");
        require(liquidationPeriod > 0, "FOUNDRY::ASSUME");
        require(flowRate > 0, "FOUNDRY::ASSUME");
        require(uint256(liquidationPeriod) * uint256(uint96(flowRate))
            <= uint256(uint96(type(int96).max)), "FOUNDRY::ASSUME");
        uint256 deposit = cfa.getDepositRequiredForFlowRatePure(minimumDeposit, liquidationPeriod, flowRate);
        assert(deposit >= minimumDeposit);
    }
}
