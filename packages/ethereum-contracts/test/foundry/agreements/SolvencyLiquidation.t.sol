// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";
import "../FoundrySuperfluidTester.t.sol";
import {
    IGeneralDistributionAgreementV1,
    PoolConfig
} from "../../../contracts/interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import { ISuperfluid } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperfluidPool } from "../../../contracts/agreements/gdav1/SuperfluidPool.sol";
import { CFASuperAppBase } from "../../../contracts/apps/CFASuperAppBase.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";

/// @dev Relays inbound CFA to a configured outbound CFA rate; optional GDA distribution.
contract OwedDepositSuperApp is CFASuperAppBase {
    using SuperTokenV1Library for ISuperToken;

    address internal immutable _receiver;
    int96 internal _outboundFlowRate;

    constructor(ISuperfluid host, address receiver) CFASuperAppBase(host) {
        _receiver = receiver;
        selfRegister(true, false, false);
    }

    function setOutboundFlowRate(int96 outboundFlowRate) external {
        _outboundFlowRate = outboundFlowRate;
    }

    function onFlowCreated(ISuperToken superToken, address, int96, bytes calldata ctx)
        internal
        override
        returns (bytes memory newCtx)
    {
        if (_outboundFlowRate > 0) {
            newCtx = superToken.createFlowWithCtx(_receiver, _outboundFlowRate, ctx);
        } else {
            newCtx = ctx;
        }
    }

    function startDistributionFlow(ISuperToken superToken, ISuperfluidPool pool, int96 flowRate) external {
        superToken.distributeFlow(pool, flowRate);
    }

    function transferAll(ISuperToken superToken, address receiver) external {
        superToken.transfer(receiver, superToken.balanceOf(address(this)));
    }
}

