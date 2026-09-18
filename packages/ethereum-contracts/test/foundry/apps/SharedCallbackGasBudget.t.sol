// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "../FoundrySuperfluidTester.t.sol";
import {
    ISuperfluid,
    ISuperToken,
    ISuperApp,
    SuperAppDefinitions
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { AgreementMock } from "../../../contracts/mocks/AgreementMock.t.sol";
import { AgreementLibrary } from "../../../contracts/agreements/AgreementLibrary.sol";
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
        return abi.encode(gasleft());
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
    /// Leave enough gas for the before-hook to return; 256 OOGs the return and reverts create.
    uint256 internal constant EXHAUST_BEFORE_LEAVE = 50_000;
    uint256 internal constant HEAVY_BEFORE_LEAVE = 500_000;

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

    /// @dev Exhaust the before-hook stipend (leave a few hundred gas to return). After is NOOP
    ///      so remainder 0 is discarded. The next after-only hook must still get a full budget.
    function test_zeroRemainder_isNotAFreshBudget() public {
        CallbackBudgetProbeApp app = _deployProbe({
            createBeforeNoop: false,
            createAfterNoop: true,
            terminateBeforeNoop: true,
            beforeLeave: EXHAUST_BEFORE_LEAVE
        });

        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);
        _helperDeleteFlow(superToken, alice, alice, address(app));

        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "discarded zero remainder must not jail");
        assertGt(app.lastAfterGas(), 2_500_000, "after-only terminate must not inherit remainder 0");
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow should be closed");
    }

    /// @dev Matching pair: before exhausts the stipend, after is enabled. Remainder 0
    ///      must not be treated as an absent budget (which would give after a full stipend).
    function test_exhaustMatchingPair_afterDoesNotGetFreshBudget() public {
        CallbackBudgetProbeApp app = _deployProbe({
            createBeforeNoop: false,
            createAfterNoop: false,
            terminateBeforeNoop: true,
            beforeLeave: EXHAUST_BEFORE_LEAVE
        });

        bool opened = _tryCreateFlow(address(app));
        if (opened) {
            assertLt(app.lastAfterGas(), 100_000, "after must see remainder ~0, not a fresh stipend");
            _helperDeleteFlow(superToken, alice, alice, address(app));
        } else {
            assertEq(superToken.getFlowRate(alice, address(app)), 0, "failed create leaves no flow");
        }
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "failed or starved create must not jail");
    }

    /// @dev Valid 2–3 operation templates. NOOP mask and before-hook workload vary.
    ///      After-hooks only record gasleft so honest apps stay inside the allowance.
    /// forge-config: default.fuzz.runs = 64
    /// forge-config: ci.fuzz.runs = 64
    function testFuzz_budgetSequence(
        uint8 template,
        uint8 beforeLeaveKind,
        bool createBeforeNoop,
        bool createAfterNoop,
        bool twoApps
    ) public {
        template = uint8(bound(template, 0, 1));
        beforeLeaveKind = uint8(bound(beforeLeaveKind, 0, 2));
        uint256 beforeLeave = _beforeLeaveForKind(beforeLeaveKind);

        CallbackBudgetProbeApp app = _deployProbe({
            createBeforeNoop: createBeforeNoop,
            createAfterNoop: createAfterNoop,
            terminateBeforeNoop: true,
            beforeLeave: createBeforeNoop ? 0 : beforeLeave
        });

        bool opened = _tryCreateFlow(address(app));
        if (!opened) {
            assertFalse(createAfterNoop, "create can fail only when after runs on an exhausted before");
            assertFalse(createBeforeNoop, "NOOP before cannot exhaust the stipend");
            assertEq(beforeLeaveKind, 2, "create can fail only on exhaust");
            assertEq(superToken.getFlowRate(alice, address(app)), 0, "failed create leaves no flow");
            assertLt(app.lastAfterGas(), 100_000, "remainder 0 is not a full after stipend");
        } else if (!createAfterNoop) {
            if (createBeforeNoop || beforeLeaveKind == 0) {
                assertGt(app.lastAfterGas(), 2_500_000, "cheap/NOOP before leaves a full after stipend");
            } else if (beforeLeaveKind == 1) {
                assertLt(app.lastAfterGas(), 1_200_000, "heavy before must shrink the after stipend");
            } else {
                assertLt(app.lastAfterGas(), 100_000, "exhaust before must leave ~0 after stipend");
            }
        }

        if (twoApps) {
            CallbackBudgetProbeApp other = _deployProbe({
                createBeforeNoop: true,
                createAfterNoop: false,
                terminateBeforeNoop: true,
                beforeLeave: 0
            });
            _helperCreateFlow(superToken, alice, address(other), FLOW_RATE);
            assertGt(other.lastAfterGas(), 2_500_000, "second app must get a full independent stipend");
            assertFalse(sf.host.isAppJailed(ISuperApp(address(other))), "second app must not be jailed");
            _helperDeleteFlow(superToken, alice, alice, address(other));
        }

        if (opened) {
            if (template == 1) {
                _helperUpdateFlow(superToken, alice, address(app), FLOW_RATE * 2);
            }
            _helperDeleteFlow(superToken, alice, alice, address(app));
            assertGt(app.lastAfterGas(), 2_500_000, "later after-only pair must start from a full stipend");
            assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "honest record-only after must not jail");
            assertEq(superToken.getFlowRate(alice, address(app)), 0, "flow should be closed");
        }
    }

    function helperCreateAsAlice(address app) external {
        _helperCreateFlow(superToken, alice, app, FLOW_RATE);
    }

    function _tryCreateFlow(address app) internal returns (bool opened) {
        try this.helperCreateAsAlice(app) {
            opened = true;
        } catch {
            opened = false;
        }
    }

    function _beforeLeaveForKind(uint8 kind) internal pure returns (uint256) {
        if (kind == 1) return HEAVY_BEFORE_LEAVE;
        if (kind == 2) return EXHAUST_BEFORE_LEAVE;
        return 0;
    }

    function _deployProbe(
        bool createBeforeNoop,
        bool createAfterNoop,
        bool terminateBeforeNoop,
        uint256 beforeLeave
    ) internal returns (CallbackBudgetProbeApp app) {
        uint256 noopMask = SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
            | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP;
        if (createBeforeNoop) noopMask |= SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;
        if (createAfterNoop) noopMask |= SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP;
        if (terminateBeforeNoop) noopMask |= SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;
        app = new CallbackBudgetProbeApp(sf.host, noopMask, beforeLeave);
        _addAccount(address(app));
    }
}

