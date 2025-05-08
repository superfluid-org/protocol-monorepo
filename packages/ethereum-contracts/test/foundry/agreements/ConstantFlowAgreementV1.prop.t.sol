// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import { ISuperfluid, ConstantFlowAgreementV1 } from "../../../contracts/agreements/ConstantFlowAgreementV1.sol";

contract ConstantFlowAgreementV1Mock is ConstantFlowAgreementV1 {
    constructor() ConstantFlowAgreementV1(ISuperfluid(address(0))) { }

    function encodeFlowData(FlowData memory flowData) external pure returns (uint256 wordA) {
        return uint256(_encodeFlowData(flowData)[0]);
    }

    function decodeFlowData(uint256 wordA) external pure returns (bool exist, FlowData memory flowData) {
        return _decodeFlowData(wordA);
    }

    function encodeFlowOperatorData(FlowOperatorData memory flowOperatorData) external pure returns (uint256 wordA) {
        return uint256(_encodeFlowOperatorData(flowOperatorData)[0]);
    }

    function decodeFlowOperatorData(uint256 wordA)
        external
        pure
        returns (bool exist, FlowOperatorData memory flowOperatorData)
    {
        return _decodeFlowOperatorData(wordA);
    }

    function clipDepositNumberRoundingUp(uint256 deposit) external pure returns (uint256) {
        return _clipDepositNumberRoundingUp(deposit);
    }

    function getMaximumFlowRateFromDepositPure(uint256 liquidationPeriod, uint256 deposit)
        external
        pure
        returns (int96 flowRate)
    {
        return _getMaximumFlowRateFromDepositPure(liquidationPeriod, deposit);
    }

    function getDepositRequiredForFlowRatePure(uint256 minimumDeposit, uint256 liquidationPeriod, int96 flowRate)
        external
        pure
        returns (uint256 deposit)
    {
        return _getDepositRequiredForFlowRatePure(minimumDeposit, liquidationPeriod, flowRate);
    }
}

