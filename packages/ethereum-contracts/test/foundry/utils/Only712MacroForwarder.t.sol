// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { VmSafe } from "forge-std/Vm.sol";
import { ISuperfluid, ISuperfluidToken } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IUserDefined712Macro } from "../../../contracts/interfaces/utils/IUserDefinedMacro.sol";
import { Only712MacroForwarder } from "../../../contracts/utils/Only712MacroForwarder.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";

// ============== Minimal mock macro for Only712MacroForwarder ==============
// Implements IUserDefined712Macro and uses *no* postCheck logic.
// Message has only the required `title`; `customPayload` is expected to be empty.
contract Minimal712Macro is IUserDefined712Macro {
    bytes32 internal constant MESSAGE_TYPEHASH = keccak256("Message(string title)");
    bytes32 internal constant EXPECTED_TITLE_HASH = keccak256(bytes("Hello 712"));

    function buildBatchOperations(ISuperfluid, bytes memory, address)
        external
        pure
        override
        returns (ISuperfluid.Operation[] memory operations)
    {
        operations = new ISuperfluid.Operation[](0);
    }

    function postCheck(ISuperfluid, bytes memory, address) external view override {
        // intentionally empty
    }

    function getMessageTypeHash() external pure override returns (bytes32) {
        return MESSAGE_TYPEHASH;
    }

    function getMessageStructHash(bytes memory message) external pure override returns (bytes32) {
        (string memory title, bytes memory customPayload) = abi.decode(message, (string, bytes));
        require(keccak256(bytes(title)) == EXPECTED_TITLE_HASH, "wrong title");
        require(customPayload.length == 0, "customPayload not empty");
        return keccak256(abi.encode(MESSAGE_TYPEHASH, keccak256(bytes(title))));
    }
}

// ============== Test Contract ==============

contract Only712MacroForwarderTest is FoundrySuperfluidTester {
    Only712MacroForwarder internal forwarder;
    Minimal712Macro internal minimal712Macro;

    constructor() FoundrySuperfluidTester(5) { }

    function setUp() public override {
        super.setUp();
        forwarder = new Only712MacroForwarder(sf.host, address(0));
        minimal712Macro = new Minimal712Macro();

        vm.prank(address(sfDeployer));
        sf.governance.enableTrustedForwarder(sf.host, ISuperfluidToken(address(0)), address(forwarder));
    }

    /**
     * @dev Smoke test: build payload, get digest via getDigest(), sign with vm.createWallet + vm.sign,
     *      call runMacro(m, params, signer, signature), assert success.
     */
    function test_Minimal712Macro_runMacro_smoke() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        bytes memory params = _buildPayload();
        bytes32 digest = forwarder.getDigest(IUserDefined712Macro(address(minimal712Macro)), params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        bytes memory signatureVRS = abi.encodePacked(r, s, v);

        vm.prank(signer.addr);
        bool ok = forwarder.runMacro(IUserDefined712Macro(address(minimal712Macro)), params, signer.addr, signatureVRS);
        assertTrue(ok);
    }

    function _buildPayload() internal pure returns (bytes memory) {
        Only712MacroForwarder.Payload memory payload = Only712MacroForwarder.Payload({
            meta: Only712MacroForwarder.PayloadMeta({ domain: "test.xyz", version: "1" }),
            message: Only712MacroForwarder.PayloadMessage({ title: "Hello 712", customPayload: new bytes(0) }),
            security: Only712MacroForwarder.PayloadSecurity({ provider: "macros.superfluid.eth", nonce: 1 })
        });
        return abi.encode(payload);
    }
}