/// @title Solvency liquidation integration tests
/// @notice CFA/GDA liquidation uses account-level `totalDeposit` from `realtimeBalanceOf`
///         (sum across agreements). `owedDeposit` does not change that coverage threshold.
///
/// Terminology:
/// - critical: `availableBalance < 0`
/// - deposit-covered (CFA/GDA liquidation): `availableBalance + totalDeposit >= 0`
/// - SuperToken solvent: `availableBalance + max(0, totalDeposit - owedDeposit) >= 0`
///   (`isAccountSolvent`). With owedDeposit > 0 these can diverge: SuperToken-insolvent
///   while still deposit-covered for liquidation (no bailout).
contract SolvencyLiquidationTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;
    using SafeCast for uint256;

    /// @dev Dominant/minor ratio so warping past minor-deposit coverage still leaves
    ///      the account globally deposit-covered.
    uint256 internal constant MIN_DOMINANT_FLOW_RATE_RATIO = 100;
    uint256 internal constant MIN_MINOR_FLOW_RATE = 1_000_000_000_000;

    struct AccountSnapshot {
        int256 availableBalance;
        uint256 totalDeposit;
        uint256 totalOwedDeposit;
        /// @dev `max(0, totalDeposit - owedDeposit)` — SuperToken solvency buffer only.
        uint256 solvencyBuffer;
        uint256 totalOutflowRate;
    }

    struct AppOwedDepositScenario {
        OwedDepositSuperApp app;
        ISuperfluidPool pool;
        AccountSnapshot snap;
        uint256 cfaDeposit;
        uint256 gdaDeposit;
    }

    struct BalancePair {
        int256 reward;
        int256 liquidator;
    }

    constructor() FoundrySuperfluidTester(10) { }

    function _solvencyBuffer(uint256 totalDeposit, uint256 totalOwedDeposit) internal pure returns (uint256) {
        return totalDeposit > totalOwedDeposit ? totalDeposit - totalOwedDeposit : 0;
    }

    function _snapshot(address account) internal view returns (AccountSnapshot memory snap) {
        (snap.availableBalance, snap.totalDeposit, snap.totalOwedDeposit,) = superToken.realtimeBalanceOfNow(account);
        snap.solvencyBuffer = _solvencyBuffer(snap.totalDeposit, snap.totalOwedDeposit);
        int96 netFlowRate = superToken.getNetFlowRate(account);
        if (netFlowRate < 0) {
            snap.totalOutflowRate = uint256(uint96(-netFlowRate));
        }
    }

    function _balances(address rewardAccount, address liquidator) internal view returns (BalancePair memory b) {
        (b.reward,,,) = superToken.realtimeBalanceOfNow(rewardAccount);
        (b.liquidator,,,) = superToken.realtimeBalanceOfNow(liquidator);
    }

    function _rewardAccount() internal view returns (address) {
        return sf.governance.getRewardAddress(sf.host, superToken);
    }

    function _helperBoundValidFlowRate(int96 seed) internal pure returns (int96 flowRate) {
        flowRate = int96(uint96(bound(uint256(int256(seed)), MIN_MINOR_FLOW_RATE, uint256(type(uint64).max))));
    }

    function _helperLiquidateGDAFlow(address liquidator, address sender, ISuperfluidPool pool) internal {
        vm.startPrank(liquidator);
        sf.host.callAgreement(
            sf.gda, abi.encodeCall(sf.gda.distributeFlow, (superToken, sender, pool, 0, new bytes(0))), new bytes(0)
        );
        vm.stopPrank();
    }

    function _helperLiquidateCFAFlow(address liquidator, address sender, address receiver) internal {
        vm.startPrank(liquidator);
        superToken.deleteFlow(sender, receiver);
        vm.stopPrank();
    }

    function _helperBoundDominantMinorFlowRates(int96 dominantSeed, int96 minorSeed)
        internal
        pure
        returns (int96 dominant, int96 minor)
    {
        uint256 maxFlowRate = uint256(type(uint64).max);
        uint256 dominantU =
            bound(uint256(int256(dominantSeed)), MIN_DOMINANT_FLOW_RATE_RATIO * MIN_MINOR_FLOW_RATE, maxFlowRate);
        uint256 minorU =
            bound(uint256(int256(minorSeed)), MIN_MINOR_FLOW_RATE, dominantU / MIN_DOMINANT_FLOW_RATE_RATIO);
        dominant = int96(uint96(dominantU));
        minor = int96(uint96(minorU));
    }

    /// @dev CFA to carol + GDA to a pool (bob member); clears Alice's spendable balance.
    function _helperSetupAliceCfaAndGdaOutflows(int96 cfaFlowRate, int96 gdaFlowRate)
        internal
        returns (ISuperfluidPool pool, uint256 cfaDeposit, uint256 gdaDeposit, uint256 totalOutflowRate)
    {
        pool = _helperCreatePool(superToken, alice, alice, false, poolConfig);
        _helperConnectPool(bob, superToken, pool);
        _helperUpdateMemberUnits(pool, alice, bob, 1);
        _helperCreateFlow(superToken, alice, carol, cfaFlowRate);
        _helperDistributeFlow(superToken, alice, alice, pool, gdaFlowRate);

        uint256 totalDeposit;
        (, totalDeposit,,) = superToken.realtimeBalanceOfNow(alice);
        cfaDeposit = _helperGetAccountFlowInfo(superToken, alice).deposit;
        gdaDeposit = totalDeposit - cfaDeposit;
        totalOutflowRate = uint256(uint96(-superToken.getNetFlowRate(alice)));

        vm.startPrank(alice);
        superToken.transfer(dan, superToken.balanceOf(alice));
        vm.stopPrank();
    }

    /// @dev Super App with inbound CFA (app credit / OD), partial outbound CFA, and GDA.
    ///      Outbound is in (0, inflow/2] so OD is strictly below inbound credit capacity.
    function _helperSetupAppOwedDepositScenario(int96 inflowSeed, int96 outboundSeed, int96 gdaSeed)
        internal
        returns (AppOwedDepositScenario memory scenario)
    {
        uint256 maxFlowRate = uint256(type(uint64).max);
        uint256 maxInflow = maxFlowRate / 2;
        int96 inflowRate = int96(uint96(bound(uint256(int256(inflowSeed)), MIN_MINOR_FLOW_RATE, maxInflow)));
        uint256 inflowU = uint256(uint96(inflowRate));
        uint256 outboundU = bound(uint256(int256(outboundSeed)), 1, inflowU / 2 == 0 ? 1 : inflowU / 2);
        int96 outboundRate = int96(uint96(outboundU));

        // Negative net flow after emptying; keep a non-empty window where SuperToken is
        // insolvent (solvency buffer exhausted) but totalDeposit still covers.
        uint256 minGda = inflowU > outboundU ? inflowU - outboundU + MIN_MINOR_FLOW_RATE : MIN_MINOR_FLOW_RATE;
        uint256 maxGda = minGda + outboundU;
        if (maxGda > maxFlowRate) maxGda = maxFlowRate;
        int96 gdaFlowRate = int96(uint96(bound(uint256(int256(gdaSeed)), minGda, maxGda)));

        scenario.app = new OwedDepositSuperApp(sf.host, carol);
        _addAccount(address(scenario.app));
        scenario.app.setOutboundFlowRate(outboundRate);

        scenario.pool = _helperCreatePool(superToken, alice, alice, false, poolConfig);
        _helperConnectPool(bob, superToken, scenario.pool);
        _helperUpdateMemberUnits(scenario.pool, alice, bob, 1);

        vm.startPrank(alice);
        superToken.transfer(address(scenario.app), 1e24);
        superToken.createFlow(address(scenario.app), inflowRate);
        vm.stopPrank();

        scenario.app.startDistributionFlow(superToken, scenario.pool, gdaFlowRate);
        uint256 inflowDeposit;
        (,, inflowDeposit,) = superToken.getFlowInfo(alice, address(scenario.app));
        (,, scenario.cfaDeposit,) = superToken.getFlowInfo(address(scenario.app), carol);
        (,, scenario.gdaDeposit) = sf.gda.getFlow(superToken, address(scenario.app), scenario.pool);

        scenario.app.transferAll(superToken, dan);
        scenario.snap = _snapshot(address(scenario.app));
        assertGt(scenario.snap.totalOwedDeposit, 0, "expected owed deposit");
        assertGt(scenario.snap.totalOutflowRate, 0, "expected net outflow");
        assertGt(scenario.snap.totalDeposit, scenario.snap.solvencyBuffer, "OD should shrink solvency buffer");
        assertLt(scenario.snap.totalOwedDeposit, inflowDeposit, "partial OD expected");
    }

    /// @dev CFA-only Super App: inbound CFA creates OD; larger outbound CFA creates net drain.
    function _helperSetupPureCFAAppCreditScenario() internal returns (AppOwedDepositScenario memory scenario) {
        int96 inflowRate = 100_000_000_000_000;
        int96 outboundRate = 150_000_000_000_000;

        scenario.app = new OwedDepositSuperApp(sf.host, carol);
        _addAccount(address(scenario.app));
        scenario.app.setOutboundFlowRate(outboundRate);

        vm.startPrank(alice);
        superToken.transfer(address(scenario.app), 1e24);
        superToken.createFlow(address(scenario.app), inflowRate);
        vm.stopPrank();

        (,, scenario.cfaDeposit,) = superToken.getFlowInfo(address(scenario.app), carol);

        scenario.app.transferAll(superToken, dan);
        scenario.snap = _snapshot(address(scenario.app));
        assertGt(scenario.snap.totalOwedDeposit, 0, "expected owed deposit");
        assertGt(scenario.snap.totalDeposit, scenario.snap.solvencyBuffer, "OD should shrink solvency buffer");
        assertGt(scenario.snap.totalOutflowRate, 0, "expected CFA-only net outflow");
    }

    /// @dev Warp into the deposit-covered critical window, capped to stay patrician.
    function _warpSecondsIntoCoverageWindow(AccountSnapshot memory snap, uint256 warpSeed) internal {
        require(snap.totalDeposit > 0 && snap.totalOutflowRate > 0, "coverage window requires buffer");
        uint256 maxCoveredSeconds = snap.totalDeposit / snap.totalOutflowRate;
        require(maxCoveredSeconds > 0, "total deposit too small for coverage window");

        (, uint256 patricianPeriod) = sf.governance.getPPPConfig(sf.host, superToken);
        // Patrician uses deposit/liquidationPeriod as implied outflow; wall-clock coverage can exceed
        // that window when inflows offset net drain. Cap so reward stays with the reward account.
        uint256 maxWarp = maxCoveredSeconds;
        if (patricianPeriod > 0 && patricianPeriod - 1 < maxWarp) {
            maxWarp = patricianPeriod - 1;
        }
        require(maxWarp > 0, "patrician coverage window empty");

        uint256 maxSafeWarp = type(uint32).max - block.timestamp - 1;
        if (maxWarp > maxSafeWarp) maxWarp = maxSafeWarp;
        vm.warp(block.timestamp + bound(warpSeed, 1, maxWarp));
    }

    function _warpToInsolvency(AccountSnapshot memory snap) internal {
        require(snap.totalOutflowRate > 0, "insolvency warp requires outflow");
        uint256 warpSeconds = snap.totalDeposit / snap.totalOutflowRate + 1;
        uint256 maxSafeWarp = type(uint32).max - block.timestamp - 1;
        require(warpSeconds <= maxSafeWarp, "warp exceeds uint32 timestamp domain");
        vm.warp(block.timestamp + warpSeconds);
    }

    /// @dev Past SuperToken solvency (`AB + solvencyBuffer < 0`) while still deposit-covered
    ///      for CFA/GDA (`AB + totalDeposit >= 0`). Requires owedDeposit > 0.
    function _warpPastSolvencyBufferWhileDepositCovered(AccountSnapshot memory snap) internal {
        require(snap.totalOutflowRate > 0, "warp requires outflow");
        require(snap.totalDeposit > snap.solvencyBuffer, "requires owed deposit");
        uint256 solvencyCoveredSeconds = snap.solvencyBuffer / snap.totalOutflowRate;
        uint256 depositCoveredSeconds = snap.totalDeposit / snap.totalOutflowRate;
        vm.assume(depositCoveredSeconds > solvencyCoveredSeconds);
        uint256 warpSeconds = solvencyCoveredSeconds + 1;
        uint256 maxSafeWarp = type(uint32).max - block.timestamp - 1;
        vm.assume(warpSeconds <= maxSafeWarp);
        vm.warp(block.timestamp + warpSeconds);
    }

    function _expectedCriticalReward(uint256 singleDeposit, AccountSnapshot memory snap)
        internal
        pure
        returns (int256)
    {
        return singleDeposit.toInt256() * (snap.availableBalance + snap.totalDeposit.toInt256())
            / snap.totalDeposit.toInt256();
    }

    function _assertCriticalAndCovered(AccountSnapshot memory snap) internal pure {
        assertLt(snap.availableBalance, 0, "critical");
        assertGe(snap.availableBalance + snap.totalDeposit.toInt256(), 0, "deposit-covered");
    }

    function _assertCriticalAndInsolvent(AccountSnapshot memory snap) internal pure {
        assertLt(snap.availableBalance, 0, "critical");
        assertLt(snap.availableBalance + snap.totalDeposit.toInt256(), 0, "deposit-uncovered");
    }

    function _assertDepositCoveredButSuperTokenInsolvent(AccountSnapshot memory snap) internal pure {
        assertLt(snap.availableBalance + snap.solvencyBuffer.toInt256(), 0, "SuperToken insolvent");
        assertGe(snap.availableBalance + snap.totalDeposit.toInt256(), 0, "still deposit-covered");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Cross-agreement
    //////////////////////////////////////////////////////////////////////////*/

    function testRevertGDALiquidateCriticalSenderWithoutGDAFlow(PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        vm.startPrank(alice);
        superToken.createFlow(bob, 100_000_000_000_000);
        superToken.transfer(dan, superToken.balanceOf(alice));
        vm.stopPrank();

        _helperWarpToCritical(superToken, alice, 1);

        vm.startPrank(carol);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_FLOW_DOES_NOT_EXIST.selector);
        sf.host.callAgreement(
            sf.gda, abi.encodeCall(sf.gda.distributeFlow, (superToken, alice, pool, 0, new bytes(0))), new bytes(0)
        );
        vm.stopPrank();
    }

    function testGDARewardAccountNotDebitedWhenAccountGloballyDepositCovered(int96 cfaFlowRate, int96 gdaFlowRate)
        public
    {
        (cfaFlowRate, gdaFlowRate) = _helperBoundDominantMinorFlowRates(cfaFlowRate, gdaFlowRate);
        (ISuperfluidPool pool,, uint256 gdaDeposit, uint256 totalOutflowRate) =
            _helperSetupAliceCfaAndGdaOutflows(cfaFlowRate, gdaFlowRate);

        vm.warp(block.timestamp + gdaDeposit / totalOutflowRate + 1);

        AccountSnapshot memory snap = _snapshot(alice);
        _assertCriticalAndCovered(snap);
        assertLt(gdaDeposit.toInt256(), -snap.availableBalance, "GDA deposit alone should not cover");
        (bool isPatricianPeriod,) = sf.gda.isPatricianPeriodNow(superToken, alice);
        assertTrue(isPatricianPeriod, "patrician");

        int256 expectedReward = _expectedCriticalReward(gdaDeposit, snap);
        address rewardAccount = _rewardAccount();
        BalancePair memory beforeBalances = _balances(rewardAccount, eve);

        _helperLiquidateGDAFlow(eve, alice, pool);

        BalancePair memory afterBalances = _balances(rewardAccount, eve);
        assertEq(afterBalances.reward, beforeBalances.reward + expectedReward, "incorrect GDA patrician reward");
        assertEq(afterBalances.liquidator, beforeBalances.liquidator, "liquidator should not receive patrician reward");
    }

    function testGDAGloballyCoveredPlebRewardGoesToLiquidator() public {
        (ISuperfluidPool pool,, uint256 gdaDeposit,) =
            _helperSetupAliceCfaAndGdaOutflows(200_000_000_000_000, 100_000_000_000_000);
        (, uint256 patricianPeriod) = sf.governance.getPPPConfig(sf.host, superToken);
        vm.warp(block.timestamp + patricianPeriod + 1);

        AccountSnapshot memory snap = _snapshot(alice);
        _assertCriticalAndCovered(snap);
        (bool isPatricianPeriod,) = sf.gda.isPatricianPeriodNow(superToken, alice);
        assertFalse(isPatricianPeriod, "pleb");

        int256 expectedReward = _expectedCriticalReward(gdaDeposit, snap);
        address rewardAccount = _rewardAccount();
        BalancePair memory beforeBalances = _balances(rewardAccount, eve);

        _helperLiquidateGDAFlow(eve, alice, pool);

        BalancePair memory afterBalances = _balances(rewardAccount, eve);
        assertEq(afterBalances.reward, beforeBalances.reward, "reward account should not receive pleb reward");
        assertEq(afterBalances.liquidator, beforeBalances.liquidator + expectedReward, "incorrect GDA pleb reward");
    }

    function testGDARewardAccountDebitedWhenAccountGloballyInsolvent(int96 cfaSeed, int96 gdaSeed) public {
        (ISuperfluidPool pool,, uint256 gdaDeposit,) =
            _helperSetupAliceCfaAndGdaOutflows(_helperBoundValidFlowRate(cfaSeed), _helperBoundValidFlowRate(gdaSeed));
        _warpToInsolvency(_snapshot(alice));

        AccountSnapshot memory snap = _snapshot(alice);
        _assertCriticalAndInsolvent(snap);
        int256 bailoutAmount = -(snap.availableBalance + snap.totalDeposit.toInt256());

        address rewardAccount = _rewardAccount();
        BalancePair memory beforeBalances = _balances(rewardAccount, eve);

        _helperLiquidateGDAFlow(eve, alice, pool);

        BalancePair memory afterBalances = _balances(rewardAccount, eve);
        (int256 senderAfter,,,) = superToken.realtimeBalanceOfNow(alice);
        assertEq(
            afterBalances.reward,
            beforeBalances.reward - gdaDeposit.toInt256() - bailoutAmount,
            "incorrect GDA bailout debit"
        );
        assertEq(
            afterBalances.liquidator,
            beforeBalances.liquidator + gdaDeposit.toInt256(),
            "incorrect GDA liquidator reward"
        );
        assertEq(senderAfter, gdaDeposit.toInt256() - snap.totalDeposit.toInt256(), "incorrect sender bailout AB");
        assertTrue(superToken.isAccountSolventNow(alice), "GDA bailout should restore solvency");
    }

    function testCFARewardAccountNotDebitedWhenAccountGloballyDepositCovered(int96 cfaFlowRate, int96 gdaFlowRate)
        public
    {
        (gdaFlowRate, cfaFlowRate) = _helperBoundDominantMinorFlowRates(gdaFlowRate, cfaFlowRate);
        (, uint256 cfaDeposit,, uint256 totalOutflowRate) = _helperSetupAliceCfaAndGdaOutflows(cfaFlowRate, gdaFlowRate);

        vm.warp(block.timestamp + cfaDeposit / totalOutflowRate + 1);

        AccountSnapshot memory snap = _snapshot(alice);
        _assertCriticalAndCovered(snap);
        assertLt(cfaDeposit.toInt256(), -snap.availableBalance, "CFA deposit alone should not cover");
        (bool isPatricianPeriod,) = sf.cfa.isPatricianPeriodNow(superToken, alice);
        assertTrue(isPatricianPeriod, "patrician");

        int256 expectedReward = _expectedCriticalReward(cfaDeposit, snap);
        address rewardAccount = _rewardAccount();
        BalancePair memory beforeBalances = _balances(rewardAccount, eve);

        _helperLiquidateCFAFlow(eve, alice, carol);

        BalancePair memory afterBalances = _balances(rewardAccount, eve);
        assertEq(afterBalances.reward, beforeBalances.reward + expectedReward, "incorrect CFA patrician reward");
        assertEq(afterBalances.liquidator, beforeBalances.liquidator, "liquidator should not receive patrician reward");
    }

    function testCFAGloballyCoveredPlebRewardGoesToLiquidator() public {
        (, uint256 cfaDeposit,,) = _helperSetupAliceCfaAndGdaOutflows(100_000_000_000_000, 200_000_000_000_000);
        (, uint256 patricianPeriod) = sf.governance.getPPPConfig(sf.host, superToken);
        vm.warp(block.timestamp + patricianPeriod + 1);

        AccountSnapshot memory snap = _snapshot(alice);
        _assertCriticalAndCovered(snap);
        (bool isPatricianPeriod,) = sf.cfa.isPatricianPeriodNow(superToken, alice);
        assertFalse(isPatricianPeriod, "pleb");

        int256 expectedReward = _expectedCriticalReward(cfaDeposit, snap);
        address rewardAccount = _rewardAccount();
        BalancePair memory beforeBalances = _balances(rewardAccount, eve);

        _helperLiquidateCFAFlow(eve, alice, carol);

        BalancePair memory afterBalances = _balances(rewardAccount, eve);
        assertEq(afterBalances.reward, beforeBalances.reward, "reward account should not receive pleb reward");
        assertEq(afterBalances.liquidator, beforeBalances.liquidator + expectedReward, "incorrect CFA pleb reward");
    }

    function testCFARewardAccountDebitedWhenAccountGloballyInsolvent(int96 cfaSeed, int96 gdaSeed) public {
        (, uint256 cfaDeposit,,) =
            _helperSetupAliceCfaAndGdaOutflows(_helperBoundValidFlowRate(cfaSeed), _helperBoundValidFlowRate(gdaSeed));
        _warpToInsolvency(_snapshot(alice));

        AccountSnapshot memory snap = _snapshot(alice);
        _assertCriticalAndInsolvent(snap);
        int256 bailoutAmount = -(snap.availableBalance + snap.totalDeposit.toInt256());

        address rewardAccount = _rewardAccount();
        BalancePair memory beforeBalances = _balances(rewardAccount, eve);

        _helperLiquidateCFAFlow(eve, alice, carol);

        BalancePair memory afterBalances = _balances(rewardAccount, eve);
        (int256 senderAfter,,,) = superToken.realtimeBalanceOfNow(alice);
        assertEq(
            afterBalances.reward,
            beforeBalances.reward - cfaDeposit.toInt256() - bailoutAmount,
            "incorrect CFA bailout debit"
        );
        assertEq(
            afterBalances.liquidator,
            beforeBalances.liquidator + cfaDeposit.toInt256(),
            "incorrect CFA liquidator reward"
        );
        assertEq(senderAfter, cfaDeposit.toInt256() - snap.totalDeposit.toInt256(), "incorrect sender bailout AB");
        assertTrue(superToken.isAccountSolventNow(alice), "CFA bailout should restore solvency");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Multi-flow reward share
    //////////////////////////////////////////////////////////////////////////*/

    function testCFAMultiFlowCriticalRewardUsesAccountTotalDeposit(
        int96 rate1Seed,
        int96 rate2Seed,
        uint256 warpSeed
    ) public {
        _helperCreateFlow(superToken, alice, carol, _helperBoundValidFlowRate(rate1Seed));
        _helperCreateFlow(superToken, alice, frank, _helperBoundValidFlowRate(rate2Seed));
        vm.startPrank(alice);
        superToken.transfer(dan, superToken.balanceOf(alice));
        vm.stopPrank();

        _warpSecondsIntoCoverageWindow(_snapshot(alice), warpSeed);

        AccountSnapshot memory snap = _snapshot(alice);
        _assertCriticalAndCovered(snap);
        (,, uint256 flow1Deposit,) = superToken.getFlowInfo(alice, carol);

        int256 expectedReward = _expectedCriticalReward(flow1Deposit, snap);
        address rewardAccount = _rewardAccount();
        (int256 rewardBefore,,,) = superToken.realtimeBalanceOfNow(rewardAccount);

        _helperLiquidateCFAFlow(eve, alice, carol);

        (int256 rewardAfter,,,) = superToken.realtimeBalanceOfNow(rewardAccount);
        assertEq(rewardAfter, rewardBefore + expectedReward, "incorrect multi-flow CFA reward share");
        assertGt(superToken.getFlowRate(alice, frank), 0, "second CFA flow should remain open");
    }

    function testGDAMultiFlowCriticalRewardUsesAccountTotalDeposit(
        int96 rate1Seed,
        int96 rate2Seed,
        uint256 warpSeed
    ) public {
        int96 rate1 = _helperBoundValidFlowRate(rate1Seed);
        int96 rate2 = _helperBoundValidFlowRate(rate2Seed);

        ISuperfluidPool pool1 = _helperCreatePool(superToken, alice, alice, false, poolConfig);
        ISuperfluidPool pool2 = _helperCreatePool(superToken, alice, alice, false, poolConfig);
        _helperConnectPool(bob, superToken, pool1);
        _helperConnectPool(bob, superToken, pool2);
        _helperUpdateMemberUnits(pool1, alice, bob, 1);
        _helperUpdateMemberUnits(pool2, alice, bob, 1);
        _helperDistributeFlow(superToken, alice, alice, pool1, rate1);
        _helperDistributeFlow(superToken, alice, alice, pool2, rate2);

        vm.startPrank(alice);
        superToken.transfer(dan, superToken.balanceOf(alice));
        vm.stopPrank();

        _warpSecondsIntoCoverageWindow(_snapshot(alice), warpSeed);

        AccountSnapshot memory snap = _snapshot(alice);
        _assertCriticalAndCovered(snap);
        (,, uint256 flow1Deposit) = sf.gda.getFlow(superToken, alice, pool1);

        int256 expectedReward = _expectedCriticalReward(flow1Deposit, snap);
        address rewardAccount = _rewardAccount();
        (int256 rewardBefore,,,) = superToken.realtimeBalanceOfNow(rewardAccount);

        _helperLiquidateGDAFlow(eve, alice, pool1);

        (int256 rewardAfter,,,) = superToken.realtimeBalanceOfNow(rewardAccount);
        assertEq(rewardAfter, rewardBefore + expectedReward, "incorrect multi-flow GDA reward share");
        assertGt(sf.gda.getFlowRate(superToken, alice, pool2), 0, "second GDA flow should remain open");
    }

    /*//////////////////////////////////////////////////////////////////////////
                    SuperToken insolvency vs CFA/GDA deposit coverage
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev SuperToken insolvent via owedDeposit, but GDA liquidation stays deposit-covered
    ///      (no reward-account bailout).
    function testAppGDACoveredWhenOwedDepositMakesAccountSuperTokenInsolvent(
        int96 inflowSeed,
        int96 outboundSeed,
        int96 gdaSeed
    ) public {
        AppOwedDepositScenario memory scenario = _helperSetupAppOwedDepositScenario(inflowSeed, outboundSeed, gdaSeed);

        _warpPastSolvencyBufferWhileDepositCovered(scenario.snap);
        AccountSnapshot memory snap = _snapshot(address(scenario.app));
        _assertDepositCoveredButSuperTokenInsolvent(snap);

        int256 expectedReward = _expectedCriticalReward(scenario.gdaDeposit, snap);
        address rewardAccount = _rewardAccount();
        BalancePair memory beforeBalances = _balances(rewardAccount, eve);

        _helperLiquidateGDAFlow(eve, address(scenario.app), scenario.pool);

        BalancePair memory afterBalances = _balances(rewardAccount, eve);
        assertEq(afterBalances.reward, beforeBalances.reward, "no bailout while deposit-covered");
        assertEq(
            afterBalances.liquidator,
            beforeBalances.liquidator + expectedReward,
            "GDA covered reward despite SuperToken insolvency"
        );
    }

    /// @dev Same split for a CFA-only Super App (minimal setup).
    function testPureCFACoveredWhenAppCreditMakesAccountSuperTokenInsolvent() public {
        AppOwedDepositScenario memory scenario = _helperSetupPureCFAAppCreditScenario();

        _warpPastSolvencyBufferWhileDepositCovered(scenario.snap);
        AccountSnapshot memory snap = _snapshot(address(scenario.app));
        assertLt(snap.availableBalance, 0, "critical");
        _assertDepositCoveredButSuperTokenInsolvent(snap);

        int256 expectedReward = _expectedCriticalReward(scenario.cfaDeposit, snap);
        address rewardAccount = _rewardAccount();
        BalancePair memory beforeBalances = _balances(rewardAccount, eve);

        _helperLiquidateCFAFlow(eve, address(scenario.app), carol);

        BalancePair memory afterBalances = _balances(rewardAccount, eve);
        assertEq(afterBalances.reward, beforeBalances.reward, "no bailout while deposit-covered");
        assertEq(
            afterBalances.liquidator,
            beforeBalances.liquidator + expectedReward,
            "pure CFA covered reward despite SuperToken insolvency"
        );
    }
}
