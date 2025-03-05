import { ethers } from "ethers";

import {
    batchOperationTypeStringToTypeMap,
    getCallDataFunctionArgs,
    OperationStruct,
} from "./BatchCall";
import { SFError } from "./SFError";
import multiplyGasLimit from "./multiplyGasLimit";
import { Superfluid__factory } from "./typechain-types";
import { removeSigHashFromCallData } from "./utils";

export type BatchOperationType =
    | "UNSUPPORTED" // 0
    | "ERC20_APPROVE" // 1
    | "ERC20_TRANSFER_FROM" // 2
    | "ERC777_SEND" // 3
    | "ERC20_INCREASE_ALLOWANCE" // 4
    | "ERC20_DECREASE_ALLOWANCE" // 5
    | "SUPERTOKEN_UPGRADE" // 101
    | "SUPERTOKEN_DOWNGRADE" // 102
    | "SUPERFLUID_CALL_AGREEMENT" // 201
    | "CALL_APP_ACTION" // 202
    | "SIMPLE_FORWARD_CALL" // 301
    | "ERC2771_FORWARD_CALL"; // 302

/**
 * Operation Helper Class
 * @description A helper class to create `Operation` objects which can be executed or batched.
 */
export default class Operation {
    readonly populateTransactionPromise: Promise<ethers.PopulatedTransaction>;
    readonly type: BatchOperationType;

    // @note This property is used to ensure BatchCall operations still function
    // when using the agreement forwarder
    readonly forwarderPopulatedPromise?: Promise<ethers.PopulatedTransaction>;

    constructor(
        txn: Promise<ethers.PopulatedTransaction>,
        type: BatchOperationType,
        forwarderPopulatedPromise?: Promise<ethers.PopulatedTransaction>
    ) {
        this.populateTransactionPromise = txn;
        this.type = type;
        this.forwarderPopulatedPromise = forwarderPopulatedPromise;
    }

    /**
     * Executes the operation via the provided signer.
     * @description Populates all fields of the transaction, signs it and sends it to the network.
     * @param signer The signer of the transaction
     * @param gasLimitMultiplier A multiplier to provide gasLimit buffer on top of the estimated gas limit (1.2x is the default)
     * @returns {ethers.providers.TransactionResponse} A TransactionResponse object which can be awaited
     */
    exec = async (
        signer: ethers.Signer,
        gasLimitMultiplier = 1.2
    ): Promise<ethers.providers.TransactionResponse> => {
        const populatedTransaction = await this.getPopulatedTransactionRequest(
            signer,
            gasLimitMultiplier
        );
        return await signer.sendTransaction(populatedTransaction);
    };

    /**
     * Get the populated transaction by awaiting `populateTransactionPromise`.
     * `providerOrSigner` is used for gas estimation if necessary.
     * NOTE: we use the forwarder populated promise if this exists
     */
    getPopulatedTransactionRequest = async (
        providerOrSigner: ethers.providers.Provider | ethers.Signer,
        gasLimitMultiplier = 1.2
    ): Promise<ethers.PopulatedTransaction> => {
        const populatedTransaction = this.forwarderPopulatedPromise
            ? await this.forwarderPopulatedPromise
            : await this.populateTransactionPromise;

        // if gasLimit exists, an Overrides object has been passed or the user has explicitly set
        // a gasLimit for their transaction prior to execution and so we keep it as is else we apply
        // a specified or the default (1.2) multiplier on the gas limit.
        if (!populatedTransaction.gasLimit) {
            const estimatedGasLimit =
                await providerOrSigner.estimateGas(populatedTransaction);
            populatedTransaction.gasLimit = multiplyGasLimit(
                estimatedGasLimit,
                gasLimitMultiplier
            );
        }

        return populatedTransaction;
    };
    /**
     * Signs the populated transaction via the provided signer (what you intend on sending to the network).
     * @param signer The signer of the transaction
     * @returns {Promise<string>} Fully serialized, signed transaction
     */
    getSignedTransaction = async (
        signer: ethers.Signer,
        gasLimitMultiplier = 1.2
    ): Promise<string> => {
        const populatedTransaction = await this.getPopulatedTransactionRequest(
            signer,
            gasLimitMultiplier
        );
        const signerPopulatedTransaction =
            await signer.populateTransaction(populatedTransaction);
        const signedTransaction = await signer.signTransaction(
            signerPopulatedTransaction
        );
        return signedTransaction;
    };

    /**
     * Gets the transaction hash of the transaction.
     * @description Calculates this by getting the keccak256 hash of the signedTxn.
     * @param signer The signer of the transaction
     * @returns {Promise<string>} The transaction hash of the transaction
     */
    getTransactionHash = async (signer: ethers.Signer): Promise<string> => {
        const signedTxn = await this.getSignedTransaction(signer);
        return ethers.utils.keccak256(signedTxn);
    };

    /**
     * Gets the `OperationStruct` object.
     * @param operation an `Operation` object
     * @param index the index of the `Operation` in the batchCall
     * @returns {Promise<OperationStruct>} OperationStruct object for batchCall
     */
    toOperationStruct = async (index: number): Promise<OperationStruct> => {
        const batchOperationType = batchOperationTypeStringToTypeMap.get(
            this.type
        );
        const populatedTransaction = await this.populateTransactionPromise;
        if (!batchOperationType) {
            throw new SFError({
                type: "UNSUPPORTED_OPERATION",
                message: "The operation at index " + index + " is unsupported.",
            });
        }

        /* istanbul ignore next */
        if (!populatedTransaction.to || !populatedTransaction.data) {
            throw new SFError({
                type: "MISSING_TRANSACTION_PROPERTIES",
                message: "The transaction is missing the to or data property.",
            });
        }

        const encoder = ethers.utils.defaultAbiCoder;

        // Handles Superfluid.callAgreement
        if (this.type === "SUPERFLUID_CALL_AGREEMENT") {
            const functionArgs = getCallDataFunctionArgs(
                Superfluid__factory.abi,
                populatedTransaction.data
            );
            const data = encoder.encode(
                ["bytes", "bytes"],
                [functionArgs["callData"], functionArgs["userData"]]
            );

            return {
                operationType: batchOperationType,
                target: functionArgs["agreementClass"],
                data,
                value: populatedTransaction.value,
            };
        }

        // Handles Superfluid.callAppAction
        if (this.type === "CALL_APP_ACTION") {
            const functionArgs = getCallDataFunctionArgs(
                Superfluid__factory.abi,
                populatedTransaction.data
            );

            return {
                operationType: batchOperationType,
                target: functionArgs["app"],
                data: functionArgs["callData"],
                value: populatedTransaction.value,
            };
        }

        if (
            this.type === "SIMPLE_FORWARD_CALL" ||
            this.type === "ERC2771_FORWARD_CALL"
        ) {
            return {
                operationType: batchOperationType,
                target: populatedTransaction.to,
                data: populatedTransaction.data,
                value: populatedTransaction.value,
            };
        }

        // Handles remaining ERC20/ERC777/SuperToken Operations (including SIMPLE_FORWARD_CALL and ERC2771_FORWARD_CALL)
        return {
            operationType: batchOperationType,
            target: populatedTransaction.to,
            data: removeSigHashFromCallData(populatedTransaction.data),
            value: populatedTransaction.value,
        };
    };
}
