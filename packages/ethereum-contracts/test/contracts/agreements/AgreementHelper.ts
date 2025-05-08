import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {FunctionFragment, Interface} from "ethers/lib/utils";
import {ethers} from "hardhat";

import IConstantFlowAgreementV1Artifact from "../../../build/hardhat/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol/IConstantFlowAgreementV1.json";
import IInstantDistributionAgreementV1Artifact from "../../../build/hardhat/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol/IInstantDistributionAgreementV1.json";
import SuperfluidMockArtifact from "../../../build/hardhat/contracts/mocks/SuperfluidMock.t.sol/SuperfluidMock.json";
import TestEnvironment from "../../TestEnvironment";

import {
    CallAgreementParams,
    CallAppActionParams,
    ModifyFlowCallDataParams,
    UpdateFlowOperatorPermissionsParams,
} from "./Agreement.types";

export const FLOW_TYPE_CREATE = "createFlow";
export const FLOW_TYPE_UPDATE = "updateFlow";
export const FLOW_TYPE_DELETE = "deleteFlow";

export default class AgreementHelper {
    readonly testEnvironment: TestEnvironment;
    readonly cfaInterface: Interface;
    readonly hostInterface: Interface;
    readonly idaInterface: Interface;

    constructor(testEnvironment: TestEnvironment) {
        this.testEnvironment = testEnvironment;
        this.cfaInterface = new ethers.utils.Interface(
            IConstantFlowAgreementV1Artifact.abi
        );
        this.hostInterface = new ethers.utils.Interface(
            SuperfluidMockArtifact.abi
        );
        this.idaInterface = new ethers.utils.Interface(
            IInstantDistributionAgreementV1Artifact.abi
        );
    }

    async callAgreement(params: CallAgreementParams) {
        return await this.testEnvironment.contracts.superfluid
            .connect(params.signer)
            .callAgreement(
                params.agreementAddress,
                params.callData,
                params.userData || "0x"
            );
    }

    async callAppAction(params: CallAppActionParams) {
        return await this.testEnvironment.contracts.superfluid
            .connect(params.signer)
            .callAppAction(params.appAddress, params.callData);
    }

    getUpdateFlowOperatorPermissionsCallData(
        params: UpdateFlowOperatorPermissionsParams
    ) {
        return this.cfaInterface.encodeFunctionData(
            "updateFlowOperatorPermissions",
            [
                params.superToken,
                params.flowOperator,
                params.permissions,
                params.flowRateAllowance,
            ]
        );
    }

    getAuthorizeFlowOperatorWithFullControlCallData(params: {
        superToken: string;
        flowOperator: string;
    }) {
        return this.cfaInterface.encodeFunctionData(
            "updateFlowOperatorPermissions",
            [params.superToken, params.flowOperator]
        );
    }

    getIDACallData(fragment: string | FunctionFragment, args: readonly any[]) {
        return this.idaInterface.encodeFunctionData(fragment, args);
    }
    getModifyFlowCallData(params: ModifyFlowCallDataParams) {
        const normalizedToken = ethers.utils.getAddress(params.superToken);
        const normalizedReceiver = ethers.utils.getAddress(params.receiver);
        const normalizedSender =
            params.type === "deleteFlow"
                ? ethers.utils.getAddress(params.sender || "")
                : "";
        const values =
            params.type === "deleteFlow"
                ? [normalizedToken, normalizedSender, normalizedReceiver, "0x"]
                : [normalizedToken, normalizedReceiver, params.flowRate, "0x"];
        return this.cfaInterface.encodeFunctionData(params.type, values);
    }

    getModifyFlowByOperatorCallData(params: ModifyFlowCallDataParams) {
        const normalizedToken = ethers.utils.getAddress(params.superToken);
        const normalizedReceiver = ethers.utils.getAddress(params.receiver);
        const normalizedSender = ethers.utils.getAddress(params.sender);
        const values =
            params.type === "deleteFlowByOperator"
                ? [normalizedToken, normalizedSender, normalizedReceiver, "0x"]
                : [
                      normalizedToken,
                      normalizedSender,
                      normalizedReceiver,
                      params.flowRate,
                      "0x",
                  ];
        return this.cfaInterface.encodeFunctionData(params.type, values);
    }

    async modifyFlow(
        params: ModifyFlowCallDataParams & {
            signer?: SignerWithAddress;
            userData?: string;
        }
    ) {
        const signer = params.signer
            ? params.signer
            : await ethers.getSigner(params.sender || "");
        const callData = this.getModifyFlowCallData(params);
        return this.callAgreement({
            agreementAddress: this.testEnvironment.contracts.cfa.address,
            callData,
            userData: params.userData,
            signer,
        });
    }
}
