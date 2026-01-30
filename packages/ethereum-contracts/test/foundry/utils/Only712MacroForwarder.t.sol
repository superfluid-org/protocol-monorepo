// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { ISuperfluid, ISuperfluidToken } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IUserDefined712Macro } from "../../../contracts/interfaces/utils/IUserDefinedMacro.sol";
import { Only712MacroForwarder } from "../../../contracts/utils/Only712MacroForwarder.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";

string constant MESSAGE_TITLE = "Hello 712";
string constant PRIMARY_TYPE_NAME = "MinimalExample";
string constant META_DOMAIN = "minimalmacro.xyz";
string constant META_VERSION = "1";
string constant SECURITY_PROVIDER = "macros.superfluid.eth";

// returns the encoded payload for the example macro
function getTestPayload() pure returns (bytes memory) {
    Only712MacroForwarder.Payload memory payload = Only712MacroForwarder.Payload({
        meta: Only712MacroForwarder.PayloadMeta({ domain: META_DOMAIN, version: META_VERSION }),
        message: Only712MacroForwarder.PayloadMessage({ title: MESSAGE_TITLE, customPayload: new bytes(0) }),
        security: Only712MacroForwarder.PayloadSecurity({ provider: SECURITY_PROVIDER, nonce: 1 })
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

        vm.prank(address(sfDeployer));
        sf.governance.enableTrustedForwarder(sf.host, ISuperfluidToken(address(0)), address(forwarder));
    }

    /**
     * @dev Smoke test: build payload, get digest via getDigest(), sign with vm.createWallet + vm.sign,
     *      call runMacro(m, params, signer, signature), assert success.
     */
    function testRunMacro() external {
        VmSafe.Wallet memory signer = vm.createWallet("signer");
        bytes memory params = getTestPayload();
        bytes32 digest = forwarder.getDigest(IUserDefined712Macro(address(minimal712Macro)), params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        bytes memory signatureVRS = abi.encodePacked(r, s, v);

        vm.prank(signer.addr);
        bool ok = forwarder.runMacro(IUserDefined712Macro(address(minimal712Macro)), params, signer.addr, signatureVRS);
        assertTrue(ok);
    }

    function testDigestCalculation() external view {
        // check the type definition
        string memory typeDefinition = forwarder.getTypeDefinition(minimal712Macro);
        string memory expectedTypeDefinition = "MinimalExample(Meta meta,Message message,Security security)Message(string title)Meta(string domain,string version)Security(string provider,uint256 nonce)";
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
        return string(abi.encodePacked(
            '"provider": "', SECURITY_PROVIDER, '",',
            '"nonce": ', '1'
        ));
    }
}
