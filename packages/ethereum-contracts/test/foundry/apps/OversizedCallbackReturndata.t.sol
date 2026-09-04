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

/// @dev Super App that bombs one termination-callback returndata channel.
///      Create/update callbacks are NOOP so only the terminate path is under test.
contract TerminationReturndataBombApp is ISuperApp {
    enum Mode {
        FatBeforeCbdata,
        FatAfterNewCtx,
        FatRevertData
    }

    Mode public immutable mode;
    uint256 public immutable payloadSize;

    constructor(ISuperfluid host, Mode mode_, uint256 payloadSize_) {
        mode = mode_;
        payloadSize = payloadSize_;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL | SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP
            | SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
            | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP;
        if (mode_ == Mode.FatBeforeCbdata || mode_ == Mode.FatRevertData) {
            configWord |= SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;
        } else {
            configWord |= SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;
        }
        host.registerApp(configWord);
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
        if (mode == Mode.FatRevertData) {
            _returnOrRevertFat(true);
        }
        if (mode == Mode.FatBeforeCbdata) {
            if (payloadSize == 0) return "";
            _returnOrRevertFat(false);
        }
        return "";
    }

    function afterAgreementTerminated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external
        view
        returns (bytes memory)
    {
        if (mode == Mode.FatAfterNewCtx) {
            _returnOrRevertFat(false);
        }
        return ctx;
    }

    /// Cheap fat payload: expand via RETURN/REVERT, no zeroing, no ABI wrapper.
    /// `new bytes(n)` would OOG inside CALLBACK_GAS_LIMIT and jail as a revert — not the Host-copy bug.
    function _returnOrRevertFat(bool doRevert) internal view {
        uint256 n = payloadSize;
        assembly {
            if doRevert { revert(0, n) }
            return(0, n)
        }
    }
}

/// @dev Desired spec (red on unpatched Host): a successful fat callback return / revert
///      must not deny termination. Liquidation-budget delete closes the flow and jails the app.
///      Unpatched Host copies returndata after the gas-capped callback and OOGs instead of jailing.
contract OversizedCallbackReturndataTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    /// Large enough that Host RETURNDATACOPY OOGs a ~3.6M liquidator tx; small enough to fit in the 3M stipend.
    uint256 internal constant FAT_PAYLOAD_SIZE = 1_000_000;

    /// Enough to deliver CALLBACK_GAS_LIMIT (EIP-150) and run an honest terminate; not enough to copy 1MB returndata.
    uint256 internal constant LIQUIDATOR_TX_GAS = 3_600_000;

    int96 internal constant FLOW_RATE = 1e9;

    constructor() FoundrySuperfluidTester(3) { }

    function deleteFlowAsAlice(address receiver) external {
        vm.startPrank(alice);
        superToken.deleteFlow(alice, receiver);
        vm.stopPrank();
    }

    function test_honestTerminate_succeedsAtLiquidatorGas() public {
        TerminationReturndataBombApp app =
            new TerminationReturndataBombApp(sf.host, TerminationReturndataBombApp.Mode.FatBeforeCbdata, 0);
        _openFlow(address(app));
        (bool ok,) = address(this).call{gas: LIQUIDATOR_TX_GAS}(abi.encodeCall(this.deleteFlowAsAlice, (address(app))));
        assertTrue(ok, "honest terminate should fit in liquidator gas");
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "honest app must not be jailed");
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "honest flow should be closed");
    }

    function test_fatBeforeCbdata_terminateJailsAndClosesFlow() public {
        TerminationReturndataBombApp app = new TerminationReturndataBombApp(
            sf.host, TerminationReturndataBombApp.Mode.FatBeforeCbdata, FAT_PAYLOAD_SIZE
        );
        _openFlow(address(app));
        _assertTerminateJailsAndCloses(address(app));
    }

    function test_fatAfterNewCtx_terminateJailsAndClosesFlow() public {
        TerminationReturndataBombApp app = new TerminationReturndataBombApp(
            sf.host, TerminationReturndataBombApp.Mode.FatAfterNewCtx, FAT_PAYLOAD_SIZE
        );
        _openFlow(address(app));
        _assertTerminateJailsAndCloses(address(app));
    }

    function test_fatRevertData_terminateJailsAndClosesFlow() public {
        TerminationReturndataBombApp app = new TerminationReturndataBombApp(
            sf.host, TerminationReturndataBombApp.Mode.FatRevertData, FAT_PAYLOAD_SIZE
        );
        _openFlow(address(app));
        _assertTerminateJailsAndCloses(address(app));
    }

    function _openFlow(address app) internal {
        // startPrank: SuperTokenV1Library may do a cache-warmup external call before callAgreement
        vm.startPrank(alice);
        superToken.createFlow(app, FLOW_RATE);
        vm.stopPrank();
        assertEq(superToken.getFlowRate(alice, app), FLOW_RATE, "setup: flow not open");
    }

    function _assertTerminateJailsAndCloses(address app) internal {
        (bool ok,) = address(this).call{gas: LIQUIDATOR_TX_GAS}(abi.encodeCall(this.deleteFlowAsAlice, (app)));
        assertTrue(ok, "termination should succeed at liquidator gas (not OOG on Host returndata copy)");
        assertTrue(sf.host.isAppJailed(ISuperApp(app)), "app should be jailed");
        assertEq(superToken.getFlowRate(alice, app), 0, "flow should be closed");
    }
}
