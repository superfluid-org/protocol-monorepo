// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { VmSafe } from "forge-std/Vm.sol";
import { IAccessControl } from "@openzeppelin-v5/contracts/access/IAccessControl.sol";
import { Strings } from "@openzeppelin-v5/contracts/utils/Strings.sol";
import { DeployPermit2 } from "aave-v3/tests/invariants/utils/DeployPermit2.sol";
import { IPermit2 } from "../../../contracts/interfaces/external/IPermit2.sol";
import { BatchOperation, ISuperfluid, ISuperfluidToken } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IUserDefined712Macro } from "../../../contracts/interfaces/utils/IUserDefinedMacro.sol";
import { Only712MacroForwarder } from "../../../contracts/utils/Only712MacroForwarder.sol";
import { Permit2MacroForwarder } from "../../../contracts/utils/Permit2MacroForwarder.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";

address constant PERMIT2_CANONICAL = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

string constant PRIMARY_TYPE_NAME = "MinimalExample";
string constant ACTION_TYPEDEF = "Action(string description)";
string constant SECURITY_DOMAIN = "minimalmacro.xyz";
string constant SECURITY_PROVIDER = "macros.superfluid.eth";
uint256 constant DEFAULT_NONCE = uint256(1) << 64;
uint256 constant TEST_AMOUNT = 100e18;

// ============== Minimal macros for Permit2MacroForwarder ==============
// Implements IUserDefined712Macro. Expects params (token, amount); does a SuperToken upgrade from underlying.
// Shows how the params can be different from the type definition, while still being part of the signed data
// (via the dynamic construction of the description string from the params)
contract Minimal712MacroForPermit2Test is IUserDefined712Macro {
    string public constant ACTION_TYPE_DEFINITION = "Action(string description)";

    function _buildDescription(address token, uint256 amount) internal pure returns (string memory) {
        return string.concat(
            "Upgrade ",
            Strings.toString(amount),
            " ",
            Strings.toHexString(token)
        );
    }

    function buildBatchOperations(ISuperfluid, bytes memory params, address /*signer*/)
        external
        pure
        override
        returns (ISuperfluid.Operation[] memory operations)
    {
        (address token, uint256 amount) = abi.decode(params, (address, uint256));
        operations = new ISuperfluid.Operation[](1);
        operations[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERTOKEN_UPGRADE,
            target: token,
            data: abi.encode(amount)
        });
    }

    function postCheck(ISuperfluid, bytes memory, address) external view override {
        // intentionally empty
    }

    function getActionTypeDefinition(bytes memory /*params*/) external pure override returns (string memory) {
        return ACTION_TYPE_DEFINITION;
    }

    function getPrimaryTypeName(bytes memory /*params*/) external pure override returns (string memory) {
        return PRIMARY_TYPE_NAME;
    }

    function getActionStructHash(bytes memory params) external pure override returns (bytes32) {
        (address token, uint256 amount) = abi.decode(params, (address, uint256));
        string memory description = _buildDescription(token, amount);
        bytes32 actionTypeHash = keccak256(abi.encodePacked(ACTION_TYPE_DEFINITION));
        return keccak256(abi.encode(actionTypeHash, keccak256(bytes(description))));
    }
}

/// Same types as Minimal712MacroForPermit2Test but returns no ops.
/// Used when upgrade is implied (forwarder pulls via Permit2 and upgrades).
contract Minimal712MacroEmptyOps is IUserDefined712Macro {
    string public constant ACTION_TYPE_DEFINITION = "Action(string description)";

    function _buildDescription(address token, uint256 amount) internal pure returns (string memory) {
        return string.concat(
            "Upgrade ",
            Strings.toString(amount),
            " ",
            Strings.toHexString(token)
        );
    }

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

    function getActionTypeDefinition(bytes memory /*params*/) external pure override returns (string memory) {
        return ACTION_TYPE_DEFINITION;
    }

    function getPrimaryTypeName(bytes memory /*params*/) external pure override returns (string memory) {
        return PRIMARY_TYPE_NAME;
    }

    function getActionStructHash(bytes memory params) external pure override returns (bytes32) {
        (address token, uint256 amount) = abi.decode(params, (address, uint256));
        string memory description = _buildDescription(token, amount);
        bytes32 actionTypeHash = keccak256(abi.encodePacked(ACTION_TYPE_DEFINITION));
        return keccak256(abi.encode(actionTypeHash, keccak256(bytes(description))));
    }
}