contract ConstantFlowAgreementV1PropertyTest is Test {
    ConstantFlowAgreementV1Mock private immutable cfa;

    constructor() {
        cfa = new ConstantFlowAgreementV1Mock();
    }

    function testMaximumFlowRateAllowedForDeposit(uint32 liquidationPeriod, uint96 depositAllowed) public view {
        depositAllowed = uint96(bound(uint256(depositAllowed), cfa.DEFAULT_MINIMUM_DEPOSIT(), cfa.MAXIMUM_DEPOSIT()));
        vm.assume(liquidationPeriod > 0);

        int96 flowRate = cfa.getMaximumFlowRateFromDepositPure(liquidationPeriod, depositAllowed);
        assert(flowRate > 0);
        // let's also assume these edge cases away
        vm.assume(uint256(liquidationPeriod) * uint256(uint96(flowRate)) <= cfa.MAXIMUM_FLOW_RATE());
        uint256 deposit = cfa.getDepositRequiredForFlowRatePure(0, liquidationPeriod, flowRate);
        assertTrue(uint256(depositAllowed) >= deposit, "CFAv1.prop: depositAllowed < deposit");
    }

    function testMinimumDeposit(uint64 minimumDeposit, uint32 liquidationPeriod, int96 flowRate) public view {
        minimumDeposit = uint32(bound(uint256(minimumDeposit), cfa.DEFAULT_MINIMUM_DEPOSIT(), type(uint64).max));
        vm.assume(liquidationPeriod > 0);
        vm.assume(flowRate > 0);
        vm.assume(uint256(liquidationPeriod) * uint256(uint96(flowRate)) <= cfa.MAXIMUM_FLOW_RATE());

        uint256 deposit = cfa.getDepositRequiredForFlowRatePure(minimumDeposit, liquidationPeriod, flowRate);
        assertTrue(deposit >= minimumDeposit, "CFAv1.prop: minimum deposit < deposit");
    }

    /**
     * tl;dr testing f(a) + f(b) = f(f(a) + f(b)) where f is clipping
     * @dev This test was added to provide extra assurance that the sum of two minimum deposits is
     * equal to the clipped sum of two minimum deposits.
     * This makes sense intuitively as the last 32 bits are clipped off for both deposits so when
     * adding, nothing will ever appear in the last 32 bits.
     * This test was added because we deleted the extra clipping in the _changeFlowToApp function
     * export FOUNDRY_FUZZ_RUNS=10000 && forge test --match testMinimumDepositClippingSumInvariant
     */
    function testMinimumDepositClippingSumInvariant(uint256 depositA, uint256 depositB) public view {
        vm.assume(type(uint256).max - depositA < depositB);
        vm.assume(type(uint256).max - depositB < depositA);
        uint256 clippedDepositA = cfa.clipDepositNumberRoundingUp(depositA);
        uint256 clippedDepositB = cfa.clipDepositNumberRoundingUp(depositB);
        clippedDepositA = bound(clippedDepositA, 0, type(uint256).max - clippedDepositB);
        clippedDepositB = bound(clippedDepositB, 0, type(uint256).max - clippedDepositA);
        uint256 summedDeposit = clippedDepositA + clippedDepositB;
        uint256 clippedSummedDeposit = cfa.clipDepositNumberRoundingUp(summedDeposit);
        assertTrue(summedDeposit == clippedSummedDeposit, "CFAv1.prop: clipped sum != sum");
    }

    /**
     * tl;dr testing f(f(a)) = f(a) where f is clipping
     * @dev This test was added to provide additional assurances that applying the minimum deposit clipping
     * multiple times on a value doesn't change it.
     */
    function testReapplyMinimumDepositClippingInvariant(uint256 deposit) public view {
        uint256 initialClipped = cfa.clipDepositNumberRoundingUp(deposit);
        uint256 reclipped = cfa.clipDepositNumberRoundingUp(initialClipped);
        assertTrue(initialClipped == reclipped, "CFAv1.prop: clipped sum != sum");
    }

    function testFlowDataEncoding(uint32 timestamp, int96 flowRate, uint64 depositClipped, uint64 owedDepositClipped)
        public view
    {
        ConstantFlowAgreementV1.FlowData memory a = ConstantFlowAgreementV1.FlowData({
            timestamp: uint256(timestamp),
            flowRate: flowRate,
            deposit: uint256(uint64(depositClipped << 32)),
            owedDeposit: uint256(uint64(owedDepositClipped << 32))
        });
        uint256 wordA = cfa.encodeFlowData(a);
        bool exist;
        ConstantFlowAgreementV1.FlowData memory b;
        (exist, b) = cfa.decodeFlowData(wordA);
        assertEq(a.timestamp, b.timestamp, "CFAv1Prop: timestamp !=");
        assertEq(a.flowRate, b.flowRate, "CFAv1Prop: flowRate !=");
        assertEq(a.deposit, b.deposit, "CFAv1Prop: deposit !=");
        assertEq(a.owedDeposit, b.owedDeposit, "CFAv1Prop: owedDeposit !=");
    }

    function testFlowOperatorDataEncoding(uint8 permissions, int96 flowRateAllowance) public view {
        vm.assume(flowRateAllowance >= 0);
        ConstantFlowAgreementV1.FlowOperatorData memory a =
            ConstantFlowAgreementV1.FlowOperatorData({ permissions: permissions, flowRateAllowance: flowRateAllowance });
        uint256 wordA = cfa.encodeFlowOperatorData(a);
        bool exist;
        ConstantFlowAgreementV1.FlowOperatorData memory b;
        (exist, b) = cfa.decodeFlowOperatorData(wordA);
        assertEq(a.permissions, b.permissions, "CFAv1Prop: permissions !=");
        assertEq(a.flowRateAllowance, b.flowRateAllowance, "CFAv1Prop: flowRateAllowance !=");
    }
}
