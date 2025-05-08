import { BytesLike, ethers, Overrides } from "ethers";

import ConstantFlowAgreementV1 from "./ConstantFlowAgreementV1";
import ERC20Token from "./ERC20Token";
import GeneralDistributionAgreementV1 from "./GeneralDistributionAgreementV1";
import Governance from "./Governance";
import InstantDistributionAgreementV1 from "./InstantDistributionAgreementV1";
import Operation from "./Operation";
import { SFError } from "./SFError";
import { chainIdToResolverDataMap, networkNameToChainIdMap } from "./constants";
import { getNetworkName } from "./frameworkHelpers";
import {
    ConnectPoolParams,
    DisconnectPoolParams,
    ERC20DecreaseAllowanceParams,
    ERC20IncreaseAllowanceParams,
    ERC777SendParams,
    FlowDistributionActualFlowRateData,
    GetPoolAdjustmentFlowInfoParams,
    IConfig,
    IRealtimeBalanceOfParams,
    IsMemberConnectedParams,
    ISuperTokenBaseIDAParams,
    ISuperTokenCreateFlowByOperatorParams,
    ISuperTokenCreateFlowParams,
    ISuperTokenDeleteFlowParams,
    ISuperTokenDistributeParams,
    ISuperTokenFlowOperatorDataByIDParams,
    ISuperTokenFlowOperatorDataParams,
    ISuperTokenFullControlParams,
    ISuperTokenGetFlowInfoParams,
    ISuperTokenGetFlowParams,
    ISuperTokenGetIndexParams,
    ISuperTokenGetSubscriptionParams,
    ISuperTokenPublisherOperationParams,
    ISuperTokenPubSubParams,
    ISuperTokenUpdateFlowByOperatorParams,
    ISuperTokenUpdateFlowOperatorPermissionsParams,
    ISuperTokenUpdateFlowParams,
    ISuperTokenUpdateIndexValueParams,
    ISuperTokenUpdateSubscriptionUnitsParams,
    IWeb3FlowInfo,
    IWeb3FlowOperatorData,
    IWeb3GovernanceParams,
    IWeb3Index,
    IWeb3RealTimeBalanceOf,
    IWeb3Subscription,
    SuperTokenCreatePoolParams,
    SuperTokenDistributeFlowParams,
    SuperTokenDistributeParams,
    SuperTokenEstimateDistributionActualAmountParams,
    SuperTokenEstimateDistributionActualFlowRateParams,
    SuperTokenFlowRateAllowanceParams,
    SuperTokenFlowRateAllowanceWithPermissionsParams,
    SuperTokenGDAGetFlowRateParams,
    SuperTokenGDAGetNetFlowParams,
    SuperTokenGetPoolAdjustmentFlowRateParams,
    SuperTokenIsPoolParams,
} from "./interfaces";
import {
    ISETH,
    ISETH__factory,
    ISuperToken,
    ISuperToken__factory,
} from "./typechain-types";
import {
    getSanitizedTimestamp,
    getStringCurrentTimeInSeconds,
    normalizeAddress,
    tryGet,
} from "./utils";

export interface ITokenSettings {
    readonly address: string;
    readonly config: IConfig;
    readonly chainId: number;
    readonly networkName: string;
}

export interface ITokenOptions {
    readonly address: string;
    readonly config: IConfig;
    readonly provider: ethers.providers.Provider;
    readonly chainId?: number;
    readonly networkName?: string;
}

/**
 * SuperToken Helper Class
 * @description A helper class to create `SuperToken` objects which can interact with the `SuperToken` contract as well as the CFAV1 and IDAV1 contracts of the desired `SuperToken`.
 * @see https://www.notion.so/superfluidhq/Classification-of-Super-Tokens-5beace780b5c4d09a5752a3677da3dc0 for further details on naming classification and underlying implementation.
 */
export default abstract class SuperToken extends ERC20Token {
    readonly options: ITokenOptions;
    readonly settings: ITokenSettings;
    readonly cfaV1: ConstantFlowAgreementV1;
    readonly idaV1: InstantDistributionAgreementV1;
    readonly gdaV1: GeneralDistributionAgreementV1;
    readonly governance: Governance;
    readonly underlyingToken?: ERC20Token;
    override readonly contract: ISuperToken;

