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

    function _deployApp(CallbackGasBudgetApp.BeforeCreatedMode mode)
        internal
        returns (CallbackGasBudgetApp app)
    {
        app = new CallbackGasBudgetApp(sf.host, mode);
        _addAccount(address(app));
    }
}
