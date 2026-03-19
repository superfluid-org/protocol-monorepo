// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { VmSafe } from "forge-std/Vm.sol";
import { IAccessControl } from "@openzeppelin-v5/contracts/access/IAccessControl.sol";
import { Strings } from "@openzeppelin-v5/contracts/utils/Strings.sol";
import { DeployPermit2 } from "aave-v3/tests/invariants/utils/DeployPermit2.sol";
import { IPermit2 } from "../../../contracts/interfaces/external/IPermit2.sol";
import {
    BatchOperation,
    ISuperfluid,
    ISuperfluidToken
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IClearMacroForwarder } from "../../../contracts/interfaces/utils/IClearMacroForwarder.sol";
import { IClearMacro } from "../../../contracts/interfaces/utils/IClearMacro.sol";
import { ClearMacroForwarder } from "../../../contracts/utils/ClearMacroForwarder.sol";
import { Permit2ClearMacroForwarder } from "../../../contracts/utils/Permit2ClearMacroForwarder.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";

address constant PERMIT2_CANONICAL = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

string constant PRIMARY_TYPE_NAME = "MinimalExample";
string constant ACTION_TYPEDEF = "Action(string description)";
string constant SECURITY_TYPEDEF =
    "Security(string domain,string provider,uint256 validAfter,uint256 validBefore,uint256 nonce)";
string constant SECURITY_DOMAIN = "minimalmacro.xyz";
string constant SECURITY_PROVIDER = "macros.superfluid.eth";
uint256 constant DEFAULT_NONCE = uint256(1) << 64;
uint256 constant TEST_AMOUNT = 100e18;

