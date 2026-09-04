// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";
import {
    ISuperfluid,
    ISuperApp,
    ISuperToken,
    SuperAppDefinitions
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";

/// @dev `beforeAgreementTerminated` returns well-formed `abi.encode(bytes)` of length `bombSize`.
///      Create/update callbacks are NOOP so only the terminate path is under test.
contract OversizedTerminateCbApp is ISuperApp {
    uint256 internal immutable _bombSize;

    constructor(ISuperfluid host, uint256 bombSize) {
        _bombSize = bombSize;
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
        return new bytes(_bombSize);
    }

    function afterAgreementTerminated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external
        pure
        returns (bytes memory)
    {
        return ctx;
    }
}

contract CallbackReturnSizeGriefTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    int96 internal constant FLOW_RATE = 1e9;
    /// Inner `bytes` payload. ABI returndata is 64+this, well above the 32KiB CallbackUtils cap,
    /// while `new bytes` still fits in the 3M callback stipend.
    uint256 internal constant BOMB_SIZE = 100 * 1024;

    constructor() FoundrySuperfluidTester(3) { }

    function test_terminateCallback_smallReturn_doesNotJail() public {
        OversizedTerminateCbApp app = new OversizedTerminateCbApp(sf.host, 32);
        _addAccount(address(app));

        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);

        vm.startPrank(alice);
        superToken.deleteFlow(alice, address(app));
        vm.stopPrank();

        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))));
        assertEq(superToken.getFlowRate(alice, address(app)), 0);
    }

    function test_terminateCallback_oversizedReturn_thirdPartyDeleteJails() public {
        OversizedTerminateCbApp app = new OversizedTerminateCbApp(sf.host, BOMB_SIZE);
        _addAccount(address(app));

        vm.startPrank(alice);
        superToken.setMaxFlowPermissions(bob);
        vm.stopPrank();

        _helperCreateFlow(superToken, alice, address(app), FLOW_RATE);

        vm.expectEmit(true, false, false, true, address(sf.host));
        emit ISuperfluid.Jail(
            ISuperApp(address(app)), SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED
        );

        vm.startPrank(bob);
        superToken.deleteFlow(alice, address(app));
        vm.stopPrank();

        assertTrue(sf.host.isAppJailed(ISuperApp(address(app))));
        assertEq(superToken.getFlowRate(alice, address(app)), 0);
    }
}
