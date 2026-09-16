// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";
import {
    ISuperfluid,
    ISuperApp,
    ISuperToken,
    SuperAppDefinitions
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { BatchLiquidator } from "../../../contracts/utils/BatchLiquidator.sol";

/// @dev Create/update are NOOP. Terminate before/after share one stipend.
contract TerminateBudgetApp is ISuperApp {
    uint256 public immutable beforeLeave;
    uint256 public immutable afterBurn;
    uint256 public afterGas;

    constructor(ISuperfluid host, uint256 beforeLeave_, uint256 afterBurn_) {
        beforeLeave = beforeLeave_;
        afterBurn = afterBurn_;
        host.registerApp(
            SuperAppDefinitions.APP_LEVEL_FINAL
                | SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP
                | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP
        );
    }

    function beforeAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        pure
        returns (bytes memory)
    {
        return "";
    }

    function afterAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external
        pure
        returns (bytes memory)
    {
        return ctx;
    }

    function beforeAgreementUpdated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        pure
        returns (bytes memory)
    {
        return "";
    }

    function afterAgreementUpdated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external
        pure
        returns (bytes memory)
    {
        return ctx;
    }

    function beforeAgreementTerminated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        view
        returns (bytes memory)
    {
        uint256 leave = beforeLeave;
        if (leave > 0) {
            while (gasleft() > leave) { }
        }
        return "";
    }

    function afterAgreementTerminated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external
        returns (bytes memory)
    {
        afterGas = gasleft();
        uint256 burn = afterBurn;
        if (burn > 0) {
            uint256 start = gasleft();
            while (start - gasleft() < burn) { }
        }
        return ctx;
    }
}

/// @dev Third-party CFA liquidation against a SuperApp whose terminate hooks share one stipend.
contract SharedCallbackBudgetLiquidationTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    int96 internal constant FLOW_RATE = 1e9;
    uint256 internal constant EXHAUST_BEFORE_LEAVE = 50_000;
    uint256 internal constant HEAVY_BEFORE_LEAVE = 500_000;
    uint256 internal constant AFTER_EXCEEDS_BURN = 700_000;
    uint256 internal constant AFTER_EXHAUST_BURN = 100_000;
    /// Enough for EIP-150 to deliver CALLBACK_GAS_LIMIT plus Host/liquidator overhead.
    uint256 internal constant LIQUIDATOR_TX_GAS = 8_000_000;

    constructor() FoundrySuperfluidTester(3) { }

    function liquidateAsBob(address app) external {
        vm.startPrank(bob);
        superToken.deleteFlow(alice, app);
        vm.stopPrank();
    }

    function test_honestCheap_liquidationClosesWithoutJail() public {
        TerminateBudgetApp app = _deployTerminateApp(0, 0);
        _openAndWarpCritical(address(app));

        bool ok = _liquidateWithGas(address(app), LIQUIDATOR_TX_GAS);
        assertTrue(ok, "honest liquidation must succeed");
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "honest terminate must not jail");
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow must close");
        assertGt(app.afterGas(), 2_500_000, "NOOP before leaves a full terminate-after stipend");
    }

    function test_heavyBefore_afterExceedsRemainder_liquidationJailsAndCloses() public {
        TerminateBudgetApp app = _deployTerminateApp(HEAVY_BEFORE_LEAVE, AFTER_EXCEEDS_BURN);
        _openAndWarpCritical(address(app));

        bool ok = _liquidateWithGas(address(app), LIQUIDATOR_TX_GAS);
        assertTrue(ok, "liquidation must close the flow even when after exceeds remainder");
        assertTrue(sf.host.isAppJailed(ISuperApp(address(app))), "after OOG on terminate must jail");
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow must close");
    }

    function test_exhaustBefore_liquidationJailsAndCloses() public {
        // Modest after work so remainder ~0 cannot complete the after-hook, while a
        // mistaken fresh stipend (3M) would still succeed and fail the jail assertion.
        TerminateBudgetApp app = _deployTerminateApp(EXHAUST_BEFORE_LEAVE, AFTER_EXHAUST_BURN);
        _openAndWarpCritical(address(app));

        bool ok = _liquidateWithGas(address(app), LIQUIDATOR_TX_GAS);
        assertTrue(ok, "liquidation must close the flow when after stipend is 0");
        assertTrue(sf.host.isAppJailed(ISuperApp(address(app))), "after failure on remainder 0 must jail");
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow must close");
    }

    function test_batchLiquidator_deleteFlow_honestClosesWithoutJail() public {
        TerminateBudgetApp app = _deployTerminateApp(0, 0);
        _openAndWarpCritical(address(app));

        vm.prank(bob);
        sf.batchLiquidator.deleteFlow(
            address(superToken),
            _cfaLiq(alice, address(app))
        );

        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "honest batch liquidate must not jail");
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow must close");
    }

    function test_batchLiquidator_deleteFlows_oneItem_heavyAfterJailsAndCloses() public {
        TerminateBudgetApp app = _deployTerminateApp(HEAVY_BEFORE_LEAVE, AFTER_EXCEEDS_BURN);
        _openAndWarpCritical(address(app));

        BatchLiquidator.FlowLiquidationData[] memory data = new BatchLiquidator.FlowLiquidationData[](1);
        data[0] = _cfaLiq(alice, address(app));
        vm.prank(bob);
        sf.batchLiquidator.deleteFlows(address(superToken), data);

        assertTrue(sf.host.isAppJailed(ISuperApp(address(app))), "after OOG must jail");
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow must close");
    }

    function test_insolventBailout_honestClosesWithoutJail() public {
        TerminateBudgetApp app = _deployTerminateApp(0, 0);
        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);
        (uint256 liquidationPeriod,) = sf.governance.getPPPConfig(sf.host, superToken);
        // Clip-up of CFA deposits can cover a few extra seconds at this flow rate.
        _helperWarpToInsolvency(superToken, alice, liquidationPeriod, 1 hours);
        assertFalse(superToken.isAccountSolventNow(alice), "setup: alice must be insolvent");

        bool ok = _liquidateWithGas(address(app), LIQUIDATOR_TX_GAS);
        assertTrue(ok, "insolvent liquidation must succeed");
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "honest terminate must not jail");
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow must close");
    }

    /// forge-config: default.fuzz.runs = 64
    /// forge-config: ci.fuzz.runs = 64
    function testFuzz_terminateBudgetSplit(uint8 beforeKind, bool afterExceeds) public {
        beforeKind = uint8(bound(beforeKind, 0, 2));
        uint256 beforeLeave = beforeKind == 1 ? HEAVY_BEFORE_LEAVE : (beforeKind == 2 ? EXHAUST_BEFORE_LEAVE : 0);
        uint256 afterBurn = afterExceeds ? AFTER_EXCEEDS_BURN : 0;
        if (beforeKind == 2 && afterBurn == 0) {
            afterBurn = AFTER_EXHAUST_BURN;
        }
        bool expectJail = beforeKind == 2 || (beforeKind == 1 && afterExceeds);

        TerminateBudgetApp app = _deployTerminateApp(beforeLeave, afterBurn);
        _openAndWarpCritical(address(app));

        bool ok = _liquidateWithGas(address(app), LIQUIDATOR_TX_GAS);
        assertTrue(ok, "funded liquidation must not roll back");
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow must close");
        assertEq(sf.host.isAppJailed(ISuperApp(address(app))), expectJail, "jail only on after failure");
    }

    function _deployTerminateApp(uint256 beforeLeave, uint256 afterBurn) internal returns (TerminateBudgetApp app) {
        app = new TerminateBudgetApp(sf.host, beforeLeave, afterBurn);
        _addAccount(address(app));
    }

    function _openAndWarpCritical(address app) internal {
        _helperCreateFlow(superToken, alice, app, FLOW_RATE);
        _helperWarpToCritical(superToken, alice, 1);
        assertTrue(superToken.isAccountCriticalNow(alice), "setup: alice must be critical");
    }

    function _liquidateWithGas(address app, uint256 executionBudget) internal returns (bool ok) {
        (ok,) = address(this).call{gas: executionBudget}(abi.encodeCall(this.liquidateAsBob, (app)));
    }

    function _cfaLiq(address sender, address receiver)
        internal
        pure
        returns (BatchLiquidator.FlowLiquidationData memory)
    {
        return BatchLiquidator.FlowLiquidationData({
            agreementOperation: BatchLiquidator.FlowType.ConstantFlowAgreement,
            sender: sender,
            receiver: receiver
        });
    }
}
