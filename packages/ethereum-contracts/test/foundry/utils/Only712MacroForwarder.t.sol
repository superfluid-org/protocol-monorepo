// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { IAccessControl } from "@openzeppelin-v5/contracts/access/IAccessControl.sol";
import { ISuperfluid, ISuperfluidToken } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IUserDefined712Macro } from "../../../contracts/interfaces/utils/IUserDefinedMacro.sol";
import { Only712MacroForwarder, NonceManager } from "../../../contracts/utils/Only712MacroForwarder.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";

string constant MESSAGE_TITLE = "Hello 712";
string constant PRIMARY_TYPE_NAME = "MinimalExample";
string constant META_DOMAIN = "minimalmacro.xyz";
string constant META_VERSION = "1";
string constant SECURITY_PROVIDER = "macros.superfluid.eth";
uint256 constant DEFAULT_NONCE = uint256(1) << 64;

// returns the encoded payload for the example macro (nonce = key 1, sequence 0)
function getTestPayload() pure returns (bytes memory) {
    return getPayloadWithNonce(DEFAULT_NONCE);
}

// returns the encoded payload with the given nonce (for nonce tests)
function getPayloadWithNonce(uint256 nonce) pure returns (bytes memory) {
    return getPayloadWithNonceAndTimeframe(nonce, 0, 0);
}

// returns the encoded payload with the given nonce and timeframe
function getPayloadWithNonceAndTimeframe(uint256 nonce, uint256 validAfter, uint256 validBefore) pure returns (bytes memory) {
    Only712MacroForwarder.Payload memory payload = Only712MacroForwarder.Payload({
        meta: Only712MacroForwarder.PayloadMeta({ domain: META_DOMAIN, version: META_VERSION }),
        message: Only712MacroForwarder.PayloadMessage({ title: MESSAGE_TITLE, customPayload: new bytes(0) }),
        security: Only712MacroForwarder.PayloadSecurity({
            provider: SECURITY_PROVIDER,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce
        })
    });
    return abi.encode(payload);
}

