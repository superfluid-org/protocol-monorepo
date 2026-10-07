import {BigNumberish, Signer} from "ethers";
import {ethers} from "hardhat";

import {
    ConstantFlowAgreementV1,
    ConstantFlowAgreementV1__factory,
    InstantDistributionAgreementV1,
    InstantDistributionAgreementV1__factory,
    ISuperfluid__factory,
    ISuperToken__factory,
    SuperfluidMock,
} from "../../typechain-types";

import {createERC20Wrapper} from "./super-token-factory";

type CallAgreementResult = {
    tx: string;
    receipt: ethers.providers.TransactionReceipt;
    blockNumber: number;
};

async function callAgreement(
    host: SuperfluidMock,
    sender: string,
    agreement: string,
    callData: string,
    userData = "0x"
): Promise<CallAgreementResult> {
    const signer = await ethers.getSigner(sender);
    const tx = await host
        .connect(signer as Signer)
        .callAgreement(agreement, callData, userData);
    const receipt = await tx.wait();
    return {
        tx: receipt.transactionHash,
        receipt,
        blockNumber: receipt.blockNumber,
    };
}

function truffleAbi(contractName: string) {
    switch (contractName) {
        case "ISuperToken":
            return ISuperToken__factory.abi;
        case "IConstantFlowAgreementV1":
            return ConstantFlowAgreementV1__factory.abi;
        case "IInstantDistributionAgreementV1":
            return InstantDistributionAgreementV1__factory.abi;
        case "ISuperfluid":
            return ISuperfluid__factory.abi;
        default:
            throw new Error(`Unknown contract ABI: ${contractName}`);
    }
}

function abiWithSignatures(abi: readonly (string | ethers.utils.Fragment)[]) {
    const iface = new ethers.utils.Interface(abi);
    return abi.map((entry) => {
        if (typeof entry !== "object" || entry.type !== "function") {
            return entry;
        }
        try {
            return {
                ...entry,
                signature: iface.getSighash(
                    ethers.utils.FunctionFragment.from(entry)
                ),
            };
        } catch {
            return entry;
        }
    });
}

function makeContractClass(contractName: string) {
    const abi = truffleAbi(contractName);
    return {
        abi,
        at: (address: string) => makeTruffleContract(contractName, address),
    };
}

function makeTruffleContract(contractName: string, address: string) {
    const iface = new ethers.utils.Interface(truffleAbi(contractName));
    const methods: Record<
        string,
        (...args: unknown[]) => {encodeABI: () => string}
    > = {};
    for (const fragment of iface.fragments) {
        if (fragment.type !== "function") continue;
        const fn = fragment as ethers.utils.FunctionFragment;
        methods[fn.name] = (...args: unknown[]) => ({
            encodeABI: () => iface.encodeFunctionData(fn, args),
        });
    }
    const base = {abi: truffleAbi(contractName), address, contract: {methods}};

    if (contractName === "ISuperfluid") {
        return {
            ...base,
            callAgreement: async (
                agreement: string,
                callData: string,
                userData: string,
                opts: {from: string}
            ) => {
                const host = (await ethers.getContractAt(
                    "SuperfluidMock",
                    address
                )) as SuperfluidMock;
                return callAgreement(
                    host,
                    opts.from,
                    agreement,
                    callData,
                    userData
                );
            },
        };
    }
    return base;
}

function cfaAgreementCall(
    host: SuperfluidMock,
    cfa: ConstantFlowAgreementV1,
    sender: string,
    fn: string,
    args: unknown[],
    userData = "0x"
) {
    const callData = cfa.interface.encodeFunctionData(fn, args);
    return callAgreement(host, sender, cfa.address, callData, userData);
}

function idaAgreementCall(
    host: SuperfluidMock,
    ida: InstantDistributionAgreementV1,
    sender: string,
    fn: string,
    args: unknown[],
    userData = "0x"
) {
    const callData = ida.interface.encodeFunctionData(fn, args);
    return callAgreement(host, sender, ida.address, callData, userData);
}

