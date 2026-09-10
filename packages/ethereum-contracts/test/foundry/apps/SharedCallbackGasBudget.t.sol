// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "../FoundrySuperfluidTester.t.sol";
import {
    ISuperfluid,
    ISuperToken,
    ISuperApp,
    SuperAppDefinitions
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";

contract CallbackGasBudgetApp is ISuperApp {
    enum BeforeCreatedMode {
        Noop,
        Cheap,
        Heavy
    }

    BeforeCreatedMode public immutable beforeCreatedMode;
    uint256 public afterCreatedGas;

    constructor(ISuperfluid host, BeforeCreatedMode beforeCreatedMode_) {
        beforeCreatedMode = beforeCreatedMode_;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL
            | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
            | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP;
        if (beforeCreatedMode_ == BeforeCreatedMode.Noop) {
            configWord |= SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;
        }
        host.registerApp(configWord);
    }

    function beforeAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        view
        returns (bytes memory)
    {
        if (beforeCreatedMode == BeforeCreatedMode.Heavy) {
            while (gasleft() > 500_000) { }
        }
        return "";
    }

    function afterAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external
        returns (bytes memory)
    {
        afterCreatedGas = gasleft();
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
        pure
        returns (bytes memory)
    {
        return "";
    }

    function afterAgreementTerminated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external
        pure
        returns (bytes memory)
    {
        return ctx;
    }
}

/// @dev One before-hook consumes most of its budget; enabled after-hooks need more than the remainder.
contract CallbackGasBudgetNoopApp is ISuperApp {
    bytes4 internal immutable _heavyBefore;
    uint256 public afterGas;

    constructor(ISuperfluid host, bytes4 heavyBefore, uint256 noopMask) {
        _heavyBefore = heavyBefore;
        host.registerApp(SuperAppDefinitions.APP_LEVEL_FINAL | noopMask);
    }

    function _before() internal view returns (bytes memory) {
        if (msg.sig == _heavyBefore) {
            while (gasleft() > 500_000) { }
        }
        return "";
    }

    function _after(bytes calldata ctx) internal returns (bytes memory) {
        uint256 start = gasleft();
        afterGas = start;
        while (start - gasleft() < 700_000) { }
        return ctx;
    }

    function beforeAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external view returns (bytes memory)
    {
        return _before();
    }

    function afterAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external returns (bytes memory)
    {
        return _after(ctx);
    }

    function beforeAgreementUpdated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external view returns (bytes memory)
    {
        return _before();
    }

    function afterAgreementUpdated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external returns (bytes memory)
    {
        return _after(ctx);
    }

    function beforeAgreementTerminated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external view returns (bytes memory)
    {
        return _before();
    }

    function afterAgreementTerminated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external returns (bytes memory)
    {
        return _after(ctx);
    }
}

contract SharedCallbackGasBudgetTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    int96 internal constant FLOW_RATE = 1e9;

    constructor() FoundrySuperfluidTester(3) { }

    function test_beforeCreatedNoop_afterGetsFullBudget() public {
        CallbackGasBudgetApp app = _deployApp(CallbackGasBudgetApp.BeforeCreatedMode.Noop);

        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);

        assertGt(app.afterCreatedGas(), 2_500_000, "NOOP before should leave the full callback budget");
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "app must not be jailed");
    }

    function test_cheapBeforeAndAfter_createFlowSucceeds() public {
        CallbackGasBudgetApp app = _deployApp(CallbackGasBudgetApp.BeforeCreatedMode.Cheap);

        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);

        assertEq(superToken.getFlowRate(alice, address(app)), FLOW_RATE, "flow should be open");
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "app must not be jailed");
    }

    function test_heavyBefore_reducesAfterBudget() public {
        CallbackGasBudgetApp app = _deployApp(CallbackGasBudgetApp.BeforeCreatedMode.Heavy);

        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);

        assertLt(app.afterCreatedGas(), 1_200_000, "after should receive only the remaining callback budget");
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "app must not be jailed");
    }

    function test_callbackBudgets_areIsolatedPerApp() public {
        CallbackGasBudgetApp heavyApp = _deployApp(CallbackGasBudgetApp.BeforeCreatedMode.Heavy);
        CallbackGasBudgetApp noopApp = _deployApp(CallbackGasBudgetApp.BeforeCreatedMode.Noop);

        _helperCreateFlow(superToken, alice, address(heavyApp), FLOW_RATE);
        _helperCreateFlow(superToken, alice, address(noopApp), FLOW_RATE);

        assertLt(heavyApp.afterCreatedGas(), 1_200_000, "heavy app should have a depleted after budget");
        assertGt(noopApp.afterCreatedGas(), 2_500_000, "other app should retain its full after budget");
    }

    function test_cheapTerminate_closesFlowWithoutJailing() public {
        CallbackGasBudgetApp app = _deployApp(CallbackGasBudgetApp.BeforeCreatedMode.Cheap);
        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);

        _helperDeleteFlow(superToken, alice, alice, address(app));

        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow should be closed");
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "app must not be jailed");
    }

    // Each test executes multiple Host operations in one transaction, as a batch/router can.
    // The before-only operation and the after-only operation must have independent budgets.
    function test_beforeOnlyCreate_doesNotReduceTerminateBudget() public {
        CallbackGasBudgetNoopApp app = new CallbackGasBudgetNoopApp(
            sf.host, ISuperApp.beforeAgreementCreated.selector,
            SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP
                | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
        );
        _addAccount(address(app));
        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);
        _helperDeleteFlow(superToken, alice, alice, address(app));
        _assertIndependentAfterBudget(app);
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow should be closed");
    }

    function test_beforeOnlyUpdate_doesNotReduceTerminateBudget() public {
        CallbackGasBudgetNoopApp app = new CallbackGasBudgetNoopApp(
            sf.host, ISuperApp.beforeAgreementUpdated.selector,
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
        );
        _addAccount(address(app));
        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);
        _helperUpdateFlow(superToken, alice, address(app), FLOW_RATE * 2);
        _helperDeleteFlow(superToken, alice, alice, address(app));
        _assertIndependentAfterBudget(app);
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow should be closed");
    }

    function test_beforeOnlyTerminate_doesNotReduceCreateBudget() public {
        CallbackGasBudgetNoopApp app = new CallbackGasBudgetNoopApp(
            sf.host, ISuperApp.beforeAgreementTerminated.selector,
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP
                | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP
        );
        _addAccount(address(app));
        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);
        _helperDeleteFlow(superToken, alice, alice, address(app));
        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);
        _assertIndependentAfterBudget(app);
        assertEq(superToken.getFlowRate(alice, address(app)), FLOW_RATE, "flow should be reopened");
    }

    function _assertIndependentAfterBudget(CallbackGasBudgetNoopApp app) internal view {
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "independent callback must not jail an honest app");
        assertGt(app.afterGas(), 2_500_000, "NOOP before should leave the full callback budget");
    }

    function _deployApp(CallbackGasBudgetApp.BeforeCreatedMode mode)
        internal
        returns (CallbackGasBudgetApp app)
    {
        app = new CallbackGasBudgetApp(sf.host, mode);
        _addAccount(address(app));
    }
}
