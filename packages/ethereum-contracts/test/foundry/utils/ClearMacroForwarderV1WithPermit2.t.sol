// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ERC20 } from "@openzeppelin-v5/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin-v5/contracts/token/ERC20/extensions/ERC4626.sol";
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
    IClearMacroForwarderV1WithPermit2,
    IClearMacroPermit2Extension
} from "../../../contracts/interfaces/utils/IClearMacroForwarderV1WithPermit2.sol";
import { IClearMacro } from "../../../contracts/interfaces/utils/IClearMacro.sol";
import { ClearMacroForwarderV1 } from "../../../contracts/utils/ClearMacroForwarderV1.sol";
import { ClearMacroForwarderV1WithPermit2 } from "../../../contracts/utils/ClearMacroForwarderV1WithPermit2.sol";
import { Superfluid } from "../../../contracts/superfluid/Superfluid.sol";
import { TestToken } from "../../../contracts/utils/TestToken.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";
import { Permit2VaultDepositMacro } from "../macros/Permit2VaultDepositMacro.t.sol";

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
// Implements IClearMacro. Expects actionParams (token, amount); does a SuperToken upgrade from underlying.
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

    function buildBatchOperations(ISuperfluid, bytes memory actionParams, address /*account*/)
        external
        pure
        override
        returns (ISuperfluid.Operation[] memory operations)
    {
        (address token, uint256 amount) = abi.decode(actionParams, (address, uint256));
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

    function getActionTypeDefinition(bytes memory /*encodedPayload*/) external pure override returns (string memory) {
        return ACTION_TYPE_DEFINITION;
    }

    function getPrimaryTypeName(bytes memory /*encodedPayload*/) external pure override returns (string memory) {
        return PRIMARY_TYPE_NAME;
    }

    function getActionStructHash(bytes memory actionParams) external pure override returns (bytes32) {
        (address token, uint256 amount) = abi.decode(actionParams, (address, uint256));
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

    function getActionTypeDefinition(bytes memory /*encodedPayload*/) external pure override returns (string memory) {
        return ACTION_TYPE_DEFINITION;
    }

    function getPrimaryTypeName(bytes memory /*encodedPayload*/) external pure override returns (string memory) {
        return PRIMARY_TYPE_NAME;
    }

    function getActionStructHash(bytes memory actionParams) external pure override returns (bytes32) {
        (address token, uint256 amount) = abi.decode(actionParams, (address, uint256));
        string memory description = _buildDescription(token, amount);
        bytes32 actionTypeHash = keccak256(abi.encodePacked(ACTION_TYPE_DEFINITION));
        return keccak256(abi.encode(actionTypeHash, keccak256(bytes(description))));
    }
}

/// @dev Minimal ERC-4626 vault for Permit2 vault-deposit macro tests.
contract TestERC4626Vault is ERC4626 {
    constructor(ERC20 asset_) ERC20("Test Vault", "vTKN") ERC4626(asset_) {}
}

// ============== Test Contract ==============

contract ClearMacroForwarderV1WithPermit2Test is FoundrySuperfluidTester {
    ClearMacroForwarderV1WithPermit2 internal forwarder;
    MinimalClearMacroForPermit2Test internal minimalClearMacro;
    MinimalClearMacroEmptyOps internal minimalClearMacroEmptyOps;
    Permit2VaultDepositMacro internal vaultDepositMacro;
    TestERC4626Vault internal vault;
    address internal permit2DomainVerifyingContract;

    constructor() FoundrySuperfluidTester(5) {}

    function setUp() public override {
        super.setUp();
        // Etch Permit2 bytecode at canonical address for local testing
        address deployed = DeployPermit2.deployPermit2();
        vm.etch(PERMIT2_CANONICAL, deployed.code);
        // The bytecode is etched onto the canonical Permit2 address, but the deployed runtime keeps
        // the immutable-cached domain separator from the original deployment. We keep that original
        // address so the JSON EIP-712 domain in tests matches the DOMAIN_SEPARATOR() used on-chain.
        permit2DomainVerifyingContract = deployed;
        forwarder = new ClearMacroForwarderV1WithPermit2(sf.host);
        minimalClearMacro = new MinimalClearMacroForPermit2Test();
        minimalClearMacroEmptyOps = new MinimalClearMacroEmptyOps();
        vaultDepositMacro = new Permit2VaultDepositMacro();
        vault = new TestERC4626Vault(token);

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

    function testRunPermit2AndMacroMatchesJsonTypedData() external {
        VmSafe.Wallet memory signer = vm.createWallet("jsonTypedDataSigner");
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getTestPayload(minimalClearMacroEmptyOps);
        IPermit2.PermitTransferFrom memory permit = _makePermit(address(token), TEST_AMOUNT);
        bytes32 witness = forwarder.getPermit2WitnessStructHash(
            minimalClearMacroEmptyOps, params, address(superToken)
        );
        string memory witnessTypeString = forwarder.getPermit2WitnessTypeString(minimalClearMacroEmptyOps, params);
        _assertPermit2TypeHashesAreCanonical(witnessTypeString);
        _assertPermit2DomainSeparatorMatches();

        bytes32 digestFromJson = vm.eip712HashTypedData(
            _getPermit2DataToBeSignedJson(permit, address(forwarder), params, address(superToken))
        );
        bytes32 digestFromSolidity = _computePermit2Digest(
            permit, address(forwarder), witness, witnessTypeString
        );
        assertEq(digestFromJson, digestFromSolidity, "Permit2 digest mismatch vs vm.eip712HashTypedData");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digestFromJson);
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _toPermit2Context(
            permit,
            signer.addr,
            witness,
            witnessTypeString,
            abi.encodePacked(r, s, v),
            address(forwarder),
            address(superToken)
        );

        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params));
        assertEq(superToken.balanceOf(signer.addr), TEST_AMOUNT, "signer should receive upgraded SuperTokens");
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
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context =
            _buildPermit2Context(signer, address(this), address(0), minimalClearMacro, params, token, TEST_AMOUNT);
        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacro, params));
        assertEq(
            superToken.balanceOf(signer.addr),
            signerSuperBalanceBefore + TEST_AMOUNT,
            "signer super token balance should increase by TEST_AMOUNT"
        );
    }

    /// Permit2 hashes `spender` as `msg.sender` (see PermitHash.hashWithWitness). A mempool observer
    /// cannot consume the permit by calling Permit2 directly with a signature made for the forwarder.
    function testPermit2WitnessTransferFromRevertsWhenCallerIsNotSignedSpender() external {
        VmSafe.Wallet memory signer = vm.createWallet("permit2SpenderBindingSigner");
        address frontrunner = makeAddr("frontrunner");

        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getTestPayload(minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _buildPermit2Context(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );

        vm.prank(frontrunner);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        IPermit2(PERMIT2_CANONICAL).permitWitnessTransferFrom(
            permit2Context.permit,
            IPermit2.SignatureTransferDetails({ to: frontrunner, requestedAmount: TEST_AMOUNT }),
            permit2Context.owner,
            permit2Context.witness,
            permit2Context.witnessTypeString,
            permit2Context.signature
        );

        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params));
        assertEq(superToken.balanceOf(signer.addr), TEST_AMOUNT, "forwarder can still execute after failed replay");
    }

    /// @notice Permit2 pull + ERC-4626 deposit inside the macro batch.
    function testRunPermit2AndMacroDepositToVault(uint256 signerPrivateKey) external {
        signerPrivateKey = bound(signerPrivateKey, 1, SECP256K1_ORDER - 1);
        VmSafe.Wallet memory signer = vm.createWallet(signerPrivateKey);
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        string memory description = "Deposit underlying into test vault";
        Permit2VaultDepositMacro.ExecutionParams memory execution = Permit2VaultDepositMacro.ExecutionParams({
            owner: signer.addr,
            token: address(token),
            amount: TEST_AMOUNT,
            permitNonce: 0,
            permitDeadline: block.timestamp + 3600,
            witness: bytes32(0),
            witnessTypeString: "",
            permit2Signature: bytes("")
        });

        IClearMacroForwarderV1.Security memory security = IClearMacroForwarderV1.Security({
            domain: SECURITY_DOMAIN,
            macroContract: address(vaultDepositMacro),
            provider: SECURITY_PROVIDER,
            validAfter: 0,
            validBefore: 0,
            nonce: DEFAULT_NONCE
        });

        bytes memory actionParamsForWitness =
            vaultDepositMacro.encodeActionParams(description, address(vault), execution);
        bytes memory encodedPayloadForWitness = forwarder.encodeParams(actionParamsForWitness, security);

        IPermit2.PermitTransferFrom memory permit = _makePermit(address(token), TEST_AMOUNT);

        (bytes32 witness, string memory witnessTypeString, bytes memory signature) = _signPermit(
            signer,
            permit,
            address(vaultDepositMacro),
            vaultDepositMacro,
            encodedPayloadForWitness,
            address(0)
        );

        execution.permit2Signature = signature;
        execution.witness = witness;
        execution.witnessTypeString = witnessTypeString;
        bytes memory encodedPayload =
            forwarder.encodeParams(vaultDepositMacro.encodeActionParams(description, address(vault), execution), security);

        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context;
        permit2Context.permit = permit;
        permit2Context.owner = signer.addr;
        permit2Context.witness = witness;
        permit2Context.witnessTypeString = witnessTypeString;
        permit2Context.signature = signature;
        permit2Context.spender = address(vaultDepositMacro);
        permit2Context.upgradeSuperToken = address(0);

        assertTrue(forwarder.runPermit2AndMacro(permit2Context, vaultDepositMacro, encodedPayload));
        assertEq(vault.balanceOf(signer.addr), TEST_AMOUNT, "signer should receive vault shares");
        assertEq(token.balanceOf(signer.addr), 0, "signer underlying should be consumed");
    }

    function testVaultDepositWitnessIgnoresPermit2Signature() external view {
        string memory description = "Deposit underlying into test vault";
        Permit2VaultDepositMacro.ExecutionParams memory execution = Permit2VaultDepositMacro.ExecutionParams({
            owner: address(0xCAFE),
            token: address(token),
            amount: TEST_AMOUNT,
            permitNonce: 0,
            permitDeadline: block.timestamp + 3600,
            witness: bytes32(0),
            witnessTypeString: "",
            permit2Signature: bytes("")
        });

        IClearMacroForwarderV1.Security memory security = IClearMacroForwarderV1.Security({
            domain: SECURITY_DOMAIN,
            macroContract: address(vaultDepositMacro),
            provider: SECURITY_PROVIDER,
            validAfter: 0,
            validBefore: 0,
            nonce: DEFAULT_NONCE
        });

        bytes memory withoutSig = vaultDepositMacro.encodeActionParams(description, address(vault), execution);
        execution.permit2Signature = hex"01";
        bytes memory withSig = vaultDepositMacro.encodeActionParams(description, address(vault), execution);

        assertEq(
            forwarder.getPermit2WitnessStructHash(
                vaultDepositMacro, forwarder.encodeParams(withoutSig, security), address(0)
            ),
            forwarder.getPermit2WitnessStructHash(
                vaultDepositMacro, forwarder.encodeParams(withSig, security), address(0)
            )
        );
    }

    /// With implied upgrade: spender is forwarder; signer approves Permit2.
    /// Forwarder pulls via Permit2, upgrades to signer, runs macro (empty ops).
    function testRunPermit2AndMacroWithImpliedUpgrade(uint256 signerPrivateKey) external {
        signerPrivateKey = bound(signerPrivateKey, 1, SECP256K1_ORDER - 1);
        VmSafe.Wallet memory signer = vm.createWallet(signerPrivateKey);
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getTestPayload(minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _buildPermit2Context(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );
        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params));
        assertEq(superToken.balanceOf(signer.addr), TEST_AMOUNT, "signer should have received upgraded SuperTokens");
    }

    function testRunPermit2AndMacroWithImpliedUpgradeEmitsEvents(uint256 signerPrivateKey) external {
        signerPrivateKey = bound(signerPrivateKey, 1, SECP256K1_ORDER - 1);
        VmSafe.Wallet memory signer = vm.createWallet(signerPrivateKey);
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getTestPayload(minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _buildPermit2Context(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );

        vm.expectEmit(true, true, true, true, address(forwarder));
        emit IClearMacroPermit2Extension.Permit2UpgradeExecuted(
            signer.addr, address(token), address(superToken), TEST_AMOUNT, TEST_AMOUNT
        );
        vm.expectEmit(true, true, true, true, address(forwarder));
        emit IClearMacroForwarderV1.MacroExecuted(
            signer.addr, address(minimalClearMacroEmptyOps), keccak256(bytes(SECURITY_PROVIDER))
        );
        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params));
    }

    function testRunPermit2AndMacroWithoutUpgradeEmitsMacroExecutedOnly(uint256 signerPrivateKey) external {
        signerPrivateKey = bound(signerPrivateKey, 1, SECP256K1_ORDER - 1);
        VmSafe.Wallet memory signer = vm.createWallet(signerPrivateKey);
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, address(superToken));

        bytes memory params = _getTestPayload(minimalClearMacro);
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context =
            _buildPermit2Context(signer, address(this), address(0), minimalClearMacro, params, token, TEST_AMOUNT);

        vm.expectEmit(true, true, true, true, address(forwarder));
        emit IClearMacroForwarderV1.MacroExecuted(
            signer.addr, address(minimalClearMacro), keccak256(bytes(SECURITY_PROVIDER))
        );
        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacro, params));
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
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _buildPermit2Context(
            signer,
            address(forwarder),
            address(localSuperToken),
            minimalClearMacroEmptyOps,
            params,
            underlying,
            underlyingAmount
        );

        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params));
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
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _buildPermit2Context(
            signer,
            address(forwarder),
            address(localSuperToken),
            minimalClearMacroEmptyOps,
            params,
            underlying,
            underlyingAmount
        );

        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params));
        assertEq(localSuperToken.balanceOf(signer.addr), expectedSuperAmount, "scaled-down super amount mismatch");
    }

    /// SELF_PROVIDER: signer uses provider "self" and calls runPermit2AndMacro as msg.sender == signer.
    function testRunPermit2AndMacroSelfRelaySucceeds() external {
        VmSafe.Wallet memory signer = vm.createWallet("selfRelaySigner");
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getSelfRelayPayload();
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _buildPermit2Context(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );
        vm.prank(signer.addr);
        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params));
        assertEq(superToken.balanceOf(signer.addr), TEST_AMOUNT, "signer should have received upgraded SuperTokens");
    }

    /// SELF_PROVIDER: when provider is "self", caller must be signer.
    function testRunPermit2AndMacroSelfRelayRevertsWhenDifferentCaller() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getSelfRelayPayload();
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _buildPermit2Context(
            signer, address(forwarder), address(superToken), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );

        vm.expectRevert(abi.encodeWithSelector(
            ClearMacroForwarderV1.ProviderNotAuthorized.selector, "self", address(this)));
        vm.prank(address(this));
        forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params);
    }

    /// When upgradeSuperToken is zero and spender is forwarder: verify signature, run macro (no pull).
    function testRunPermit2AndMacroNoUpgradeWhenSpenderIsForwarder() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerAndApprove(token, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getTestPayload(minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _buildPermit2Context(
            signer, address(forwarder), address(0), minimalClearMacroEmptyOps, params, token, TEST_AMOUNT
        );
        assertTrue(forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params));
    }

    function testRunPermit2AndMacroRevertsOnPermitTokenMismatch() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        TestToken wrongUnderlying = new TestToken("Wrong Token", "WRONG", 18, type(uint256).max);
        _fundSignerAndApprove(wrongUnderlying, signer, TEST_AMOUNT, PERMIT2_CANONICAL);

        bytes memory params = _getTestPayload(minimalClearMacroEmptyOps);
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context;
        permit2Context.permit = _makePermit(address(wrongUnderlying), TEST_AMOUNT);
        (permit2Context.witness, permit2Context.witnessTypeString, permit2Context.signature) = _signPermit(
            signer, permit2Context.permit, address(forwarder), minimalClearMacroEmptyOps, params, address(superToken)
        );
        permit2Context.owner = signer.addr;
        permit2Context.spender = address(forwarder);
        permit2Context.upgradeSuperToken = address(superToken);

        vm.expectRevert(abi.encodeWithSelector(ClearMacroForwarderV1.InvalidPayload.selector, "permit token mismatch"));
        forwarder.runPermit2AndMacro(permit2Context, minimalClearMacroEmptyOps, params);
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
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _toPermit2Context(
            permit, signer.addr, witness, witnessTypeString, badSignature, address(this), address(0)
        );
        forwarder.runPermit2AndMacro(permit2Context, minimalClearMacro, params);
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
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context = _toPermit2Context(
            permit, signer.addr, wrongWitness, witnessTypeString, signature, address(this), address(0)
        );
        forwarder.runPermit2AndMacro(permit2Context, minimalClearMacro, params);
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

    function _assertPermit2TypeHashesAreCanonical(string memory witnessTypeString) internal pure {
        string memory witnessInnerTypeDef = string(abi.encodePacked(
            "ClearMacro(address upgradeSuperToken,Action action,Security security)",
            ACTION_TYPEDEF,
            SECURITY_TYPEDEF
        ));
        assertEq(
            keccak256(bytes(witnessInnerTypeDef)),
            vm.eip712HashType(witnessInnerTypeDef),
            "ClearMacro witness inner type is not canonical EIP-712"
        );

        string memory fullTypeDef = string(abi.encodePacked(
            "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,",
            witnessTypeString
        ));
        assertEq(
            keccak256(bytes(fullTypeDef)),
            vm.eip712HashType(fullTypeDef),
            "PermitWitnessTransferFrom witness type is not canonical EIP-712"
        );
    }

    function _assertPermit2DomainSeparatorMatches() internal view {
        bytes32 expectedDomainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("Permit2")),
            block.chainid,
            permit2DomainVerifyingContract
        ));
        assertEq(
            IPermit2(PERMIT2_CANONICAL).DOMAIN_SEPARATOR(),
            expectedDomainSeparator,
            "Permit2 domain separator mismatch"
        );
    }

    function _makePermit(address tokenAddr, uint256 amount) internal view returns (IPermit2.PermitTransferFrom memory) {
        return IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({ token: tokenAddr, amount: amount }),
            nonce: 0,
            deadline: block.timestamp + 3600
        });
    }

    function _getPermit2DataToBeSignedJson(
        IPermit2.PermitTransferFrom memory permit,
        address spender,
        bytes memory params,
        address upgradeSuperToken
    ) internal view returns (string memory) {
        IClearMacroForwarderV1.Payload memory payload =
            abi.decode(params, (IClearMacroForwarderV1.Payload));
        return string(abi.encodePacked(
            _getPermit2PrefixJson(),
            _getPermit2DomainJson(
                Strings.toString(block.chainid),
                Strings.toHexString(permit2DomainVerifyingContract)
            ),
            _getPermit2MessageJson(
                permit,
                Strings.toHexString(spender),
                _getPermit2WitnessJson(payload.action.params, upgradeSuperToken, payload.security)
            ),
            "}"
        ));
    }

    function _getExpectedDescription(bytes memory actionParams) internal pure returns (string memory) {
        (address targetSuperToken, uint256 amount) = abi.decode(actionParams, (address, uint256));
        return string.concat(
            "Upgrade ",
            Strings.toString(amount),
            " ",
            Strings.toHexString(targetSuperToken)
        );
    }

    function _getPermit2PrefixJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            "{",
            "\"types\": {", _getPermit2TypesJson(), "},",
            "\"primaryType\": \"PermitWitnessTransferFrom\","
        ));
    }

    function _getPermit2DomainJson(string memory chainIdStr, string memory permit2Str)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(
            "\"domain\": {",
            "\"name\": \"Permit2\",",
            "\"chainId\": ", chainIdStr, ",",
            "\"verifyingContract\": \"", permit2Str, "\""
        ));
    }

    function _getPermit2MessageJson(
        IPermit2.PermitTransferFrom memory permit,
        string memory spenderStr,
        string memory witnessJson
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "},",
            "\"message\": {",
            "\"permitted\": {\"token\": \"", Strings.toHexString(permit.permitted.token), "\", \"amount\": \"",
            Strings.toString(permit.permitted.amount), "\"},",
            "\"spender\": \"", spenderStr, "\",",
            "\"nonce\": \"", Strings.toString(permit.nonce), "\",",
            "\"deadline\": \"", Strings.toString(permit.deadline), "\",",
            "\"witness\": ", witnessJson,
            "}"
        ));
    }

    function _getPermit2WitnessJson(
        bytes memory actionParams,
        address upgradeSuperToken,
        IClearMacroForwarderV1.Security memory security
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "{",
            "\"upgradeSuperToken\": \"", Strings.toHexString(upgradeSuperToken), "\",",
            "\"action\": ", _getPermit2ActionJson(actionParams), ",",
            "\"security\": ", _getPermit2SecurityJson(security),
            "}"
        ));
    }

    function _getPermit2ActionJson(bytes memory actionParams) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "{\"description\": \"", _getExpectedDescription(actionParams), "\"}"
        ));
    }

    function _getPermit2SecurityJson(IClearMacroForwarderV1.Security memory security)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(
            "{",
            "\"domain\": \"", security.domain, "\",",
            "\"macroContract\": \"", Strings.toHexString(security.macroContract), "\",",
            "\"provider\": \"", security.provider, "\",",
            "\"validAfter\": \"", Strings.toString(security.validAfter), "\",",
            "\"validBefore\": \"", Strings.toString(security.validBefore), "\",",
            "\"nonce\": \"", Strings.toString(security.nonce), "\"",
            "}"
        ));
    }

    function _getPermit2TypesJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            _getPermit2EIP712DomainTypeJson(),
            _getPermit2PermitWitnessTransferFromTypeJson(),
            _getPermit2TokenPermissionsTypeJson(),
            _getPermit2ClearMacroTypeJson(),
            _getPermit2ActionTypeJson(),
            _getPermit2SecurityTypeJson()
        ));
    }

    function _getPermit2EIP712DomainTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            "\"EIP712Domain\": [",
            "{\"name\": \"name\", \"type\": \"string\"},",
            "{\"name\": \"chainId\", \"type\": \"uint256\"},",
            "{\"name\": \"verifyingContract\", \"type\": \"address\"}",
            "],"
        ));
    }

    function _getPermit2PermitWitnessTransferFromTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            "\"PermitWitnessTransferFrom\": [",
            "{\"name\": \"permitted\", \"type\": \"TokenPermissions\"},",
            "{\"name\": \"spender\", \"type\": \"address\"},",
            "{\"name\": \"nonce\", \"type\": \"uint256\"},",
            "{\"name\": \"deadline\", \"type\": \"uint256\"},",
            "{\"name\": \"witness\", \"type\": \"ClearMacro\"}",
            "],"
        ));
    }

    function _getPermit2TokenPermissionsTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            "\"TokenPermissions\": [",
            "{\"name\": \"token\", \"type\": \"address\"},",
            "{\"name\": \"amount\", \"type\": \"uint256\"}",
            "],"
        ));
    }

    function _getPermit2ClearMacroTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            "\"ClearMacro\": [",
            "{\"name\": \"upgradeSuperToken\", \"type\": \"address\"},",
            "{\"name\": \"action\", \"type\": \"Action\"},",
            "{\"name\": \"security\", \"type\": \"Security\"}",
            "],"
        ));
    }

    function _getPermit2ActionTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            "\"Action\": [",
            "{\"name\": \"description\", \"type\": \"string\"}",
            "],"
        ));
    }

    function _getPermit2SecurityTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            "\"Security\": [",
            "{\"name\": \"domain\", \"type\": \"string\"},",
            "{\"name\": \"macroContract\", \"type\": \"address\"},",
            "{\"name\": \"provider\", \"type\": \"string\"},",
            "{\"name\": \"validAfter\", \"type\": \"uint256\"},",
            "{\"name\": \"validBefore\", \"type\": \"uint256\"},",
            "{\"name\": \"nonce\", \"type\": \"uint256\"}",
            "]"
        ));
    }

    function _signPermit(
        VmSafe.Wallet memory signer,
        IPermit2.PermitTransferFrom memory permit,
        address spender,
        IClearMacro m,
        bytes memory encodedPayload,
        address upgradeSuperToken
    ) internal returns (bytes32 witness, string memory witnessTypeString, bytes memory signature) {
        witness = forwarder.getPermit2WitnessStructHash(m, encodedPayload, upgradeSuperToken);
        witnessTypeString = forwarder.getPermit2WitnessTypeString(m, encodedPayload);
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

    function _buildPermit2Context(
        VmSafe.Wallet memory signer,
        address spender,
        address upgradeSuperToken,
        IClearMacro m,
        bytes memory encodedPayload,
        TestToken permitToken,
        uint256 permitAmount
    ) internal returns (IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context) {
        permit2Context.permit = _makePermit(address(permitToken), permitAmount);
        (permit2Context.witness, permit2Context.witnessTypeString, permit2Context.signature) =
            _signPermit(signer, permit2Context.permit, spender, m, encodedPayload, upgradeSuperToken);
        permit2Context.owner = signer.addr;
        permit2Context.spender = spender;
        permit2Context.upgradeSuperToken = upgradeSuperToken;
    }

    function _fundSignerAndApprove(TestToken underlying, VmSafe.Wallet memory signer, uint256 amount, address spender)
        internal
    {
        underlying.mint(signer.addr, amount);
        vm.prank(signer.addr);
        underlying.approve(spender, amount);
    }

    function _toPermit2Context(
        IPermit2.PermitTransferFrom memory permit,
        address owner,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory signature,
        address spender,
        address upgradeSuperToken
    ) internal pure returns (IClearMacroForwarderV1WithPermit2.Permit2Context memory) {
        IClearMacroForwarderV1WithPermit2.Permit2Context memory permit2Context;
        permit2Context.permit = permit;
        permit2Context.owner = owner;
        permit2Context.witness = witness;
        permit2Context.witnessTypeString = witnessTypeString;
        permit2Context.signature = signature;
        permit2Context.spender = spender;
        permit2Context.upgradeSuperToken = upgradeSuperToken;
        return permit2Context;
    }
}