/** Minimal js-sdk Framework replacement for legacy agreement behaviour tests. */
export async function createEthersFramework(
    host: SuperfluidMock,
    cfa: ConstantFlowAgreementV1,
    ida: InstantDistributionAgreementV1
) {
    const cfaContract = {
        abi: abiWithSignatures(ConstantFlowAgreementV1__factory.abi),
    };
    const idaAbi = abiWithSignatures(
        InstantDistributionAgreementV1__factory.abi
    );

    return {
        agreements: {
            cfa: {contract: cfaContract},
            ida: {abi: idaAbi},
        },
        contracts: {
            ISuperToken: makeContractClass("ISuperToken"),
            IConstantFlowAgreementV1: makeContractClass(
                "IConstantFlowAgreementV1"
            ),
            IInstantDistributionAgreementV1: makeContractClass(
                "IInstantDistributionAgreementV1"
            ),
            ISuperfluid: makeContractClass("ISuperfluid"),
            ISuperTokenFactory: makeContractClass("ISuperToken"),
        },
        cfa: {
            createFlow: ({
                superToken,
                sender,
                receiver,
                flowRate,
                userData = "0x",
            }: {
                superToken: string;
                sender: string;
                receiver: string;
                flowRate: BigNumberish;
                userData?: string;
            }) =>
                cfaAgreementCall(
                    host,
                    cfa,
                    sender,
                    "createFlow",
                    [superToken, receiver, flowRate, "0x"],
                    userData
                ),
            updateFlow: ({
                superToken,
                sender,
                receiver,
                flowRate,
                userData = "0x",
            }: {
                superToken: string;
                sender: string;
                receiver: string;
                flowRate: BigNumberish;
                userData?: string;
            }) =>
                cfaAgreementCall(
                    host,
                    cfa,
                    sender,
                    "updateFlow",
                    [superToken, receiver, flowRate, "0x"],
                    userData
                ),
            deleteFlow: ({
                superToken,
                sender,
                receiver,
                by,
                userData = "0x",
            }: {
                superToken: string;
                sender: string;
                receiver: string;
                by?: string;
                userData?: string;
            }) =>
                cfaAgreementCall(
                    host,
                    cfa,
                    by ?? sender,
                    "deleteFlow",
                    [superToken, sender, receiver, "0x"],
                    userData
                ),
        },
        ida: {
            createIndex: ({
                superToken,
                publisher,
                indexId,
                userData = "0x",
            }: {
                superToken: string;
                publisher: string;
                indexId: BigNumberish;
                userData?: string;
            }) =>
                idaAgreementCall(
                    host,
                    ida,
                    publisher,
                    "createIndex",
                    [superToken, indexId, "0x"],
                    userData
                ),
            distribute: ({
                superToken,
                publisher,
                indexId,
                amount,
                userData = "0x",
            }: {
                superToken: string;
                publisher: string;
                indexId: BigNumberish;
                amount: BigNumberish;
                userData?: string;
            }) =>
                idaAgreementCall(
                    host,
                    ida,
                    publisher,
                    "distribute",
                    [superToken, indexId, amount, "0x"],
                    userData
                ),
            updateIndex: ({
                superToken,
                publisher,
                indexId,
                indexValue,
                userData = "0x",
            }: {
                superToken: string;
                publisher: string;
                indexId: BigNumberish;
                indexValue: BigNumberish;
                userData?: string;
            }) =>
                idaAgreementCall(
                    host,
                    ida,
                    publisher,
                    "updateIndex",
                    [superToken, indexId, indexValue, "0x"],
                    userData
                ),
            updateSubscription: ({
                superToken,
                publisher,
                indexId,
                subscriber,
                units,
                userData = "0x",
            }: {
                superToken: string;
                publisher: string;
                indexId: BigNumberish;
                subscriber: string;
                units: BigNumberish;
                userData?: string;
            }) =>
                idaAgreementCall(
                    host,
                    ida,
                    publisher,
                    "updateSubscription",
                    [superToken, indexId, subscriber, units, "0x"],
                    userData
                ),
            approveSubscription: ({
                superToken,
                publisher,
                indexId,
                subscriber,
                userData = "0x",
            }: {
                superToken: string;
                publisher: string;
                indexId: BigNumberish;
                subscriber: string;
                userData?: string;
            }) =>
                idaAgreementCall(
                    host,
                    ida,
                    subscriber,
                    "approveSubscription",
                    [superToken, publisher, indexId, "0x"],
                    userData
                ),
            revokeSubscription: ({
                superToken,
                publisher,
                indexId,
                subscriber,
                userData = "0x",
            }: {
                superToken: string;
                publisher: string;
                indexId: BigNumberish;
                subscriber: string;
                userData?: string;
            }) =>
                idaAgreementCall(
                    host,
                    ida,
                    subscriber,
                    "revokeSubscription",
                    [superToken, publisher, indexId, "0x"],
                    userData
                ),
            deleteSubscription: ({
                superToken,
                publisher,
                indexId,
                subscriber,
                userData = "0x",
            }: {
                superToken: string;
                publisher: string;
                indexId: BigNumberish;
                subscriber: string;
                userData?: string;
            }) =>
                idaAgreementCall(
                    host,
                    ida,
                    publisher,
                    "deleteSubscription",
                    [superToken, publisher, indexId, subscriber, "0x"],
                    userData
                ),
            claim: ({
                superToken,
                publisher,
                indexId,
                subscriber,
                userData = "0x",
            }: {
                superToken: string;
                publisher: string;
                indexId: BigNumberish;
                subscriber: string;
                userData?: string;
            }) =>
                idaAgreementCall(
                    host,
                    ida,
                    subscriber,
                    "claim",
                    [superToken, publisher, indexId, subscriber, "0x"],
                    userData
                ),
        },
        createERC20Wrapper: (
            token: Parameters<typeof createERC20Wrapper>[1],
            opts?: Parameters<typeof createERC20Wrapper>[2]
        ) => createERC20Wrapper(host, token, opts),
    };
}
