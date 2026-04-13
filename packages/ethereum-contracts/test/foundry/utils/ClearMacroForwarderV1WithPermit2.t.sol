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
    ISuperfluidToken,
    ISuperToken
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IClearMacroForwarderV1 } from "../../../contracts/interfaces/utils/IClearMacroForwarderV1.sol";
import {
    IClearMacroForwarderV1WithPermit2
} from "../../../contracts/interfaces/utils/IClearMacroForwarderV1WithPermit2.sol";
import { IClearMacro } from "../../../contracts/interfaces/utils/IClearMacro.sol";
import { ClearMacroForwarderV1 } from "../../../contracts/utils/ClearMacroForwarderV1.sol";
import { ClearMacroForwarderV1WithPermit2 } from "../../../contracts/utils/ClearMacroForwarderV1WithPermit2.sol";
import { TestToken } from "../../../contracts/utils/TestToken.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";

address constant PERMIT2_CANONICAL = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

string constant PRIMARY_TYPE_NAME = "MinimalExample";
string constant ACTION_TYPEDEF = "Action(string description)";
string constant SECURITY_TYPEDEF =
    "Security(string domain,address macroContract,string provider,uint256 validAfter,uint256 validBefore,uint256 nonce)";
string constant SECURITY_DOMAIN = "minimalmacro.xyz";
string constant SECURITY_PROVIDER = "macros.superfluid.eth";
uint256 constant DEFAULT_NONCE = uint256(1) << 64;
uint256 constant TEST_AMOUNT = 100e18;

// ============== Minimal macros for ClearMacroForwarderV1WithPermit2 ==============
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