    protected constructor(options: ITokenOptions, settings: ITokenSettings) {
        // initialize ERC20 token functions here
        super(settings.address);

        this.options = options;
        this.settings = settings;
        this.cfaV1 = new ConstantFlowAgreementV1(
            settings.config.hostAddress,
            settings.config.cfaV1Address,
            settings.config.cfaV1ForwarderAddress
        );
        this.idaV1 = new InstantDistributionAgreementV1(
            settings.config.hostAddress,
            settings.config.idaV1Address
        );
        this.gdaV1 = new GeneralDistributionAgreementV1(
            settings.config.hostAddress,
            settings.config.gdaV1Address,
            settings.config.gdaV1ForwarderAddress
        );
        this.governance = new Governance(
            settings.config.hostAddress,
            settings.config.governanceAddress
        );

        this.contract = new ethers.Contract(
            settings.address,
            ISuperToken__factory.abi
        ) as ISuperToken;
    }

    static create = async (options: ITokenOptions): Promise<SuperToken> => {
        if (!options.chainId && !options.networkName) {
            throw new SFError({
                type: "SUPERTOKEN_INITIALIZATION",
                message: "You must input chainId or networkName.",
            });
        }
        const networkName = getNetworkName(options);
        const chainId =
            options.chainId || networkNameToChainIdMap.get(networkName)!;
        try {
            const superToken = ISuperToken__factory.connect(
                options.address,
                options.provider
            );
            const getUnderlyingTokenPromise = superToken
                .connect(options.provider)
                .getUnderlyingToken();
            const underlyingTokenAddress = await tryGet(
                getUnderlyingTokenPromise,
                ethers.constants.AddressZero
            );
            const settings: ITokenSettings = {
                address: options.address,
                config: options.config,
                chainId,
                networkName,
            };

            const tokenSymbol = await superToken
                .connect(options.provider)
                .symbol();
            const resolverData = chainIdToResolverDataMap.get(chainId) || {
                subgraphAPIEndpoint: "",
                resolverAddress: "",
                networkName: "",
                nativeTokenSymbol: "",
            };
            const nativeTokenSymbol = resolverData.nativeTokenSymbol || "ETH";
            const nativeSuperTokenSymbol = nativeTokenSymbol + "x";

            if (nativeSuperTokenSymbol === tokenSymbol) {
                return new NativeAssetSuperToken(
                    options,
                    settings,
                    nativeTokenSymbol
                );
            }

            if (underlyingTokenAddress !== ethers.constants.AddressZero) {
                return new WrapperSuperToken(options, {
                    ...settings,
                    underlyingTokenAddress,
                });
            }
            return new PureSuperToken(options, settings);
        } catch (err) {
            throw new SFError({
                type: "SUPERTOKEN_INITIALIZATION",
                message: "There was an error initializing the SuperToken",
                cause: err,
            });
        }
    };

    /** ### ERC777 Token Write Functions ### */
    /**
     * Send `amount` tokens to `recipient` from transaction signer.
     * @param recipient the recipient of the tokens
     * @param amount the amount of tokens to send
     * @param userData Extra user data provided.
     */
    send = (params: ERC777SendParams): Operation => {
        const recipient = normalizeAddress(params.recipient);
        const txn = this.contract.populateTransaction.send(
            recipient,
            params.amount,
            params.userData || "0x",
            params.overrides || {}
        );
        return new Operation(txn, "ERC777_SEND");
    };

    /** ### SuperToken Contract Read Functions ### */