// ============== Minimal macros for Permit2ClearMacroForwarder ==============
// Implements IClearMacro. Expects params (token, amount); does a SuperToken upgrade from underlying.
contract MinimalClearMacroForPermit2Test is IClearMacro {
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

/// Same types as MinimalClearMacroForPermit2Test but returns no ops.
/// Used when upgrade is implied (forwarder pulls via Permit2 and upgrades).
contract MinimalClearMacroEmptyOps is IClearMacro {
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

contract Permit2ClearMacroForwarderTest is FoundrySuperfluidTester {
    Permit2ClearMacroForwarder internal forwarder;
    MinimalClearMacroForPermit2Test internal minimalClearMacro;
    MinimalClearMacroEmptyOps internal minimalClearMacroEmptyOps;

    constructor() FoundrySuperfluidTester(5) {}

    function setUp() public override {
        super.setUp();
        // Etch Permit2 bytecode at canonical address for local testing
        address deployed = DeployPermit2.deployPermit2();
        vm.etch(PERMIT2_CANONICAL, deployed.code);
        forwarder = new Permit2ClearMacroForwarder(sf.host);
        minimalClearMacro = new MinimalClearMacroForPermit2Test();
        minimalClearMacroEmptyOps = new MinimalClearMacroEmptyOps();

        IAccessControl acl = IAccessControl(sf.host.getSimpleACL());
        vm.prank(address(sfDeployer));
        acl.grantRole(keccak256(bytes(SECURITY_PROVIDER)), address(this));

        vm.prank(address(sfDeployer));
        sf.governance.enableTrustedForwarder(sf.host, ISuperfluidToken(address(0)), address(forwarder));
    }

    function testGetPermit2WitnessTypeString() public view {
        bytes memory params = _getTestPayload();
        string memory result = forwarder.getPermit2WitnessTypeString(minimalClearMacro, params);

        string memory expected = string(abi.encodePacked(
            "ClearMacro",
            " witness)",
            ACTION_TYPEDEF,
            "ClearMacro(Action action,Security security)",
            SECURITY_TYPEDEF,
            "TokenPermissions(address token,uint256 amount)"
        ));
        assertEq(result, expected, "witness type string mismatch");
    }

    function testGetPermit2WitnessTypeStringOrderingForDifferentPrimaryNames() public view {
        // Uses constant "ClearMacro" with nested Security for deterministic alphabetical order:
        // Action, ClearMacro, Security, TokenPermissions (regardless of macro primary name).
        bytes memory params = _getTestPayload();
        string memory result = forwarder.getPermit2WitnessTypeString(minimalClearMacro, params);

        assertTrue(
            _indexOf(result, "Action(") < _indexOf(result, "ClearMacro("),
            "Action should precede ClearMacro"
        );
        assertTrue(
            _indexOf(result, "ClearMacro(") < _indexOf(result, "Security("),
            "ClearMacro should precede Security"
        );
        assertTrue(
            _indexOf(result, "Security(") < _indexOf(result, "TokenPermissions("),
            "Security should precede TokenPermissions"
        );
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
        Permit2ClearMacroForwarder.Permit2MacroParams memory p =
            _buildPermit2Params(signer, address(this), address(0), minimalClearMacro, params);
        assertTrue(forwarder.runPermit2AndMacro(p, minimalClearMacro, params));
        assertEq(
            superToken.balanceOf(signer.addr),
            signerSuperBalanceBefore + TEST_AMOUNT,
            "signer super token balance should increase by TEST_AMOUNT"
        );
    }

    /// With implied upgrade: spender is forwarder; signer approves Permit2.
    /// Forwarder pulls via Permit2, upgrades to signer, runs macro (empty ops).
    function testRunPermit2AndMacroWithImpliedUpgrade(uint256 signerPrivateKey) external {
        signerPrivateKey = bound(signerPrivateKey, 1, SECP256K1_ORDER - 1);
        VmSafe.Wallet memory signer = vm.createWallet(signerPrivateKey);
        _fundSignerWithPermit2Approval(signer, 1);

        bytes memory params = _getTestPayload();
        Permit2ClearMacroForwarder.Permit2MacroParams memory p = _buildPermit2Params(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params
        );
        assertTrue(forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params));
        assertEq(superToken.balanceOf(signer.addr), TEST_AMOUNT, "signer should have received upgraded SuperTokens");
    }

    /// SELF_PROVIDER: signer uses provider "self" and calls runPermit2AndMacro as msg.sender == signer.
    function testRunPermit2AndMacroSelfRelaySucceeds() external {
        VmSafe.Wallet memory signer = vm.createWallet("selfRelaySigner");
        _fundSignerWithPermit2Approval(signer, 1);

        bytes memory params = _getSelfRelayPayload();
        Permit2ClearMacroForwarder.Permit2MacroParams memory p = _buildPermit2Params(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params
        );
        vm.prank(signer.addr);
        assertTrue(forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params));
        assertEq(superToken.balanceOf(signer.addr), TEST_AMOUNT, "signer should have received upgraded SuperTokens");
    }

    /// SELF_PROVIDER: when provider is "self", caller must be signer.
    function testRunPermit2AndMacroSelfRelayRevertsWhenDifferentCaller() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerWithPermit2Approval(signer, 1);

        bytes memory params = _getSelfRelayPayload();
        Permit2ClearMacroForwarder.Permit2MacroParams memory p = _buildPermit2Params(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params
        );

        vm.expectRevert(abi.encodeWithSelector(
            ClearMacroForwarder.ProviderNotAuthorized.selector, "self", address(this)));
        vm.prank(address(this));
        forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params);
    }

    /// When upgradeSuperToken is zero and spender is forwarder: verify signature, run macro (no pull).
    function testRunPermit2AndMacroNoUpgradeWhenSpenderIsForwarder() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerWithPermit2Approval(signer, 1);

        bytes memory params = _getTestPayload();
        Permit2ClearMacroForwarder.Permit2MacroParams memory p =
            _buildPermit2Params(signer, address(forwarder), address(0), minimalClearMacroEmptyOps, params);
        assertTrue(forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params));
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

        bytes32 witness = forwarder.getPermit2WitnessStructHash(minimalClearMacro, params);
        string memory witnessTypeString = forwarder.getPermit2WitnessTypeString(minimalClearMacro, params);

        bytes memory badSignature = abi.encodePacked(bytes32(0), bytes32(0), uint8(27));

        IPermit2.SignatureTransferDetails memory transferDetails = IPermit2.SignatureTransferDetails({
            to: signer.addr,
            requestedAmount: TEST_AMOUNT
        });

        vm.expectRevert(ClearMacroForwarder.InvalidSignature.selector);
        Permit2ClearMacroForwarder.Permit2MacroParams memory p = _toPermit2MacroParams(
            permit, transferDetails, signer.addr, witness, witnessTypeString, badSignature, address(this), address(0)
        );
        forwarder.runPermit2AndMacro(p, minimalClearMacro, params);
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

        vm.expectRevert(abi.encodeWithSelector(ClearMacroForwarder.InvalidPayload.selector, "witness mismatch"));
        Permit2ClearMacroForwarder.Permit2MacroParams memory p = _toPermit2MacroParams(
            permit, transferDetails, signer.addr, wrongWitness, witnessTypeString, signature, address(this), address(0)
        );
        forwarder.runPermit2AndMacro(p, minimalClearMacro, params);
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

        witnessTypeString = forwarder.getPermit2WitnessTypeString(minimalClearMacro, params);
        IClearMacroForwarder.Security memory otherSecurity = IClearMacroForwarder.Security({
            domain: SECURITY_DOMAIN,
            provider: SECURITY_PROVIDER,
            validAfter: 0,
            validBefore: 0,
            nonce: DEFAULT_NONCE
        });
        bytes memory otherParams = forwarder.encodeParams(
            abi.encode(address(superToken), TEST_AMOUNT + 1),
            otherSecurity
        );
        wrongWitness = forwarder.getPermit2WitnessStructHash(minimalClearMacro, otherParams);
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
        IClearMacro m,
        bytes memory params
    ) internal returns (bytes32 witness, string memory witnessTypeString, bytes memory signature) {
        witness = forwarder.getPermit2WitnessStructHash(m, params);
        witnessTypeString = forwarder.getPermit2WitnessTypeString(m, params);
        bytes32 digest = _computePermit2Digest(permit, spender, witness, witnessTypeString);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _getTestPayload() internal view returns (bytes memory) {
        IClearMacroForwarder.Security memory security = IClearMacroForwarder.Security({
            domain: SECURITY_DOMAIN,
            provider: SECURITY_PROVIDER,
            validAfter: 0,
            validBefore: 0,
            nonce: DEFAULT_NONCE
        });
        return forwarder.encodeParams(abi.encode(address(superToken), TEST_AMOUNT), security);
    }

    function _getSelfRelayPayload() internal view returns (bytes memory) {
        IClearMacroForwarder.Security memory security = IClearMacroForwarder.Security({
            domain: SECURITY_DOMAIN,
            provider: "self",
            validAfter: 0,
            validBefore: 0,
            nonce: DEFAULT_NONCE
        });
        return forwarder.encodeParams(abi.encode(address(superToken), TEST_AMOUNT), security);
    }

    function _buildPermit2Params(
        VmSafe.Wallet memory signer,
        address spender,
        address upgradeSuperToken,
        IClearMacro m,
        bytes memory params
    ) internal returns (Permit2ClearMacroForwarder.Permit2MacroParams memory p) {
        p.permit = _makePermit(address(token), TEST_AMOUNT);
        (p.witness, p.witnessTypeString, p.signature) = _signPermit(signer, p.permit, spender, m, params);
        p.transferDetails = IPermit2.SignatureTransferDetails({
            to: spender == address(forwarder) ? address(forwarder) : signer.addr,
            requestedAmount: TEST_AMOUNT
        });
        p.owner = signer.addr;
        p.spender = spender;
        p.upgradeSuperToken = upgradeSuperToken;
    }

    function _toPermit2MacroParams(
        IPermit2.PermitTransferFrom memory permit,
        IPermit2.SignatureTransferDetails memory transferDetails,
        address owner,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory signature,
        address spender,
        address upgradeSuperToken
    ) internal pure returns (Permit2ClearMacroForwarder.Permit2MacroParams memory) {
        return Permit2ClearMacroForwarder.Permit2MacroParams({
            permit: permit,
            transferDetails: transferDetails,
            owner: owner,
            witness: witness,
            witnessTypeString: witnessTypeString,
            signature: signature,
            spender: spender,
            upgradeSuperToken: upgradeSuperToken
        });
    }
}
