// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";
import {
    ISuperfluid,
    ISuperApp,
    ISuperToken,
    SuperAppDefinitions
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";

/// @dev before-hook returns a chosen inner `bytes`; after-hook records the `cbdata` it received.
///      Verifies that Host decoding and CFA encoding preserve the cbdata payload received by the after-hook.
contract EchoCbdataApp is ISuperApp {
    bytes internal _payload;
    bytes public lastCbdata;

    constructor(ISuperfluid host, bytes memory payload) {
        _payload = payload;
        host.registerApp(
            SuperAppDefinitions.APP_LEVEL_FINAL
                | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP
        );
    }

    function beforeAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        view
        returns (bytes memory)
    {
        return _payload;
    }

    function afterAgreementCreated(
        ISuperToken,
        address,
        bytes32,
        bytes calldata,
        bytes calldata cbdata,
        bytes calldata ctx
    )
        external
        returns (bytes memory)
    {
        lastCbdata = cbdata;
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

contract CallbackCbdataRoundtripTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    int96 internal constant FLOW_RATE = 1e9;

    constructor() FoundrySuperfluidTester(3) { }

    function test_beforeCallback_emptyCbdataRoundtrips() public {
        _assertCbdataRoundtrip("");
    }

    function test_beforeCallback_unalignedCbdataRoundtrips() public {
        _assertCbdataRoundtrip(hex"ff");
        _assertCbdataRoundtrip(bytes(hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2021"));
    }

    function test_beforeCallback_cbdataRoundtrips(bytes memory payload) public {
        vm.assume(payload.length <= 1024);
        _assertCbdataRoundtrip(payload);
    }

    function _assertCbdataRoundtrip(bytes memory payload) internal {
        EchoCbdataApp app = new EchoCbdataApp(sf.host, payload);
        _addAccount(address(app));

        vm.startPrank(alice);
        superToken.createFlow(address(app), FLOW_RATE);
        vm.stopPrank();

        assertEq(app.lastCbdata(), payload, "after-hook must see inner cbdata, not ABI wrapper");
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "honest create must not jail");
        assertEq(superToken.getFlowRate(alice, address(app)), FLOW_RATE);
    }
}