    /**
     * Returns the real time balance of `address`.
     * @param account the target address
     * @param timestamp the timestamp you'd like to see the data
     * @param providerOrSigner a provider or signer for executing a web3 call
     * @returns {Promise<IWeb3RealTimeBalanceOf>} real time balance of data
     */
    realtimeBalanceOf = async ({
        providerOrSigner,
        account,
        timestamp = getStringCurrentTimeInSeconds(),
    }: IRealtimeBalanceOfParams): Promise<IWeb3RealTimeBalanceOf> => {
        const normalizedAccount = normalizeAddress(account);
        try {
            const realtimeBalanceOf = await this.contract
                .connect(providerOrSigner)
                .realtimeBalanceOf(normalizedAccount, timestamp);
            return {
                availableBalance: realtimeBalanceOf.availableBalance.toString(),
                deposit: realtimeBalanceOf.deposit.toString(),
                owedDeposit: realtimeBalanceOf.owedDeposit.toString(),
                timestamp: getSanitizedTimestamp(timestamp),
            };
        } catch (err) {
            throw new SFError({
                type: "SUPERTOKEN_READ",
                message: "There was an error getting realtimeBalanceOf",
                cause: err,
            });
        }
    };

    /** ### CFA Read Functions ### */

    /**
     * Get the details of a flow.
     * @param sender the sender of the flow
     * @param receiver the receiver of the flow
     * @param providerOrSigner a provider or signer object
     * @returns {Promise<IWeb3FlowInfo>} Web3 Flow info object
     */
    getFlow = async (
        params: ISuperTokenGetFlowParams
    ): Promise<IWeb3FlowInfo> => {
        return await this.cfaV1.getFlow({
            superToken: this.settings.address,
            sender: params.sender,
            receiver: params.receiver,
            providerOrSigner: params.providerOrSigner,
        });
    };

    /**
     * Get the flow info of an account (net flow).
     * @param account the account we're querying
     * @param providerOrSigner a provider or signer object
     * @returns {Promise<IWeb3FlowInfo>} Web3 Flow info object
     */
    getAccountFlowInfo = async (
        params: ISuperTokenGetFlowInfoParams
    ): Promise<IWeb3FlowInfo> => {
        return await this.cfaV1.getAccountFlowInfo({
            superToken: this.settings.address,
            account: params.account,
            providerOrSigner: params.providerOrSigner,
        });
    };

    /**
     * Get the net flow of an account.
     * @param account the account we're querying
     * @param providerOrSigner a provider or signer object
     * @returns {Promise<string>} Web3 Flow info object
     */
    getNetFlow = async (
        params: ISuperTokenGetFlowInfoParams
    ): Promise<string> => {
        return await this.cfaV1.getNetFlow({
            superToken: this.settings.address,
            account: params.account,
            providerOrSigner: params.providerOrSigner,
        });
    };

    /**
     * Get flow operator data.
     * @param sender the sender
     * @param flowOperator the flowOperator
     * @param providerOrSigner a provider or signer object
     * @returns {Promise<IWeb3FlowOperatorData>} Web3 Flow info object
     */
    getFlowOperatorData = async (
        params: ISuperTokenFlowOperatorDataParams
    ): Promise<IWeb3FlowOperatorData> => {
        const normalizedSender = normalizeAddress(params.sender);
        const normalizedFlowOperator = normalizeAddress(params.flowOperator);
        return await this.cfaV1.getFlowOperatorData({
            superToken: this.settings.address,
            sender: normalizedSender,
            flowOperator: normalizedFlowOperator,
            providerOrSigner: params.providerOrSigner,
        });
    };

    /**
     * Get flow operator data using the flowOperatorId.
     * @param flowOperatorId The keccak256 hash of encoded string "flowOperator", sender and flowOperator
     * @param providerOrSigner a provider or signer object
     * @returns {Promise<IWeb3FlowOperatorData>} Web3 Flow info object
     */
    getFlowOperatorDataByID = async (
        params: ISuperTokenFlowOperatorDataByIDParams
    ): Promise<IWeb3FlowOperatorData> => {
        return await this.cfaV1.getFlowOperatorDataByID({
            superToken: this.settings.address,
            flowOperatorId: params.flowOperatorId,
            providerOrSigner: params.providerOrSigner,
        });
    };

    /** ### ERC20 Write Functions ### */

    /**
     * Increases the allowance of `spender` by `amount`.
     * @param spender the spender
     * @param amount the amount to increase the allowance by
     * @returns {Operation}  An instance of Operation which can be executed or batched.
     */
    increaseAllowance = (params: ERC20IncreaseAllowanceParams): Operation => {
        const spender = normalizeAddress(params.spender);
        const txn = this.contract.populateTransaction.increaseAllowance(
            spender,
            params.amount,
            params.overrides || {}
        );
        return new Operation(txn, "ERC20_INCREASE_ALLOWANCE");
    };

