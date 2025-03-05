import { JsonFragment } from "@ethersproject/abi";
import { BigNumber, ethers } from "ethers";

import Host from "./Host";
import Operation, { BatchOperationType } from "./Operation";
import { SFError } from "./SFError";
import { getTransactionDescription } from "./utils";

export interface IBatchCallOptions {
    hostAddress: string;
    operations: ReadonlyArray<Operation>;
}

export interface OperationStruct {
    readonly operationType: number;
    readonly target: string;
    readonly data: string;
    readonly value?: ethers.BigNumber;
}

export const batchOperationTypeStringToTypeMap = new Map<
    BatchOperationType,
    number
>([
    ["ERC20_APPROVE", 1],
    ["ERC20_TRANSFER_FROM", 2],
    ["ERC777_SEND", 3],
    ["ERC20_INCREASE_ALLOWANCE", 4],
    ["ERC20_DECREASE_ALLOWANCE", 5],
    ["SUPERTOKEN_UPGRADE", 101],
    ["SUPERTOKEN_DOWNGRADE", 102],
    ["SUPERFLUID_CALL_AGREEMENT", 201],
    ["CALL_APP_ACTION", 202],
    ["SIMPLE_FORWARD_CALL", 301],
    ["ERC2771_FORWARD_CALL", 302],
]);

/**
 * Gets function arguments given an ABI and callData.
 * @param abi the abi fragments of a contract/function
 * @param callData call data of the function
 * @returns {ethers.utils.Result} call agreement function arguments
 */
export const getCallDataFunctionArgs = (
    abi: string | readonly (string | ethers.utils.Fragment | JsonFragment)[],
    callData: string
): ethers.utils.Result => getTransactionDescription(abi, callData).args;

/**
 * BatchCall Helper Class
 * @description A helper class to create `BatchCall` objects which can be executed.
 */
export default class BatchCall {
    options: IBatchCallOptions;
    host: Host;

    constructor(options: IBatchCallOptions) {
        this.options = options;
        this.host = new Host(options.hostAddress);
    }

    getCallDataFunctionArgs = getCallDataFunctionArgs;

    /**
     * Given an `Operation` object, gets the `OperationStruct` object.
     * @param operation an `Operation` object
     * @param index the index of the `Operation` in the batchCall
     * @returns {Promise<OperationStruct>} OperationStruct object for batchCall
     */
    getOperationStruct = async (
        operation: Operation,
        index: number
    ): Promise<OperationStruct> => operation.toOperationStruct(index);

    /**
     * Gets an array of `OperationStruct` objects to be passed to batchCall.
     * @returns {Promise<OperationStruct>[]} array of operation struct promises
     */
    get getOperationStructArrayPromises(): Promise<OperationStruct>[] {
        return this.options.operations.map((x, i) =>
            this.getOperationStruct(x, i)
        );
    }

    async toOperation() {
        if (this.getOperationStructArrayPromises.length === 0) {
            throw new SFError({
                type: "BATCH_CALL_ERROR",
                message: "There are no operations to execute in the batch.",
            });
        }
        const operationStructArray = await Promise.all(
            this.getOperationStructArrayPromises
        );

        const values = operationStructArray
            .filter((x) => x.value?.gt(BigNumber.from(0)))
            .map((x) => x.value);

        if (values.length > 1) {
            throw new SFError({
                type: "BATCH_CALL_ERROR",
                message:
                    "There are multiple values in the batch call. The value can only be forwarded to one receiving operation.",
            });
        }

        const tx = this.host.contract.populateTransaction.batchCall(
            operationStructArray,
            {
                value: values?.length > 0 ? values[0] : undefined,
            }
        );
        return new Operation(tx, "UNSUPPORTED");
    }

    /**
     * Executes a batch call given the operations on this class.
     * @param signer the signer of the transaction
     * @param gasLimitMultiplier A multiplier to provide gasLimit buffer on top of the estimated gas limit (1.2x is the default)
     * @returns {Promise<ethers.ContractTransaction>} ContractTransaction object
     */
    exec = async (
        signer: ethers.Signer,
        gasLimitMultiplier = 1.2
    ): Promise<ethers.ContractTransaction> => {
        const operation = await this.toOperation();
        return await operation.exec(signer, gasLimitMultiplier);
    };

    /* istanbul ignore next */
    // TODO: user signs the transaction they'd like to execute and gives
    // this data to the trusted forwarder to sign
    /**
     * Executes a forward batch call given the operations on this class.
     * @param signer the signer of the transaction
     * @returns {Promise<ethers.ContractTransaction>} ContractTransaction object
     */
    execForward = async (
        signer: ethers.Signer
    ): Promise<ethers.ContractTransaction> => {
        if (this.getOperationStructArrayPromises.length === 0) {
            throw new SFError({
                type: "BATCH_CALL_ERROR",
                message: "There are no operations to execute in the batch.",
            });
        }
        const operationStructArray = await Promise.all(
            this.getOperationStructArrayPromises
        );
        return await this.host.contract
            .connect(signer)
            .forwardBatchCall(operationStructArray);
    };
}