/// @dev Records after-hook gasleft. Optional before-hook burn until `gasleft() <= beforeLeave`.
contract CallbackBudgetProbeApp is ISuperApp {
    uint256 public immutable beforeLeave;
    uint256 public lastAfterGas;

    constructor(ISuperfluid host, uint256 noopMask, uint256 beforeLeave_) {
        beforeLeave = beforeLeave_;
        host.registerApp(SuperAppDefinitions.APP_LEVEL_FINAL | noopMask);
    }

    function _before() internal view returns (bytes memory) {
        uint256 leave = beforeLeave;
        if (leave > 0) {
            while (gasleft() > leave) { }
        }
        return "";
    }

    function _after(bytes calldata ctx) internal returns (bytes memory) {
        lastAfterGas = gasleft();
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


/// @dev Exercises the context-carried budget through the agreement helper and the real Host.
contract CallbackBudgetAgreement is AgreementMock {
    uint256 public remainingGas;
    uint256 public observedBeforeGas;

    constructor(address host) AgreementMock(host, keccak256("CallbackBudgetAgreement"), 1) { }

    function runBefore(ISuperApp app, bytes calldata ctx) external returns (bytes memory newCtx) {
        AgreementLibrary.CallbackInputs memory inputs = AgreementLibrary.createCallbackInputs(
            ISuperfluidToken(address(0)), address(app), bytes32(0), ""
        );
        inputs.noopBit = SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;
        bytes memory cbdata;
        (cbdata, newCtx) = AgreementLibrary.callAppBeforeCallback(inputs, ctx);
        remainingGas = ISuperfluid(msg.sender).decodeCtx(newCtx).callbackGasLeft;
        if (cbdata.length != 0) observedBeforeGas = abi.decode(cbdata, (uint256));
        return newCtx;
    }
}

/// @dev The Host starts every before-hook with its configured pair stipend.
contract ExplicitCallbackGasBudgetTest is FoundrySuperfluidTester {
    CallbackBudgetAgreement private _agreement;

    constructor() FoundrySuperfluidTester(3) { }

    function setUp() public override {
        super.setUp();
        CallbackBudgetAgreement implementation = new CallbackBudgetAgreement(address(sf.host));
        vm.prank(sf.governance.owner());
        sf.governance.registerAgreementClass(sf.host, address(implementation));
        _agreement = CallbackBudgetAgreement(address(sf.host.getAgreementClass(implementation.agreementType())));
    }

    function _runBefore(ISuperApp app) private {
        sf.host.callAgreement(_agreement, abi.encodeCall(_agreement.runBefore, (app, new bytes(0))), "");
    }

    function test_beforeHook_limitsExecutionAndStoresRemainder() public {
        CallbackGasBudgetApp app = new CallbackGasBudgetApp(sf.host, CallbackGasBudgetApp.BeforeCreatedMode.Cheap);
        _runBefore(app);
        uint256 hostLimit = sf.host.CALLBACK_GAS_LIMIT();
        assertGt(_agreement.observedBeforeGas(), 0);
        assertLt(_agreement.observedBeforeGas(), hostLimit);
        assertGt(_agreement.remainingGas(), 0);
        assertLt(_agreement.remainingGas(), hostLimit);
    }

    function test_noopBefore_preservesFullBudget() public {
        CallbackGasBudgetApp app = new CallbackGasBudgetApp(sf.host, CallbackGasBudgetApp.BeforeCreatedMode.Noop);
        _runBefore(app);
        assertEq(_agreement.remainingGas(), sf.host.CALLBACK_GAS_LIMIT());
        assertEq(_agreement.observedBeforeGas(), 0);
    }
}