    /**
     * Decreases the allowance of `spender` by `amount`.
     * @param spender the spender
     * @param amount the amount to decrease the allowance by
     * @returns {Operation}  An instance of Operation which can be executed or batched.
     */
    decreaseAllowance = (params: ERC20DecreaseAllowanceParams): Operation => {
        const spender = normalizeAddress(params.spender);
        const txn = this.contract.populateTransaction.decreaseAllowance(
            spender,
            params.amount,
            params.overrides || {}
        );
        return new Operation(txn, "ERC20_DECREASE_ALLOWANCE");
    };

    /** ### CFA Write Functions ### */

    /**
     * Create a flow of the token of this class.
     * @param receiver The receiver of the flow.
     * @param flowRate The specified flow rate.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    createFlow = (params: ISuperTokenCreateFlowParams): Operation => {
        return this.cfaV1.createFlow({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Update a flow of the token of this class.
     * @param receiver The receiver of the flow.
     * @param flowRate The specified flow rate.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    updateFlow = (params: ISuperTokenUpdateFlowParams): Operation => {
        return this.cfaV1.updateFlow({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Delete a flow of the token of this class.
     * @param sender The sender of the flow.
     * @param receiver The receiver of the flow.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    deleteFlow = (params: ISuperTokenDeleteFlowParams): Operation => {
        return this.cfaV1.deleteFlow({
            superToken: this.settings.address,
            ...params,
        });
    };

    /** ### CFA ACL Write Functions (byOperator) ### */

    /**
     * Increase the flow rate allowance for an ACL operator.
     * @param flowOperator The operator of the flow.
     * @param flowRateAllowanceDelta The amount to increase the flow rate allowance by.
     * @param userData Extra user data provided.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    increaseFlowRateAllowance(
        params: SuperTokenFlowRateAllowanceParams
    ): Operation {
        return this.cfaV1.increaseFlowRateAllowance({
            superToken: this.settings.address,
            ...params,
        });
    }

    /**
     * Decrease the flow rate allowance for an ACL operator.
     * @param flowOperator The operator of the flow.
     * @param flowRateAllowanceDelta The amount to decrease the flow rate allowance by.
     * @param userData Extra user data provided.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    decreaseFlowRateAllowance(params: SuperTokenFlowRateAllowanceParams) {
        return this.cfaV1.decreaseFlowRateAllowance({
            superToken: this.settings.address,
            ...params,
        });
    }

    /**
     * Increase the flow rate allowance and sets permissions for an ACL operator.
     * @param flowOperator The permission grantee address
     * @param permission The permissions to set.
     * @param flowRateAllowance The amount to increase the flow rate allowance by.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     *
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    increaseFlowRateAllowanceWithPermissions(
        params: SuperTokenFlowRateAllowanceWithPermissionsParams
    ): Operation {
        return this.cfaV1.increaseFlowRateAllowanceWithPermissions({
            superToken: this.settings.address,
            ...params,
        });
    }

    /**
     * Decrease the flow rate allowance and sets permissions for an ACL operator.
     * @param flowOperator The permission grantee address
     * @param permission The permissions to set.
     * @param flowRateAllowance The amount to decrease the flow rate allowance by.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     *
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    decreaseFlowRateAllowanceWithPermissions(
        params: SuperTokenFlowRateAllowanceWithPermissionsParams
    ): Operation {
        return this.cfaV1.decreaseFlowRateAllowanceWithPermissions({
            superToken: this.settings.address,
            ...params,
        });
    }

    /**
     * Update permissions for a flow operator as a sender.
     * @param flowOperator The permission grantee address
     * @param permission The permissions to set.
     * @param flowRateAllowance The flowRateAllowance granted to the flow operator.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    updateFlowOperatorPermissions(
        params: ISuperTokenUpdateFlowOperatorPermissionsParams
    ): Operation {
        return this.cfaV1.updateFlowOperatorPermissions({
            superToken: this.settings.address,
            ...params,
        });
    }

    /**
     * Give flow operator full control - max flow rate and create/update/delete permissions.
     * @param flowOperator The permission grantee address
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     */
    authorizeFlowOperatorWithFullControl(
        params: ISuperTokenFullControlParams
    ): Operation {
        return this.cfaV1.authorizeFlowOperatorWithFullControl({
            superToken: this.settings.address,
            ...params,
        });
    }