// ============== Test Contract ==============

contract Permit2MacroForwarderTest is FoundrySuperfluidTester {
    Permit2MacroForwarder internal forwarder;
    Minimal712MacroForPermit2Test internal minimal712Macro;
    Minimal712MacroEmptyOps internal minimal712MacroEmptyOps;

    constructor() FoundrySuperfluidTester(5) {}

    function setUp() public override {
        super.setUp();
        // Etch Permit2 bytecode at canonical address for local testing
        address deployed = DeployPermit2.deployPermit2();
        vm.etch(PERMIT2_CANONICAL, deployed.code);
        forwarder = new Permit2MacroForwarder(sf.host);
        minimal712Macro = new Minimal712MacroForPermit2Test();
        minimal712MacroEmptyOps = new Minimal712MacroEmptyOps();

        IAccessControl acl = IAccessControl(sf.host.getSimpleACL());
        vm.prank(address(sfDeployer));
        acl.grantRole(keccak256(bytes(SECURITY_PROVIDER)), address(this));

        vm.prank(address(sfDeployer));
        sf.governance.enableTrustedForwarder(sf.host, ISuperfluidToken(address(0)), address(forwarder));
    }

    function testGetPermit2WitnessTypeString() public view {
        bytes memory params = _getTestPayload();
        string memory result = forwarder.getPermit2WitnessTypeString(minimal712Macro, params);

        string memory expected = string(abi.encodePacked(
            PRIMARY_TYPE_NAME,
            " witness)",
            ACTION_TYPEDEF,
            PRIMARY_TYPE_NAME,
            "(Action action,string domain,uint256 nonce,string provider,uint256 validAfter,uint256 validBefore)",
            "TokenPermissions(address token,uint256 amount)"
        ));
        assertEq(result, expected, "witness type string mismatch");
    }

    function testGetPermit2WitnessTypeStringOrderingForDifferentPrimaryNames() public view {
        // For "AMacro" (A before M before T): Action, AMacro, TokenPermissions
        // For "ZooWitness" (A before T before Z): Action, TokenPermissions, ZooWitness
        // We test that MinimalExample gives Action, MinimalExample, TokenPermissions
        bytes memory params = _getTestPayload();
        string memory result = forwarder.getPermit2WitnessTypeString(minimal712Macro, params);

        // Verify Action comes before MinimalExample (alphabetically)
        assertTrue(_indexOf(result, "Action(") < _indexOf(result, "MinimalExample("), "Action should precede MinimalExample");
        // Verify MinimalExample comes before TokenPermissions
        assertTrue(_indexOf(result, "MinimalExample(") < _indexOf(result, "TokenPermissions("), "MinimalExample should precede TokenPermissions");
    }

    function _indexOf(string memory haystack, string memory needle) internal pure returns (int256) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);
        if (needleBytes.length > haystackBytes.length) return -1;
        for (uint256 i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return int256(i);
        }
        return -1;
    }

    /// Without implied upgrade: spender is test contract; signer has direct approval to SuperToken.
    /// Macro builds upgrade op; Host pulls from signer.
    function testRunPermit2AndMacroWithoutUpgrade(uint256 signerPrivateKey) external {
        signerPrivateKey = bound(signerPrivateKey, 1, SECP256K1_ORDER - 1);
        VmSafe.Wallet memory signer = vm.createWallet(signerPrivateKey);
        _fundSignerForUpgrade(signer, 1);

        uint256 signerSuperBalanceBefore = superToken.balanceOf(signer.addr);
        bytes memory params = _getTestPayload();
        IPermit2.PermitTransferFrom memory permit = _makePermit(address(token), TEST_AMOUNT);
        (bytes32 witness, string memory witnessTypeString, bytes memory signature) =
            _signPermit(signer, permit, address(this), minimal712Macro, params);
        IPermit2.SignatureTransferDetails memory transferDetails =
            IPermit2.SignatureTransferDetails({ to: signer.addr, requestedAmount: TEST_AMOUNT });

        assertTrue(_runPermit2AndMacro(permit, transferDetails, signer.addr, witness, witnessTypeString, signature, minimal712Macro, params));
        assertEq(superToken.balanceOf(signer.addr), signerSuperBalanceBefore + TEST_AMOUNT, "signer super token balance should increase by TEST_AMOUNT");
    }

    /// With implied upgrade: spender is forwarder; signer approves Permit2.
    /// Forwarder pulls via Permit2, upgrades to signer, runs macro (empty ops).
    function testRunPermit2AndMacroWithImpliedUpgrade(uint256 signerPrivateKey) external {
        signerPrivateKey = bound(signerPrivateKey, 1, SECP256K1_ORDER - 1);
        VmSafe.Wallet memory signer = vm.createWallet(signerPrivateKey);
        _fundSignerWithPermit2Approval(signer, 1);

        bytes memory params = _getTestPayload();
        IPermit2.PermitTransferFrom memory permit = _makePermit(address(token), TEST_AMOUNT);
        (bytes32 witness, string memory witnessTypeString, bytes memory signature) =
            _signPermit(signer, permit, address(forwarder), minimal712MacroEmptyOps, params);
        IPermit2.SignatureTransferDetails memory transferDetails =
            IPermit2.SignatureTransferDetails({ to: address(forwarder), requestedAmount: TEST_AMOUNT });

        assertTrue(_runPermit2AndMacro(permit, transferDetails, signer.addr, witness, witnessTypeString, signature, minimal712MacroEmptyOps, params));
        assertEq(superToken.balanceOf(signer.addr), TEST_AMOUNT, "signer should have received upgraded SuperTokens");
    }

    function testRunPermit2AndMacroRevertsOnInvalidSignature() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerForUpgrade(signer, 1);

        bytes memory params = _getTestPayload();
        IPermit2.PermitTransferFrom memory permit = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({
                token: address(token),
                amount: TEST_AMOUNT
            }),
            nonce: 0,
            deadline: block.timestamp + 3600
        });

        bytes32 witness = forwarder.getStructHash(minimal712Macro, params);
        string memory witnessTypeString = forwarder.getPermit2WitnessTypeString(minimal712Macro, params);

        bytes memory badSignature = abi.encodePacked(bytes32(0), bytes32(0), uint8(27));

        IPermit2.SignatureTransferDetails memory transferDetails = IPermit2.SignatureTransferDetails({
            to: signer.addr,
            requestedAmount: TEST_AMOUNT
        });

        vm.expectRevert(Only712MacroForwarder.InvalidSignature.selector);
        forwarder.runPermit2AndMacro(
            permit, transferDetails, signer.addr, witness, witnessTypeString, badSignature,
            minimal712Macro, params
        );
    }

    function testRunPermit2AndMacroRevertsOnWitnessMismatch() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerForUpgrade(signer, 1);

        bytes memory params = _getTestPayload();
        (
            IPermit2.PermitTransferFrom memory permit,
            bytes32 wrongWitness,
            string memory witnessTypeString,
            bytes memory signature
        ) = _getPermitAndSignatureForWitnessMismatch(signer, params);

        IPermit2.SignatureTransferDetails memory transferDetails = IPermit2.SignatureTransferDetails({
            to: signer.addr,
            requestedAmount: TEST_AMOUNT
        });

        vm.expectRevert(abi.encodeWithSelector(Only712MacroForwarder.InvalidPayload.selector, "witness mismatch"));
        forwarder.runPermit2AndMacro(
            permit, transferDetails, signer.addr, wrongWitness, witnessTypeString, signature,
            minimal712Macro, params
        );
    }

    function _getPermitAndSignatureForWitnessMismatch(VmSafe.Wallet memory signer, bytes memory params)
        internal
        returns (
            IPermit2.PermitTransferFrom memory permit,
            bytes32 wrongWitness,
            string memory witnessTypeString,
            bytes memory signature
        )
    {
        permit = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({
                token: address(token),
                amount: TEST_AMOUNT
            }),
            nonce: 0,
            deadline: block.timestamp + 3600
        });

        witnessTypeString = forwarder.getPermit2WitnessTypeString(minimal712Macro, params);
        bytes memory otherParams = forwarder.encodeParams(
            abi.encode(address(superToken), TEST_AMOUNT + 1),
            SECURITY_DOMAIN,
            SECURITY_PROVIDER,
            0,
            0,
            DEFAULT_NONCE
        );
        wrongWitness = forwarder.getStructHash(minimal712Macro, otherParams);
        bytes32 digest = _computePermit2Digest(permit, address(this), wrongWitness, witnessTypeString);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _computePermit2Digest(
        IPermit2.PermitTransferFrom memory permit,
        address spender,
        bytes32 witness,
        string memory witnessTypeString
    ) internal view returns (bytes32) {
        bytes32 typeHash = keccak256(abi.encodePacked(
            "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,",
            witnessTypeString
        ));
        bytes32 tokenPermissionsHash = keccak256(abi.encode(
            keccak256("TokenPermissions(address token,uint256 amount)"),
            permit.permitted
        ));
        bytes32 structHash = keccak256(abi.encode(
            typeHash,
            tokenPermissionsHash,
            spender,
            permit.nonce,
            permit.deadline,
            witness
        ));
        bytes32 domainSeparator = IPermit2(PERMIT2_CANONICAL).DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _fundSignerForUpgrade(VmSafe.Wallet memory signer, uint256 runs) internal {
        uint256 total = TEST_AMOUNT * runs;
        vm.prank(alice);
        token.transfer(signer.addr, total);
        vm.prank(signer.addr);
        token.approve(address(superToken), total);
    }

    function _fundSignerWithPermit2Approval(VmSafe.Wallet memory signer, uint256 runs) internal {
        uint256 total = TEST_AMOUNT * runs;
        vm.prank(alice);
        token.transfer(signer.addr, total);
        vm.prank(signer.addr);
        token.approve(PERMIT2_CANONICAL, total);
    }

    function _makePermit(address tokenAddr, uint256 amount) internal view returns (IPermit2.PermitTransferFrom memory) {
        return IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({ token: tokenAddr, amount: amount }),
            nonce: 0,
            deadline: block.timestamp + 3600
        });
    }

    function _signPermit(
        VmSafe.Wallet memory signer,
        IPermit2.PermitTransferFrom memory permit,
        address spender,
        IUserDefined712Macro m,
        bytes memory params
    ) internal returns (bytes32 witness, string memory witnessTypeString, bytes memory signature) {
        witness = forwarder.getStructHash(m, params);
        witnessTypeString = forwarder.getPermit2WitnessTypeString(m, params);
        bytes32 digest = _computePermit2Digest(permit, spender, witness, witnessTypeString);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _getTestPayload() internal view returns (bytes memory) {
        return forwarder.encodeParams(
            abi.encode(address(superToken), TEST_AMOUNT),
            SECURITY_DOMAIN,
            SECURITY_PROVIDER,
            0,
            0,
            DEFAULT_NONCE
        );
    }

    function _runPermit2AndMacro(
        IPermit2.PermitTransferFrom memory permit,
        IPermit2.SignatureTransferDetails memory transferDetails,
        address owner,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory signature,
        IUserDefined712Macro m,
        bytes memory params
    ) internal returns (bool) {
        return forwarder.runPermit2AndMacro(
            permit, transferDetails, owner, witness, witnessTypeString, signature, m, params
        );
    }
}