// ============== Minimal macro for Only712MacroForwarder ==============
// Implements IUserDefined712Macro and uses *no* postCheck logic.
// Message has only the required `title`; `customPayload` is expected to be empty.
contract Minimal712Macro is IUserDefined712Macro {

    string public constant MESSAGE_TYPE_DEFINITION = "Message(string title)";

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

    function getMessageTypeDefinition() external pure override returns (string memory) {
        return MESSAGE_TYPE_DEFINITION;
    }

    function getPrimaryTypeName() external pure override returns (string memory) {
        return PRIMARY_TYPE_NAME;
    }

    function getMessageStructHash(bytes memory message) external pure override returns (bytes32) {
        (string memory title, bytes memory customPayload) = abi.decode(message, (string, bytes));
        require(keccak256(bytes(title)) == keccak256(bytes(MESSAGE_TITLE)), "wrong title");
        require(customPayload.length == 0, "customPayload not empty");
        bytes32 messageTypeHash = keccak256(abi.encodePacked(MESSAGE_TYPE_DEFINITION));
        return keccak256(abi.encode(messageTypeHash, keccak256(bytes(title))));
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

        IAccessControl acl = IAccessControl(sf.host.getSimpleACL());
        vm.prank(address(sfDeployer));
        acl.grantRole(keccak256(bytes(SECURITY_PROVIDER)), address(this));

        vm.prank(address(sfDeployer));
        sf.governance.enableTrustedForwarder(sf.host, ISuperfluidToken(address(0)), address(forwarder));
    }

    function testRunMacro() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        (bytes memory params, bytes memory signatureVRS) = _signPayload(signer, DEFAULT_NONCE);
        assertTrue(_runMacroAs(address(this), signer.addr, params, signatureVRS));
    }

    function testRevertsWhenCallerMissingProviderRole() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        (bytes memory params, bytes memory signatureVRS) = _signPayload(signer, DEFAULT_NONCE);
        vm.expectRevert(abi.encodeWithSelector(
            Only712MacroForwarder.ProviderNotAuthorized.selector, SECURITY_PROVIDER, address(0xbad)));
        _runMacroAs(address(0xbad), signer.addr, params, signatureVRS);
    }

    function testDigestCalculation() external view {
        // check the type definition
        string memory typeDefinition = forwarder.getTypeDefinition(minimal712Macro);
        string memory expectedTypeDefinition = "MinimalExample(Meta meta,Message message,Security security)Message(string title)Meta(string domain,string version)Security(string provider,uint256 validAfter,uint256 validBefore,uint256 nonce)";
        assertEq(typeDefinition, expectedTypeDefinition, "typeDefinition mismatch");

        // check the type hash
        bytes32 typeHash = forwarder.getTypeHash(minimal712Macro);
        bytes32 expectedTypeHash = vm.eip712HashType(expectedTypeDefinition);
        assertEq(typeHash, expectedTypeHash, "typeHash mismatch");

        // check the struct hash (includes type hash and the struct data)
        bytes memory payload = getTestPayload();
        bytes32 structHash = forwarder.getStructHash(minimal712Macro, payload);
        bytes32 expectedStructHash = vm.eip712HashStruct(typeDefinition, payload);
        assertEq(structHash, expectedStructHash, "structHash mismatch");

        // check the digest
        bytes32 digest = forwarder.getDigest(minimal712Macro, payload);
        string memory dataToBeSignedJson = getDataToBeSignedJson();
        console.log(dataToBeSignedJson);
        bytes32 expectedDigest = vm.eip712HashTypedData(dataToBeSignedJson);
        assertEq(digest, expectedDigest, "digest mismatch");
    }

    function testGetNonce(uint192 key) external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");

        for (uint256 i = 0; i < 10; i++) {
            uint256 nonce = forwarder.getNonce(signer.addr, key);
            (bytes memory params, bytes memory signatureVRS) = _signPayload(signer, nonce);
            assertTrue(_runMacroAs(address(this), signer.addr, params, signatureVRS), "runMacro with getNonce() nonce should succeed");
        }
    }

    function testCannotReuseNonce(uint192 key) external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");

        uint256 nonce = forwarder.getNonce(signer.addr, key);
        (bytes memory params, bytes memory signatureVRS) = _signPayload(signer, nonce);
        assertTrue(_runMacroAs(address(this), signer.addr, params, signatureVRS));

        vm.expectRevert(abi.encodeWithSelector(NonceManager.InvalidNonce.selector, signer.addr, nonce));
        _runMacroAs(address(this), signer.addr, params, signatureVRS);
    }

    function testValidityWindow(uint32 t0_raw, uint32 t1_raw) external {
        uint256 t0 = uint256(t0_raw);
        uint256 t1 = uint256(t1_raw);

        vm.warp(t0);

        VmSafe.Wallet memory signer = vm.createWallet("signer");
        uint256 nonce = forwarder.getNonce(signer.addr, 0);
        (bytes memory params, bytes memory signatureVRS) = _signPayloadWithTimeframe(signer, nonce, t0, t1);

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
        (params, signatureVRS) = _signPayloadWithTimeframe(signer, nonce, 0, expiry);
        vm.warp(expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(
            Only712MacroForwarder.OutsideValidityWindow.selector, expiry + 1, expiry, uint256(0)));
        _runMacroAs(address(this), signer.addr, params, signatureVRS);
    }

    /// For a given key, nonces must be used in sequence (0, 1, 2, ...). Skipping must revert.
    function testNonceEnforceInSequence(uint192 key) external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");

        // Using seq=1 before seq=0 must revert
        uint256 nonceSeq1 = (uint256(key) << 64) | 1;
        (bytes memory paramsSeq1, bytes memory sig1) = _signPayload(signer, nonceSeq1);

        vm.expectRevert(abi.encodeWithSelector(NonceManager.InvalidNonce.selector, signer.addr, nonceSeq1));
        _runMacroAs(address(this), signer.addr, paramsSeq1, sig1);

        // seq=0 must succeed
        uint256 nonceSeq0 = uint256(key) << 64;
        (bytes memory paramsSeq0, bytes memory sig0) = _signPayload(signer, nonceSeq0);
        assertTrue(_runMacroAs(address(this), signer.addr, paramsSeq0, sig0));

        // now seq=1 must succeed
        assertTrue(_runMacroAs(address(this), signer.addr, paramsSeq1, sig1));
    }

    // example: https://github.com/vaquita-fi/vaquita-lisk/blob/c4964af9157c9cca9cfb167ac1a4450e36edb29e/contracts/test/VaquitaPool.t.sol#L142
    // The splitting up into many functions avoids stack too deep error.
    function getDataToBeSignedJson() internal view returns (string memory) {
        return string(abi.encodePacked(
            '{',
            '"types": {', _getTypesJson(), '},',
            '"primaryType": "MinimalExample",', // leaving this as literal in order to fit onto the stack
            '"domain": {', _getDomainJson(), '},',
            '"message": {',
            '"meta": {', _getMetaJson(), '},',
            '"message": {', _getMessageJson(), '},',
            '"security": {', _getSecurityJson(), '}',
            '}',
            '}'
        ));
    }

    function _getTypesJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            _getEIP712DomainTypeJson(),
            _getMinimalExampleTypeJson(),
            _getMessageTypeJson(),
            _getMetaTypeJson(),
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
            '{"name": "meta", "type": "Meta"},',
            '{"name": "message", "type": "Message"},',
            '{"name": "security", "type": "Security"}',
            '],'
        ));
    }

    function _getMessageTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"Message": [',
            '{"name": "title", "type": "string"}',
            '],'
        ));
    }

    function _getMetaTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"Meta": [',
            '{"name": "domain", "type": "string"},',
            '{"name": "version", "type": "string"}',
            '],'
        ));
    }

    function _getSecurityTypeJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"Security": [',
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

    function _getMetaJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"domain": "', META_DOMAIN, '",',
            '"version": "', META_VERSION, '"'
        ));
    }

    function _getMessageJson() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"title": "', MESSAGE_TITLE, '"'
        ));
    }

    function _getSecurityJson() internal pure returns (string memory) {
        // Use string for nonce so Foundry's JSON parser accepts 2^64 as uint256 (avoids type mismatch)
        return string(abi.encodePacked(
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

    function _signPayload(VmSafe.Wallet memory signer, uint256 nonce)
        internal
        returns (bytes memory params, bytes memory signatureVRS)
    {
        return _signPayloadWithTimeframe(signer, nonce, 0, 0);
    }

    function _signPayloadWithTimeframe(VmSafe.Wallet memory signer, uint256 nonce, uint256 validAfter, uint256 validBefore)
        internal
        returns (bytes memory params, bytes memory signatureVRS)
    {
        params = getPayloadWithNonceAndTimeframe(nonce, validAfter, validBefore);
        bytes32 digest = forwarder.getDigest(minimal712Macro, params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        signatureVRS = abi.encodePacked(r, s, v);
    }
}
