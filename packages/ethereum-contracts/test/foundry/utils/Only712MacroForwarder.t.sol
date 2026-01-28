// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ISuperfluid, BatchOperation } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperfluidToken } from "../../../contracts/interfaces/superfluid/ISuperfluidToken.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { IUserDefinedMacro } from "../../../contracts/interfaces/utils/IUserDefinedMacro.sol";
import { Only712MacroForwarder } from "../../../contracts/utils/Only712MacroForwarder.sol";
import { SuperUpgrader } from "../../../contracts/utils/SuperUpgrader.sol";
import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";

using SuperTokenV1Library for ISuperToken;

// ============== Mock Macro: Create Flow + Allowance to SuperUpgrader ==============

/**
 * @dev Macro that builds: (1) ERC20 approve SuperToken to SuperUpgrader, (2) CFA createFlow.
 * Params: abi.encode(actionCode, lang, actionParams, signatureVRS)
 * actionParams: abi.encode(SetFlowAndAllowanceParams)
 */
contract FlowAndUpgradeMacro is IUserDefinedMacro {
    struct SetFlowAndAllowanceParams {
        ISuperToken superToken;
        address receiver;
        int96 flowRate;
        address superUpgrader;
        uint256 upgradeAllowance;
    }

    uint8 public constant ACTION_SET_FLOW_AND_ALLOWANCE = 1;

    error UnknownActionCode(uint8 actionCode);
    error WrongFlowRate();
    error InsufficientAllowance();

    function buildBatchOperations(ISuperfluid host, bytes memory params, address /*msgSender*/)
        external
        override
        view
        returns (ISuperfluid.Operation[] memory operations)
    {
        (uint8 actionCode, /*bytes32 lang*/, bytes memory actionParams, /*bytes memory signatureVRS*/) =
            abi.decode(params, (uint8, bytes32, bytes, bytes));

        if (actionCode != ACTION_SET_FLOW_AND_ALLOWANCE) revert UnknownActionCode(actionCode);

        SetFlowAndAllowanceParams memory p = abi.decode(actionParams, (SetFlowAndAllowanceParams));

        IConstantFlowAgreementV1 cfa =
            IConstantFlowAgreementV1(address(host.getAgreementClass(
                keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
            )));

        operations = new ISuperfluid.Operation[](2);

        // op 1: approve SuperToken to SuperUpgrader (Host supports SuperToken.operationApprove)
        operations[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC20_APPROVE,
            target: address(p.superToken),
            data: abi.encode(p.superUpgrader, p.upgradeAllowance)
        });

        // op 2: CFA createFlow
        operations[1] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
            target: address(cfa),
            data: abi.encode(
                abi.encodeCall(cfa.createFlow, (p.superToken, p.receiver, p.flowRate, new bytes(0))),
                new bytes(0)
            )
        });
    }

    function postCheck(ISuperfluid /*host*/, bytes memory params, address msgSender) external view override {
        (, /*lang*/, bytes memory actionParams,) = abi.decode(params, (uint8, bytes32, bytes, bytes));
        SetFlowAndAllowanceParams memory p = abi.decode(actionParams, (SetFlowAndAllowanceParams));

        int96 actualFlowRate = p.superToken.getFlowRate(msgSender, p.receiver);
        if (actualFlowRate != p.flowRate) revert WrongFlowRate();

        uint256 allowance = p.superToken.allowance(msgSender, p.superUpgrader);
        if (allowance < p.upgradeAllowance) revert InsufficientAllowance();
    }

    function encodeParams(
        ISuperToken superToken_,
        address receiver_,
        int96 flowRate_,
        address superUpgrader_,
        uint256 upgradeAllowance_
    )
        external
        pure
        returns (bytes memory)
    {
        SetFlowAndAllowanceParams memory p = SetFlowAndAllowanceParams({
            superToken: superToken_,
            receiver: receiver_,
            flowRate: flowRate_,
            superUpgrader: superUpgrader_,
            upgradeAllowance: upgradeAllowance_
        });
        return abi.encode(ACTION_SET_FLOW_AND_ALLOWANCE, bytes32("en"), abi.encode(p), new bytes(0));
    }
}

// ============== Test Contract ==============

