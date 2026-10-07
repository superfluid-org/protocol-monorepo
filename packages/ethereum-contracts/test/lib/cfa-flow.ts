import {Signer} from "ethers";
import {ethers} from "hardhat";

import {ConstantFlowAgreementV1, SuperfluidMock} from "../../typechain-types";

export type DeleteFlowParams = {
    superfluid: SuperfluidMock;
    cfa: ConstantFlowAgreementV1;
    superToken: string;
    sender: string;
    receiver: string;
    by?: string;
    userData?: string;
};

/** Ethers replacement for js-sdk CFA helper deleteFlow (liquidation tests). */
export async function deleteFlow({
    superfluid,
    cfa,
    superToken,
    sender,
    receiver,
    by,
    userData = "0x",
}: DeleteFlowParams) {
    const liquidator = by ?? sender;
    const signer = await ethers.getSigner(liquidator);
    const cfaInterface = cfa.interface;
    const callData = cfaInterface.encodeFunctionData("deleteFlow", [
        superToken,
        sender,
        receiver,
        "0x",
    ]);
    console.log(
        `Delete flow from ${sender} to ${receiver} by ${liquidator} for ${superToken} ...`
    );
    const tx = await superfluid
        .connect(signer as Signer)
        .callAgreement(cfa.address, callData, userData);
    const receipt = await tx.wait();
    console.log("Flow deleted.");
    return {tx: receipt.transactionHash, receipt};
}