    /**
     * Revoke flow operator control - set flow rate to 0 with no permissions.
     * @param flowOperator The permission grantee address
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     */
    revokeFlowOperatorWithFullControl(
        params: ISuperTokenFullControlParams
    ): Operation {
        return this.cfaV1.revokeFlowOperatorWithFullControl({
            superToken: this.settings.address,
            ...params,
        });
    }

    /**
     * Create a flow as an operator
     * @param flowRate The specified flow rate.
     * @param sender The sender of the flow.
     * @param receiver The receiver of the flow.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    createFlowByOperator = (
        params: ISuperTokenCreateFlowByOperatorParams
    ): Operation => {
        return this.cfaV1.createFlowByOperator({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Update a flow as an operator.
     * @param flowRate The specified flow rate.
     * @param sender The sender of the flow.
     * @param receiver The receiver of the flow.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    updateFlowByOperator = (
        params: ISuperTokenUpdateFlowByOperatorParams
    ): Operation => {
        return this.cfaV1.updateFlowByOperator({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Delete a flow as an operator.
     * @param sender The sender of the flow.
     * @param receiver The receiver of the flow.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    deleteFlowByOperator = (params: ISuperTokenDeleteFlowParams): Operation => {
        return this.cfaV1.deleteFlowByOperator({
            superToken: this.settings.address,
            ...params,
        });
    };

    /** ### IDA Read Functions ### */