contract Only712MacroForwarderTest is FoundrySuperfluidTester {
    Only712MacroForwarder internal only712MacroForwarder;
    SuperUpgrader internal superUpgrader;
    FlowAndUpgradeMacro internal flowAndUpgradeMacro;

    int96 internal constant TEST_FLOW_RATE = 42;
    uint256 internal constant TEST_UPGRADE_ALLOWANCE = 1000e18;

    /// @dev Private key for signer; vm.addr(SIGNER_PRIV_KEY) receives tokens and signs envelope + app message.
    uint256 internal constant SIGNER_PRIV_KEY = 1;

    constructor() FoundrySuperfluidTester(5) {}

    function setUp() public override {
        super.setUp();

        address[] memory backends = new address[](1);
        backends[0] = admin;
        superUpgrader = new SuperUpgrader(admin, backends);

        only712MacroForwarder = new Only712MacroForwarder(sf.host, address(0));

        flowAndUpgradeMacro = new FlowAndUpgradeMacro();

        vm.prank(address(sfDeployer));
        sf.governance.enableTrustedForwarder(
            sf.host,
            ISuperfluidToken(address(0)),
            address(only712MacroForwarder)
        );

        address signer = vm.addr(SIGNER_PRIV_KEY);
        vm.prank(alice);
        superToken.transfer(signer, 1e24);
    }

    /**
     * @dev Happy path for the final implementation: build envelope + envelope sig + app params + app sig,
     *      call runMacro. Expects revert until forwarder decodes/verifies envelope and macro verifies app sig.
     */
    function testFlowAndUpgradeMacroViaOnly712Forwarder_HappyPathExpectRevert() external {
        bytes memory payload = _buildFullPayload();
        vm.startPrank(vm.addr(SIGNER_PRIV_KEY));
        vm.expectRevert();
        only712MacroForwarder.runMacro(IUserDefinedMacro(address(flowAndUpgradeMacro)), payload);
        vm.stopPrank();
    }

    function _buildFullPayload() internal view returns (bytes memory) {
        bytes memory envelopeEncoded = abi.encode(
            "test.xyz",
            "1",
            "en",
            "Read before signing.",
            "Set flow and allowance",
            "Create stream and approve SuperUpgrader for future upgrades",
            "macros.superfluid.eth",
            block.timestamp,
            block.timestamp + 1 hours,
            uint256(1),
            address(flowAndUpgradeMacro)
        );
        bytes32 envelopeDigest = _hashMacroEnvelope(envelopeEncoded, address(only712MacroForwarder));
        (uint8 ev, bytes32 er, bytes32 es) = vm.sign(SIGNER_PRIV_KEY, envelopeDigest);
        bytes memory envelopeSig = abi.encodePacked(er, es, ev);

        bytes32 appDigest = _hashSetFlowAndAllowance(
            "Set your stream to 42 FTTx/month to bob and approve SuperUpgrader for 1000 FTTx",
            address(superToken),
            bob,
            TEST_FLOW_RATE,
            address(superUpgrader),
            TEST_UPGRADE_ALLOWANCE,
            address(flowAndUpgradeMacro)
        );
        (uint8 av, bytes32 ar, bytes32 as_) = vm.sign(SIGNER_PRIV_KEY, appDigest);

        FlowAndUpgradeMacro.SetFlowAndAllowanceParams memory p = FlowAndUpgradeMacro.SetFlowAndAllowanceParams({
            superToken: superToken,
            receiver: bob,
            flowRate: TEST_FLOW_RATE,
            superUpgrader: address(superUpgrader),
            upgradeAllowance: TEST_UPGRADE_ALLOWANCE
        });
        bytes memory appParams = abi.encode(
            flowAndUpgradeMacro.ACTION_SET_FLOW_AND_ALLOWANCE(),
            bytes32("en"),
            abi.encode(p),
            abi.encode(av, ar, as_)
        );
        return abi.encode(envelopeEncoded, envelopeSig, appParams);
    }

    function _hashMacroEnvelope(bytes memory envelopeEncoded, address verifyingContract)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = _macroEnvelopeStructHash(envelopeEncoded);
        return _eip712Digest(_macroEnvelopeDomainSeparator(verifyingContract), structHash);
    }

    function _macroEnvelopeStructHash(bytes memory envelopeEncoded) internal pure returns (bytes32) {
        (
            string memory domain,
            string memory version,
            string memory language,
            string memory disclaimer,
            string memory title,
            string memory description,
            string memory provider,
            uint256 validAfter,
            uint256 validBefore,
            uint256 nonce,
            address macroAddr
        ) = abi.decode(
            envelopeEncoded,
            (string, string, string, string, string, string, string, uint256, uint256, uint256, address)
        );
        bytes32 typeHash = keccak256(
            "MacroEnvelope(string domain,string version,string language,string disclaimer,string title,string description,string provider,uint256 validAfter,uint256 validBefore,uint256 nonce,address macro)"
        );
        return keccak256(
            abi.encode(
                typeHash,
                keccak256(bytes(domain)),
                keccak256(bytes(version)),
                keccak256(bytes(language)),
                keccak256(bytes(disclaimer)),
                keccak256(bytes(title)),
                keccak256(bytes(description)),
                keccak256(bytes(provider)),
                validAfter,
                validBefore,
                nonce,
                macroAddr
            )
        );
    }

    function _macroEnvelopeDomainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Superfluid Macro"),
                keccak256("1"),
                block.chainid,
                verifyingContract
            )
        );
    }

    function _hashSetFlowAndAllowance(
        string memory message,
        address superToken_,
        address receiver_,
        int96 flowRate_,
        address superUpgrader_,
        uint256 upgradeAllowance_,
        address verifyingContract
    )
        internal
        view
        returns (bytes32)
    {
        bytes32 typeHash = keccak256(
            "SetFlowAndAllowance(string message,address superToken,address receiver,int96 flowRate,address superUpgrader,uint256 upgradeAllowance)"
        );
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(bytes(message)),
                superToken_,
                receiver_,
                flowRate_,
                superUpgrader_,
                upgradeAllowance_
            )
        );
        return _eip712Digest(_flowAndUpgradeMacroDomainSeparator(verifyingContract), structHash);
    }

    function _flowAndUpgradeMacroDomainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("FlowAndUpgradeMacro"),
                keccak256("1"),
                block.chainid,
                verifyingContract
            )
        );
    }

    function _eip712Digest(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
