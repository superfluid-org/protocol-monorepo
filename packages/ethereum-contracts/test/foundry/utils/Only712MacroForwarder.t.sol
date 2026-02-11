// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { IAccessControl } from "@openzeppelin-v5/contracts/access/IAccessControl.sol";
import { BatchOperation, ISuperfluid, ISuperfluidToken } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IUserDefined712Macro } from "../../../contracts/interfaces/utils/IUserDefinedMacro.sol";
import { Strings } from "@openzeppelin-v5/contracts/utils/Strings.sol";
import { Only712MacroForwarder, NonceManager } from "../../../contracts/utils/Only712MacroForwarder.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";

string constant PRIMARY_TYPE_NAME = "MinimalExample";
string constant ACTION_TYPEDEF = "Action(string description)";
string constant SECURITY_DOMAIN = "minimalmacro.xyz";
string constant SECURITY_PROVIDER = "macros.superfluid.eth";
string constant SECURITY_TYPEDEF = "Security(string domain,string provider,uint256 validAfter,uint256 validBefore,uint256 nonce)";
uint256 constant DEFAULT_NONCE = uint256(1) << 64;
uint256 constant TEST_AMOUNT = 100e18;

// ============== Minimal macro for Only712MacroForwarder ==============
// Implements IUserDefined712Macro and uses *no* postCheck logic.
// Expects params (token, amount); does a SuperToken upgrade from underlying.
// Shows how the params can be different from the type definition, while still being part of the signed data
// (via the dynamic construction of the description string from the params)
contract Minimal712Macro is IUserDefined712Macro {

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

// ============== Test Contract ==============

contract Only712MacroForwarderTest is FoundrySuperfluidTester {
    Only712MacroForwarder internal forwarder;
    Minimal712Macro internal minimal712Macro;

    constructor() FoundrySuperfluidTester(5) { }

    function setUp() public override {
        super.setUp();
        forwarder = new Only712MacroForwarder(sf.host);
        minimal712Macro = new Minimal712Macro();

        IAccessControl acl = IAccessControl(sf.host.getSimpleACL());
        vm.prank(address(sfDeployer));
        acl.grantRole(keccak256(bytes(SECURITY_PROVIDER)), address(this));

        vm.prank(address(sfDeployer));
        sf.governance.enableTrustedForwarder(sf.host, ISuperfluidToken(address(0)), address(forwarder));
    }

    function testEncodeParams(
        uint256 nonce,
        uint256 validAfter,
        uint256 validBefore,
        address token,
        uint256 amount
    ) external view {
        Only712MacroForwarder.PrimaryType memory payload = Only712MacroForwarder.PrimaryType({
            action: Only712MacroForwarder.ActionType({ actionParams: abi.encode(token, amount) }),
            security: Only712MacroForwarder.SecurityType({
                domain: SECURITY_DOMAIN,
                provider: SECURITY_PROVIDER,
                validAfter: validAfter,
                validBefore: validBefore,
                nonce: nonce
            })
        });
        bytes memory localPayload = abi.encode(payload);
        
        bytes memory forwarderPayload = forwarder.encodeParams(
            abi.encode(token, amount),
            Only712MacroForwarder.SecurityType({
                domain: SECURITY_DOMAIN,
                provider: SECURITY_PROVIDER,
                validAfter: validAfter,
                validBefore: validBefore,
                nonce: nonce
            })
        );
        assertEq(localPayload, forwarderPayload, "encodeParams output must match manual PrimaryType encoding");
    }

    function testRunMacro(uint256 signerPrivateKey) external {
        signerPrivateKey = bound(signerPrivateKey, 1, SECP256K1_ORDER - 1);
        VmSafe.Wallet memory signer = vm.createWallet(signerPrivateKey);
        _fundSignerForUpgrade(signer, 1);

        uint256 signerSuperBalanceBefore = superToken.balanceOf(signer.addr);
        bytes memory params = _getTestPayload();
        bytes memory signatureVRS = _signPayload(signer, params);
        assertTrue(_runMacroAs(address(this), signer.addr, params, signatureVRS));
        assertEq(superToken.balanceOf(signer.addr), signerSuperBalanceBefore + TEST_AMOUNT, "signer super token balance should increase by TEST_AMOUNT");
    }

    function testRevertsWhenCallerMissingProviderRole() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        bytes memory params = _getTestPayload();
        bytes memory signatureVRS = _signPayload(signer, params);
        vm.expectRevert(abi.encodeWithSelector(
            Only712MacroForwarder.ProviderNotAuthorized.selector, SECURITY_PROVIDER, address(0xbad)));
        _runMacroAs(address(0xbad), signer.addr, params, signatureVRS);
    }

    function testDigestCalculation() external view {
        // check the type definition (build same way as forwarder: primary + action typedef + security typedef)
        string memory typeDefinition = forwarder.getTypeDefinition(minimal712Macro, _getTestPayload());
        string memory expectedTypeDefinition = string(abi.encodePacked(
            PRIMARY_TYPE_NAME,
            "(Action action,Security security)",
            ACTION_TYPEDEF,
            SECURITY_TYPEDEF
        ));
        assertEq(typeDefinition, expectedTypeDefinition, "typeDefinition mismatch");

        // check the type hash
        bytes32 typeHash = forwarder.getTypeHash(minimal712Macro, _getTestPayload());
        bytes32 expectedTypeHash = vm.eip712HashType(expectedTypeDefinition);
        assertEq(typeHash, expectedTypeHash, "typeHash mismatch");

        // check the struct hash (includes type hash and the struct data)
        bytes memory payload = _getTestPayload();
        bytes32 structHash = forwarder.getStructHash(minimal712Macro, payload);
        bytes32 actionStructHash = minimal712Macro.getActionStructHash(abi.encode(address(superToken), TEST_AMOUNT));
        bytes32 securityTypeHash = keccak256(abi.encodePacked(SECURITY_TYPEDEF));
        bytes32 securityStructHash = keccak256(abi.encode(
            securityTypeHash,
            keccak256(bytes(SECURITY_DOMAIN)),
            keccak256(bytes(SECURITY_PROVIDER)),
            uint256(0),
            uint256(0),
            DEFAULT_NONCE
        ));
        bytes32 expectedStructHash = keccak256(abi.encode(
            expectedTypeHash,
            actionStructHash,
            securityStructHash
        ));
        assertEq(structHash, expectedStructHash, "structHash mismatch");

        // check the digest
        bytes32 digest = forwarder.getDigest(minimal712Macro, payload);
        string memory dataToBeSignedJson = _getDataToBeSignedJson();
        console.log(dataToBeSignedJson);
        bytes32 expectedDigest = vm.eip712HashTypedData(dataToBeSignedJson);
        assertEq(digest, expectedDigest, "digest mismatch");
    }

    function testGetNonce(uint192 key) external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerForUpgrade(signer, 10);

        for (uint256 i = 0; i < 10; i++) {
            uint256 nonce = forwarder.getNonce(signer.addr, key);
            bytes memory params = _getPayloadWithTokenAmount(nonce, 0, 0, address(superToken), TEST_AMOUNT);
            bytes memory signatureVRS = _signPayload(signer, params);
            assertTrue(_runMacroAs(address(this), signer.addr, params, signatureVRS), "runMacro with getNonce() nonce should succeed");
        }
    }

    function testCannotReuseNonce(uint192 key) external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerForUpgrade(signer, 2);

        uint256 nonce = forwarder.getNonce(signer.addr, key);
        bytes memory params = _getPayloadWithTokenAmount(nonce, 0, 0, address(superToken), TEST_AMOUNT);
        bytes memory signatureVRS = _signPayload(signer, params);
        assertTrue(_runMacroAs(address(this), signer.addr, params, signatureVRS));

        vm.expectRevert(abi.encodeWithSelector(NonceManager.InvalidNonce.selector, signer.addr, nonce));
        _runMacroAs(address(this), signer.addr, params, signatureVRS);
    }

    function testValidityWindow(uint32 t0_raw, uint32 t1_raw) external {
        uint256 t0 = uint256(t0_raw);
        uint256 t1 = uint256(t1_raw);

        vm.warp(t0);

        VmSafe.Wallet memory signer = vm.createWallet("signer");
        _fundSignerForUpgrade(signer, 2);
        uint256 nonce = forwarder.getNonce(signer.addr, 0);
        bytes memory params = _getPayloadWithTokenAmount(nonce, t0, t1, address(superToken), TEST_AMOUNT);
        bytes memory signatureVRS = _signPayload(signer, params);

        // Before validAfter: revert (skip when t0 == 0 to avoid underflow)
        if (t0 > 0) {
            vm.warp(t0 - 1);
            vm.expectRevert(abi.encodeWithSelector(
                Only712MacroForwarder.OutsideValidityWindow.selector, t0 - 1, t1, t0));
            _runMacroAs(address(this), signer.addr, params, signatureVRS);
        }

        // Within window: success when non-empty (t1 == 0 or t1 >= t0); else revert
        if (t1 == 0 || t1 >= t0) {
            vm.warp(t1 == 0 ? t0 + 100 : t0 + (t1 - t0) / 2);
            assertTrue(_runMacroAs(address(this), signer.addr, params, signatureVRS));
        } else {
            vm.warp(t0);
            vm.expectRevert(abi.encodeWithSelector(
                Only712MacroForwarder.OutsideValidityWindow.selector, t0, t1, t0));
            _runMacroAs(address(this), signer.addr, params, signatureVRS);
        }

        // After validBefore: revert (use non-zero validBefore so 0 = unbounded is not used here)
        uint256 expiry = t0 > 0 ? t0 : 1;
        nonce = forwarder.getNonce(signer.addr, 0);
        params = _getPayloadWithTokenAmount(nonce, 0, expiry, address(superToken), TEST_AMOUNT);
        signatureVRS = _signPayload(signer, params);
        vm.warp(expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(
            Only712MacroForwarder.OutsideValidityWindow.selector, expiry + 1, expiry, uint256(0)));
        _runMacroAs(address(this), signer.addr, params, signatureVRS);
    }

    /// For a given key, nonces must be used in sequence (0, 1, 2, ...). Skipping must revert.
    function testNonceEnforceInSequence(uint192 key) external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
            _fundSignerForUpgrade(signer, 2);

        // Using seq=1 before seq=0 must revert
        uint256 nonceSeq1 = (uint256(key) << 64) | 1;
        bytes memory paramsSeq1 = _getPayloadWithTokenAmount(nonceSeq1, 0, 0, address(superToken), TEST_AMOUNT);
        bytes memory sig1 = _signPayload(signer, paramsSeq1);

        vm.expectRevert(abi.encodeWithSelector(NonceManager.InvalidNonce.selector, signer.addr, nonceSeq1));
        _runMacroAs(address(this), signer.addr, paramsSeq1, sig1);

        // seq=0 must succeed
        uint256 nonceSeq0 = uint256(key) << 64;
        bytes memory paramsSeq0 = _getPayloadWithTokenAmount(nonceSeq0, 0, 0, address(superToken), TEST_AMOUNT);
        bytes memory sig0 = _signPayload(signer, paramsSeq0);
        assertTrue(_runMacroAs(address(this), signer.addr, paramsSeq0, sig0));

        // now seq=1 must succeed
        assertTrue(_runMacroAs(address(this), signer.addr, paramsSeq1, sig1));
    }

    function _fundSignerForUpgrade(VmSafe.Wallet memory signer, uint256 runs) internal {
        uint256 total = TEST_AMOUNT * runs;
        vm.prank(alice);
        token.transfer(signer.addr, total);
        vm.prank(signer.addr);
        token.approve(address(superToken), total);
    }

    function _getPayloadWithTokenAmount(
        uint256 nonce,
        uint256 validAfter,
        uint256 validBefore,
        address token,
        uint256 amount
    ) internal view returns (bytes memory) {
        return forwarder.encodeParams(
            abi.encode(token, amount),
            Only712MacroForwarder.SecurityType({
                domain: SECURITY_DOMAIN,
                provider: SECURITY_PROVIDER,
                validAfter: validAfter,
                validBefore: validBefore,
                nonce: nonce
            })
        );
    }

    function _getTestPayload() internal view returns (bytes memory) {
        return _getPayloadWithTokenAmount(DEFAULT_NONCE, 0, 0, address(superToken), TEST_AMOUNT);
    }

    // example: https://github.com/vaquita-fi/vaquita-lisk/blob/c4964af9157c9cca9cfb167ac1a4450e36edb29e/contracts/test/VaquitaPool.t.sol#L142
    // The splitting up into many functions avoids stack too deep error.
    function _getDataToBeSignedJson() internal view returns (string memory) {
        return string(abi.encodePacked(
            '{',
            '"types": {', _getTypesJson(), '},',
            '"primaryType": "MinimalExample",', // leaving this as literal in order to fit onto the stack
            '"domain": {', _getDomainJson(), '},',
            '"message": {',
            '"action": {', _getActionJson(), '},',
            '"security": {', _getSecurityJson(), '}',
            '}',
            '}'
        ));
    }

    function _getTypesJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            _getEIP712DomainTypeJson(),
            _getMinimalExampleTypeJson(),
            _getActionTypeJson(),
            _getSecurityTypeJson()
        ));
    }

    function _getEIP712DomainTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"EIP712Domain": [',
            '{"name": "name", "type": "string"},',
            '{"name": "version", "type": "string"},',
            '{"name": "chainId", "type": "uint256"},',
            '{"name": "verifyingContract", "type": "address"}',
            '],'
        ));
    }

    function _getMinimalExampleTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"MinimalExample": [',
            '{"name": "action", "type": "Action"},',
            '{"name": "security", "type": "Security"}',
            '],'
        ));
    }

    function _getActionTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"Action": [',
            '{"name": "description", "type": "string"}',
            '],'
        ));
    }

    function _getSecurityTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"Security": [',
            '{"name": "domain", "type": "string"},',
            '{"name": "provider", "type": "string"},',
            '{"name": "validAfter", "type": "uint256"},',
            '{"name": "validBefore", "type": "uint256"},',
            '{"name": "nonce", "type": "uint256"}',
            ']'
        ));
    }

    function _getDomainJson() internal view returns (string memory) {
        return string(abi.encodePacked(
            '"name": "ClearSigning",',
            '"version": "1",',
            '"chainId": ', vm.toString(block.chainid), ',',
            '"verifyingContract": "', vm.toString(address(forwarder)), '"'
        ));
    }

    function _getExpectedDescription() internal view returns (string memory) {
        return string.concat(
            "Upgrade ",
            Strings.toString(TEST_AMOUNT),
            " ",
            Strings.toHexString(address(superToken))
        );
    }

    function _getActionJson() internal view returns (string memory) {
        return string(abi.encodePacked(
            '"description": "', _getExpectedDescription(), '"'
        ));
    }

    function _getSecurityJson() internal pure returns (string memory) {
        // Use string for nonce so Foundry's JSON parser accepts 2^64 as uint256 (avoids type mismatch)
        return string(abi.encodePacked(
            '"domain": "', SECURITY_DOMAIN, '",',
            '"provider": "', SECURITY_PROVIDER, '",',
            '"validAfter": "0",',
            '"validBefore": "0",',
            '"nonce": "', vm.toString(DEFAULT_NONCE), '"'
        ));
    }

    function _runMacroAs(address relayer, address signer, bytes memory params, bytes memory signatureVRS)
        internal
        returns (bool)
    {
        vm.prank(relayer);
        return forwarder.runMacro(minimal712Macro, params, signer, signatureVRS);
    }

    function _signPayload(VmSafe.Wallet memory signer, bytes memory params) internal returns (bytes memory) {
        bytes32 digest = forwarder.getDigest(minimal712Macro, params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        return abi.encodePacked(r, s, v);
    }
}