    /**
     * Get the details of a `Subscription`.
     * @param publisher the address of the publisher of the index
     * @param indexId the index id
     * @param subscriber the subscriber's address
     * @param providerOrSigner a provider or signer object
     * @returns {Promise<IWeb3Subscription>} Web3 Subscription object
     */
    getSubscription = async (
        params: ISuperTokenGetSubscriptionParams
    ): Promise<IWeb3Subscription> => {
        return await this.idaV1.getSubscription({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Get the details of an `Index`.
     * @param publisher the address of the publisher of the index
     * @param indexId the index id
     * @param providerOrSigner a provider or signer object
     * @returns {Promise<IWeb3Index>} Web3 Index object
     */
    getIndex = async (
        params: ISuperTokenGetIndexParams
    ): Promise<IWeb3Index> => {
        return await this.idaV1.getIndex({
            superToken: this.settings.address,
            ...params,
        });
    };

    /** ### IDA Write Functions ### */

    /**
     * Creates an IDA Index.
     * @param indexId The id of the index.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    createIndex = (params: ISuperTokenBaseIDAParams): Operation => {
        return this.idaV1.createIndex({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Distributes `amount` of token to an index
     * @param indexId The id of the index.
     * @param amount The amount of tokens to be distributed.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    distribute = (params: ISuperTokenDistributeParams): Operation => {
        return this.idaV1.distribute({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Updates the `IndexValue` field of an index.
     * @param indexId The id of the index.
     * @param indexValue The new indexValue.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     *
     * NOTE: It has the same effect as `distribute`, but is closer to the low level data structure of the index.
     */
    updateIndexValue = (
        params: ISuperTokenUpdateIndexValueParams
    ): Operation => {
        return this.idaV1.updateIndexValue({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Updates the `units` allocated to a Subscription.
     * @param indexId The id of the index.
     * @param subscriber The subscriber address whose units you want to update.
     * @param units The amount of units you want to update to.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    updateSubscriptionUnits = (
        params: ISuperTokenUpdateSubscriptionUnitsParams
    ): Operation => {
        return this.idaV1.updateSubscriptionUnits({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Approves a Subscription, so the Subscriber won't need to claim tokens when the Publisher distributes.
     * @param indexId The id of the index.
     * @param publisher The publisher address whose subscription you want to approve.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    approveSubscription = (
        params: ISuperTokenPublisherOperationParams
    ): Operation => {
        return this.idaV1.approveSubscription({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Revokes a Subscription, so the Subscriber will need to claim tokens when the Publisher distributes.
     * @param indexId The id of the index.
     * @param publisher The index publisher address you want to revoke for the subscriber.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    revokeSubscription = (
        params: ISuperTokenPublisherOperationParams
    ): Operation => {
        return this.idaV1.revokeSubscription({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Deletes a Subscription by setting the `units` allocated to the Subscriber to 0.
     * @param indexId The id of the index.
     * @param subscriber The subscriber address whose subscription you want to delete.
     * @param publisher The publisher address of the index you are targeting.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    deleteSubscription = (params: ISuperTokenPubSubParams): Operation => {
        return this.idaV1.deleteSubscription({
            superToken: this.settings.address,
            ...params,
        });
    };

    /**
     * Claims any pending tokens allocated to the Subscription (unapproved).
     * @param indexId The id of the index.
     * @param subscriber The subscriber address who you are claiming for.
     * @param publisher The publisher address of the index you are targeting.
     * @param userData Extra user data provided.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    claim = (params: ISuperTokenPubSubParams): Operation => {
        return this.idaV1.claim({
            superToken: this.settings.address,
            ...params,
        });
    };

    /** ### GDA Read Functions ### */

    /**
     * Retrieves the net flow for a specific token and account.
     *
     * @param account The account address.
     * @param providerOrSigner A provider or signer object
     * @returns The net flow of the account for the token.
     */
    getGDANetFlow = async (
        params: SuperTokenGDAGetNetFlowParams
    ): Promise<string> => {
        return this.gdaV1.getNetFlow({
            token: this.settings.address,
            ...params,
        });
    };

    /**
     * Retrieves the flow rate for a specific token, sender, and pool.
     *
     * @param from The sender address.
     * @param pool The pool address.
     * @param providerOrSigner A provider or signer object
     * @returns The flow rate from the sender to the pool for the token.
     */
    getFlowRate = async (
        params: SuperTokenGDAGetFlowRateParams
    ): Promise<string> => {
        return this.gdaV1.getFlowRate({
            token: this.settings.address,
            ...params,
        });
    };

    /**
     * Estimates the flow distribution's actual flow rate for a specific token, sender, and pool.
     *
     * @param from The sender address.
     * @param pool The pool address.
     * @param requestedFlowRate The requested flow rate.
     * @param providerOrSigner A provider or signer object
     * @returns The flow distribution's actual flow rate and the total distribution flow rate for the pool.
     */
    estimateFlowDistributionActualFlowRate = async (
        params: SuperTokenEstimateDistributionActualFlowRateParams
    ): Promise<FlowDistributionActualFlowRateData> => {
        return this.gdaV1.estimateFlowDistributionActualFlowRate({
            token: this.settings.address,
            ...params,
        });
    };

    /**
     * Estimates the distribution's actual amount for a specific token, sender, and pool.
     *
     * @param from The sender address.
     * @param pool The pool address.
     * @param requestedAmount The requested amount.
     * @param providerOrSigner A provider or signer object
     * @returns The actual amount that will be distributed.
     */
    estimateDistributionActualAmount = async (
        params: SuperTokenEstimateDistributionActualAmountParams
    ): Promise<string> => {
        return this.gdaV1.estimateDistributionActualAmount({
            token: this.settings.address,
            ...params,
        });
    };

    /**
     * Retrieves the pool adjustment flow rate for a specific token and pool.
     *
     * @param pool The pool address.
     * @param providerOrSigner A provider or signer object
     * @returns The pool adjustment flow rate for the token and pool.
     */
    getPoolAdjustmentFlowRate = async (
        params: SuperTokenGetPoolAdjustmentFlowRateParams
    ): Promise<string> => {
        return this.gdaV1.getPoolAdjustmentFlowRate({
            ...params,
        });
    };

    /**
     * Checks if a given token and account form a pool.
     *
     * @param account The account address.
     * @param providerOrSigner A provider or signer object
     * @returns Whether the account is a pool for the token.
     */
    isPool = async (params: SuperTokenIsPoolParams): Promise<boolean> => {
        return this.gdaV1.isPool({
            token: this.settings.address,
            ...params,
        });
    };

    /**
     * Checks if a member is connected to a specific pool.
     *
     * @param pool The pool address.
     * @param member The member address.
     * @param providerOrSigner A provider or signer object
     * @returns Whether the member is connected to the pool.
     */
    isMemberConnected = async (
        params: IsMemberConnectedParams
    ): Promise<boolean> => {
        return this.gdaV1.isMemberConnected({
            ...params,
        });
    };

    /**
     * Retrieves the pool adjustment flow information for a specific pool.
     *
     * @param poolAddress The address of the pool.
     * @param providerOrSigner A provider or signer object
     * @returns The recipient of the pool adjustment flow, the flow hash and the rate of the adjustment flow.
     */
    getPoolAdjustmentFlowInfo = async (
        params: GetPoolAdjustmentFlowInfoParams
    ) => {
        return this.gdaV1.getPoolAdjustmentFlowInfo(params);
    };

    /** ### GDA Write Functions ### */

    /**
     * Creates a new pool with the given token and admin.
     *
     * @param admin The admin address.
     * @param overrides The transaction overrides.
     * @returns The contract transaction and the pool address
     */
    createPool = async (params: SuperTokenCreatePoolParams) => {
        return await this.gdaV1.createPool({
            token: this.settings.address,
            ...params,
        });
    };

    /**
     * Connects a pool to the contract.
     *
     * @param pool The pool address.
     * @param userData The user data.
     * @param overrides The transaction overrides.
     * @returns The call agreement operation result.
     */
    connectPool = (params: ConnectPoolParams): Operation => {
        return this.gdaV1.connectPool({
            ...params,
        });
    };

    /**
     * Disconnects a pool from the contract.
     *
     * @param pool The pool address.
     * @param userData The user data.
     * @param overrides The transaction overrides.
     * @returns The call agreement operation result.
     */
    disconnectPool = (params: DisconnectPoolParams): Operation => {
        return this.gdaV1.disconnectPool({
            ...params,
        });
    };

    /**
     * Distributes funds from the sender's account to the specified pool.
     *
     * @param from The sender's address.
     * @param pool The pool address.
     * @param requestedAmount The requested amount to distribute.
     * @param userData The user data.
     * @param overrides The transaction overrides.
     * @returns The call agreement operation result.
     */
    distributeWithGDA = (params: SuperTokenDistributeParams): Operation => {
        return this.gdaV1.distribute({
            token: this.settings.address,
            ...params,
        });
    };

    /**
     * Distributes the flow from the sender's account to the specified pool.
     *
     * @param from The sender's address.
     * @param pool The pool address.
     * @param requestedFlowRate The requested flow rate.
     * @param userData The user data.
     * @param overrides The transaction overrides.
     * @returns The call agreement operation result.
     */
    distributeFlow = (params: SuperTokenDistributeFlowParams): Operation => {
        return this.gdaV1.distributeFlow({
            token: this.settings.address,
            ...params,
        });
    };

    /** ### Governance Read Functions ### */

    getGovernanceParameters = async (
        providerOrSigner: ethers.providers.Provider | ethers.Signer
    ): Promise<IWeb3GovernanceParams> => {
        return this.governance.getGovernanceParameters({
            providerOrSigner,
            token: this.settings.address,
        });
    };
}

/**
 * WrapperSuperToken has an underlying ERC20 token.
 */
export class WrapperSuperToken extends SuperToken {
    override readonly underlyingToken: ERC20Token;

    constructor(
        options: ITokenOptions,
        settings: ITokenSettings & { underlyingTokenAddress: string }
    ) {
        super(options, settings);
        this.underlyingToken = new ERC20Token(settings.underlyingTokenAddress);
    }

    /** ### WrapperSuperToken Contract Write Functions ### */

    /**
     * Downgrade `amount` SuperToken's.
     * @param amount The amount to be downgraded.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    downgrade = ({
        amount,
        overrides,
    }: {
        amount: string;
        overrides?: Overrides & { from?: string };
    }): Operation => {
        const txn = this.contract.populateTransaction.downgrade(
            amount,
            overrides || {}
        );
        return new Operation(txn, "SUPERTOKEN_DOWNGRADE");
    };

    /**
     * Downgrade `amount` of an ERC20 token to its SuperToken to `to` address.
     * @param amount The amount to be downgraded.
     * @param to The destination of the downgraded ERC20 token.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed.
     */
    downgradeTo = ({
        amount,
        to,
        overrides,
    }: {
        amount: string;
        to: string;
        overrides?: Overrides & { from?: string };
    }) => {
        const txn = this.contract.populateTransaction.downgradeTo(to, amount, {
            ...overrides,
        });
        return new Operation(txn, "UNSUPPORTED");
    };

    /**
     * Upgrade `amount` SuperToken's.
     * @param amount The amount to be upgraded.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed or batched.
     */
    upgrade = ({
        amount,
        overrides,
    }: {
        amount: string;
        overrides?: Overrides & { from?: string };
    }): Operation => {
        const txn = this.contract.populateTransaction.upgrade(
            amount,
            overrides || {}
        );
        return new Operation(txn, "SUPERTOKEN_UPGRADE");
    };

    /**
     * Upgrade `amount` of an ERC20 token to its SuperToken to `to` address.
     * @param amount The amount to be upgraded.
     * @param to The destination of the upgraded wrapper super tokens.
     * @param data Bytes userData
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed.
     */
    upgradeTo = ({
        amount,
        to,
        data = "0x",
        overrides,
    }: {
        amount: string;
        to: string;
        data?: BytesLike;
        overrides?: Overrides & { from?: string };
    }) => {
        const txn = this.contract.populateTransaction.upgradeTo(
            to,
            amount,
            data,
            {
                ...overrides,
            }
        );
        return new Operation(txn, "UNSUPPORTED");
    };
}

/**
 * PureSuperToken doesn't have any underlying ERC20 token.
 */
export class PureSuperToken extends SuperToken {
    constructor(options: ITokenOptions, settings: ITokenSettings) {
        super(options, settings);
    }
}

/**
 * NativeAssetSuperToken wraps the native asset of the network.
 */
export class NativeAssetSuperToken extends SuperToken {
    readonly nativeTokenSymbol: string;

    constructor(
        options: ITokenOptions,
        settings: ITokenSettings,
        nativeTokenSymbol: string
    ) {
        super(options, settings);
        this.nativeTokenSymbol = nativeTokenSymbol;
    }

    get nativeAssetContract() {
        return new ethers.Contract(
            this.settings.address,
            ISETH__factory.abi
        ) as ISETH;
    }

    /**
     * Upgrade `amount` of a network's native asset to its SuperToken.
     * @param amount The amount to be upgraded.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed.
     */
    upgrade = ({
        amount,
        overrides,
    }: {
        amount: string;
        overrides?: Overrides & { from?: string };
    }): Operation => {
        const txn = this.nativeAssetContract.populateTransaction.upgradeByETH({
            ...overrides,
            value: amount,
        });
        return new Operation(txn, "UNSUPPORTED");
    };

    /**
     * Upgrade `amount` of a network's native asset to its SuperToken to `to` address.
     * @param amount The amount to be upgraded.
     * @param to The destination of the upgraded native asset super tokens.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed.
     */
    upgradeTo = ({
        amount,
        to,
        overrides,
    }: {
        amount: string;
        to: string;
        overrides?: Overrides & { from?: string };
    }) => {
        const txn = this.nativeAssetContract.populateTransaction.upgradeByETHTo(
            to,
            {
                ...overrides,
                value: amount,
            }
        );
        return new Operation(txn, "UNSUPPORTED");
    };

    /**
     * Downgrade `amount` of a native asset super token to the underlying native asset.
     * @param amount The amount to be upgraded.
     * @param overrides ethers overrides object for more control over the transaction sent.
     * @returns {Operation} An instance of Operation which can be executed.
     */
    downgrade = ({
        amount,
        overrides,
    }: {
        amount: string;
        overrides?: Overrides & { from?: string };
    }) => {
        const txn = this.nativeAssetContract.populateTransaction.downgradeToETH(
            amount,
            {
                ...overrides,
            }
        );
        return new Operation(txn, "UNSUPPORTED");
    };
}