contract ClearMacroForwarderV1WithPermit2Test is FoundrySuperfluidTester {
    ClearMacroForwarderV1WithPermit2 internal forwarder;
    MinimalClearMacroForPermit2Test internal minimalClearMacro;
    MinimalClearMacroEmptyOps internal minimalClearMacroEmptyOps;

    constructor() FoundrySuperfluidTester(5) {}

    function setUp() public override {
        super.setUp();
        // Etch Permit2 bytecode at canonical address for local testing
        address deployed = DeployPermit2.deployPermit2();
        vm.etch(PERMIT2_CANONICAL, deployed.code);
        forwarder = new ClearMacroForwarderV1WithPermit2(sf.host);
        minimalClearMacro = new MinimalClearMacroForPermit2Test();
        minimalClearMacroEmptyOps = new MinimalClearMacroEmptyOps();

        IAccessControl acl = IAccessControl(sf.host.getSimpleACL());
        vm.prank(address(sfDeployer));
        acl.grantRole(keccak256(bytes(SECURITY_PROVIDER)), address(this));

        vm.prank(address(sfDeployer));
        sf.governance.enableTrustedForwarder(sf.host, ISuperfluidToken(address(0)), address(forwarder));
    }

    function testGetPermit2WitnessTypeString() public view {
        bytes memory params = _getTestPayload(minimalClearMacro);
        string memory result = forwarder.getPermit2WitnessTypeString(minimalClearMacro, params);

        string memory expected = string(abi.encodePacked(
            "ClearMacro",
            " witness)",
            ACTION_TYPEDEF,
            "ClearMacro(address upgradeSuperToken,Action action,Security security)",
            SECURITY_TYPEDEF,
            "TokenPermissions(address token,uint256 amount)"
        ));
        assertEq(result, expected, "witness type string mismatch");
    }

    function testGetPermit2WitnessTypeStringOrderingForDifferentPrimaryNames() public view {
        // Uses constant "ClearMacro" with nested Security for deterministic alphabetical order:
        // Action, ClearMacro, Security, TokenPermissions (regardless of macro primary name).
        bytes memory params = _getTestPayload(minimalClearMacro);
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
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, address(superToken));

        uint256 signerSuperBalanceBefore = superToken.balanceOf(signer.addr);
        bytes memory params = _getTestPayload(minimalClearMacro);
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p =
            _buildPermit2Params(signer, address(this), address(0), minimalClearMacro, params, token, TEST_AMOUNT);
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
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getTestPayload(minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p = _buildPermit2Params(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );
        assertTrue(forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params));
        assertEq(superToken.balanceOf(signer.addr), TEST_AMOUNT, "signer should have received upgraded SuperTokens");
    }

    function testRunPermit2AndMacroWithImpliedUpgradeScalesUpForLowerUnderlyingDecimals() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer6Decimals");
        (TestToken underlying, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("Token6", "TK6", 6, type(uint256).max, address(0));
        uint256 underlyingAmount = 1_234_567; // 1.234567 with 6 decimals
        uint256 expectedSuperAmount = underlyingAmount * 1e12;

        _fundSignerAndApprove(underlying, signer, underlyingAmount, PERMIT2_CANONICAL);

        bytes memory params =
            _getPayload(localSuperToken, expectedSuperAmount, SECURITY_PROVIDER, minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p = _buildPermit2Params(
            signer,
            address(forwarder),
            address(localSuperToken),
            minimalClearMacroEmptyOps,
            params,
            underlying,
            underlyingAmount
        );

        assertTrue(forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params));
        assertEq(localSuperToken.balanceOf(signer.addr), expectedSuperAmount, "scaled-up super amount mismatch");
    }

    function testRunPermit2AndMacroWithImpliedUpgradeScalesDownForHigherUnderlyingDecimals() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer20Decimals");
        (TestToken underlying, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("Token20", "TK20", 20, type(uint256).max, address(0));
        uint256 underlyingAmount = 123_456_789_012_345_678_901; // 12.3456789012345678901 with 20 decimals
        uint256 expectedSuperAmount = underlyingAmount / 100;

        _fundSignerAndApprove(underlying, signer, underlyingAmount, PERMIT2_CANONICAL);

        bytes memory params =
            _getPayload(localSuperToken, expectedSuperAmount, SECURITY_PROVIDER, minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p = _buildPermit2Params(
            signer,
            address(forwarder),
            address(localSuperToken),
            minimalClearMacroEmptyOps,
            params,
            underlying,
            underlyingAmount
        );

        assertTrue(forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params));
        assertEq(localSuperToken.balanceOf(signer.addr), expectedSuperAmount, "scaled-down super amount mismatch");
    }

    /// SELF_PROVIDER: signer uses provider "self" and calls runPermit2AndMacro as msg.sender == signer.
    function testRunPermit2AndMacroSelfRelaySucceeds() external {
        VmSafe.Wallet memory signer = vm.createWallet("selfRelaySigner");
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getSelfRelayPayload();
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p = _buildPermit2Params(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );
        vm.prank(signer.addr);
        assertTrue(forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params));
        assertEq(superToken.balanceOf(signer.addr), TEST_AMOUNT, "signer should have received upgraded SuperTokens");
    }

    /// SELF_PROVIDER: when provider is "self", caller must be signer.
    function testRunPermit2AndMacroSelfRelayRevertsWhenDifferentCaller() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getSelfRelayPayload();
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p = _buildPermit2Params(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );

        vm.expectRevert(abi.encodeWithSelector(
            ClearMacroForwarderV1.ProviderNotAuthorized.selector, "self", address(this)));
        vm.prank(address(this));
        forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params);
    }

    /// When upgradeSuperToken is zero and spender is forwarder: verify signature, run macro (no pull).
    function testRunPermit2AndMacroNoUpgradeWhenSpenderIsForwarder() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getTestPayload(minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p = _buildPermit2Params(
            signer, address(forwarder), address(0), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );
        assertTrue(forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params));
    }

    function testRunPermit2AndMacroRevertsOnPermitTokenMismatch() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        TestToken wrongUnderlying = new TestToken("Wrong Token", "WRONG", 18, type(uint256).max);
        _fundSignerAndApprove(wrongUnderlying, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getTestPayload(minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p;
        p.permit = _makePermit(address(wrongUnderlying), TEST_AMOUNT);
        (p.witness, p.witnessTypeString, p.signature) = _signPermit(
            signer, p.permit, address(forwarder), minimalClearMacroEmptyOps, params, address(superToken)
        );
        p.owner = signer.addr;
        p.spender = address(forwarder);
        p.upgradeSuperToken = address(superToken);

        vm.expectRevert(abi.encodeWithSelector(ClearMacroForwarderV1.InvalidPayload.selector, "permit token mismatch"));
        forwarder.runPermit2AndMacro(p, minimalClearMacroEmptyOps, params);
    }

    function testRunPermit2AndMacroRevertsOnInvalidSignature() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, address(superToken));

        bytes memory params = _getTestPayload(minimalClearMacro);
        IPermit2.PermitTransferFrom memory permit = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({
                token: address(token),
                amount: TEST_AMOUNT
            }),
            nonce: 0,
            deadline: block.timestamp + 3600
        });

        bytes32 witness = forwarder.getPermit2WitnessStructHash(minimalClearMacro, params, address(0));
        string memory witnessTypeString = forwarder.getPermit2WitnessTypeString(minimalClearMacro, params);

        bytes memory badSignature = abi.encodePacked(bytes32(0), bytes32(0), uint8(27));

        vm.expectRevert(ClearMacroForwarderV1.InvalidSignature.selector);
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p = _toPermit2MacroParams(
            permit, signer.addr, witness, witnessTypeString, badSignature, address(this), address(0)
        );
        forwarder.runPermit2AndMacro(p, minimalClearMacro, params);
    }

    function testRunPermit2AndMacroRevertsOnWitnessMismatch() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, address(superToken));

        bytes memory params = _getTestPayload(minimalClearMacro);
        (
            IPermit2.PermitTransferFrom memory permit,
            bytes32 wrongWitness,
            string memory witnessTypeString,
            bytes memory signature
        ) = _getPermitAndSignatureForWitnessMismatch(signer, params);

        vm.expectRevert(abi.encodeWithSelector(ClearMacroForwarderV1.InvalidPayload.selector, "witness mismatch"));
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p = _toPermit2MacroParams(
            permit, signer.addr, wrongWitness, witnessTypeString, signature, address(this), address(0)
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
        IClearMacroForwarderV1.Security memory otherSecurity = IClearMacroForwarderV1.Security({
            domain: SECURITY_DOMAIN,
            macroContract: address(minimalClearMacro),
            provider: SECURITY_PROVIDER,
            validAfter: 0,
            validBefore: 0,
            nonce: DEFAULT_NONCE
        });
        bytes memory otherParams = forwarder.encodeParams(
            abi.encode(address(superToken), TEST_AMOUNT + 1),
            otherSecurity
        );
        wrongWitness = forwarder.getPermit2WitnessStructHash(minimalClearMacro, otherParams, address(0));
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
        bytes memory params,
        address upgradeSuperToken
    ) internal returns (bytes32 witness, string memory witnessTypeString, bytes memory signature) {
        witness = forwarder.getPermit2WitnessStructHash(m, params, upgradeSuperToken);
        witnessTypeString = forwarder.getPermit2WitnessTypeString(m, params);
        bytes32 digest = _computePermit2Digest(permit, spender, witness, witnessTypeString);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _getTestPayload(IClearMacro m) internal view returns (bytes memory) {
        return _getPayload(superToken, TEST_AMOUNT, SECURITY_PROVIDER, m);
    }

    function _getSelfRelayPayload() internal view returns (bytes memory) {
        return _getPayload(superToken, TEST_AMOUNT, "self", minimalClearMacroEmptyOps);
    }

    function _getPayload(ISuperToken targetSuperToken, uint256 amount, string memory provider, IClearMacro m)
        internal
        view
        returns (bytes memory)
    {
        IClearMacroForwarderV1.Security memory security = IClearMacroForwarderV1.Security({
            domain: SECURITY_DOMAIN,
            macroContract: address(m),
            provider: provider,
            validAfter: 0,
            validBefore: 0,
            nonce: DEFAULT_NONCE
        });
        return forwarder.encodeParams(abi.encode(address(targetSuperToken), amount), security);
    }

    function _buildPermit2Params(
        VmSafe.Wallet memory signer,
        address spender,
        address upgradeSuperToken,
        IClearMacro m,
        bytes memory params,
        TestToken permitToken,
        uint256 permitAmount
    ) internal returns (IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p) {
        p.permit = _makePermit(address(permitToken), permitAmount);
        (p.witness, p.witnessTypeString, p.signature) = _signPermit(signer, p.permit, spender, m, params, upgradeSuperToken);
        p.owner = signer.addr;
        p.spender = spender;
        p.upgradeSuperToken = upgradeSuperToken;
    }

    function _fundSignerAndApprove(TestToken underlying, VmSafe.Wallet memory signer, uint256 amount, address spender)
        internal
    {
        underlying.mint(signer.addr, amount);
        vm.prank(signer.addr);
        underlying.approve(spender, amount);
    }

    function _toPermit2MacroParams(
        IPermit2.PermitTransferFrom memory permit,
        address owner,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory signature,
        address spender,
        address upgradeSuperToken
    ) internal pure returns (IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory) {
        IClearMacroForwarderV1WithPermit2.Permit2MacroParams memory p;
        p.permit = permit;
        p.owner = owner;
        p.witness = witness;
        p.witnessTypeString = witnessTypeString;
        p.signature = signature;
        p.spender = spender;
        p.upgradeSuperToken = upgradeSuperToken;
        return p;
    }
}
