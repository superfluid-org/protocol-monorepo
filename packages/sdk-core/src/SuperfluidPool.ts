import { ContractTransaction, ethers } from "ethers";

import { SFError } from "./SFError";
import {
    ClaimableData,
    ClaimAllForMemberParams,
    ERC20AllowanceParams,
    ERC20ApproveParams,
    ERC20BalanceOfParams,
    ERC20TransferFromParams,
    ERC20TransferParams,
    GetClaimableNowParams,
    GetClaimableParams,
    GetDisconnectedBalanceParams,
    GetMemberFlowRateParams,
    GetTotalAmountReceivedByMemberParams,
    GetUnitsParams,
    SuperfluidPoolDecreaseAllowanceParams,
    SuperfluidPoolIncreaseAllowanceParams,
    UpdateMemberParams,
} from "./interfaces";
import { ISuperfluidPool, ISuperfluidPool__factory } from "./typechain-types";
import { normalizeAddress } from "./utils";

/**
 * Superfluid Pool Helper Class
 * @description A helper class to interact with the SuperfluidPool contract.
 */
export default class SuperfluidPoolClass {
    readonly contract: ISuperfluidPool;

    constructor(poolAddress: string) {
        this.contract = new ethers.Contract(
            poolAddress,
            ISuperfluidPool__factory.abi
        ) as ISuperfluidPool;
    }

    /**
     * Retrieves the pool admin.
     * @param providerOrSigner A provider or signer object
     * @returns The pool admin.
     */
    getPoolAdmin = async (
        providerOrSigner: ethers.providers.Provider | ethers.Signer
    ): Promise<string> => {
        try {
            return await this.contract.connect(providerOrSigner).admin();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting the pool admin.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the SuperToken.
     * @param providerOrSigner A provider or signer object
     * @returns The SuperToken for this pool.
     */
    getSuperToken = async (
        providerOrSigner: ethers.providers.Provider | ethers.Signer
    ): Promise<string> => {
        try {
            return await this.contract.connect(providerOrSigner).superToken();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting the pool's SuperToken.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the total units.
     * Returns the same value as totalSupply.
     * @param providerOrSigner A provider or signer object
     * @returns The total units.
     */
    getTotalUnits = async (
        providerOrSigner: ethers.providers.Provider | ethers.Signer
    ): Promise<string> => {
        try {
            return (
                await this.contract.connect(providerOrSigner).getTotalUnits()
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting total units.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the total connected units.
     * @param providerOrSigner A provider or signer object
     * @returns The total connected units.
     */
    getTotalConnectedUnits = async (
        providerOrSigner: ethers.providers.Provider | ethers.Signer
    ): Promise<string> => {
        try {
            return (
                await this.contract
                    .connect(providerOrSigner)
                    .getTotalConnectedUnits()
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting total connected units.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the units for a specific member.
     * @param member The member's address.
     * @param providerOrSigner A provider or signer object
     * @returns The units for the specified member.
     */
    getUnits = async (params: GetUnitsParams): Promise<string> => {
        try {
            return (
                await this.contract
                    .connect(params.providerOrSigner)
                    .getUnits(params.member)
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting units.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the total connected flow rate.
     * @param providerOrSigner A provider or signer object
     * @returns The total connected flow rate.
     */
    getTotalConnectedFlowRate = async (
        providerOrSigner: ethers.providers.Provider | ethers.Signer
    ): Promise<string> => {
        try {
            return (
                await this.contract
                    .connect(providerOrSigner)
                    .getTotalConnectedFlowRate()
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message:
                    "There was an error getting total connected flow rate.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the total disconnected flow rate.
     * @param providerOrSigner A provider or signer object
     * @returns The total disconnected flow rate.
     */
    getTotalDisconnectedFlowRate = async (
        providerOrSigner: ethers.providers.Provider | ethers.Signer
    ): Promise<string> => {
        try {
            return (
                await this.contract
                    .connect(providerOrSigner)
                    .getTotalDisconnectedFlowRate()
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message:
                    "There was an error getting total disconnected flow rate.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the disconnected balance for the pool a specific time.
     * @param time The time of the disconnected balance.
     * @param providerOrSigner A provider or signer object
     * @returns The disconnected balance.
     */
    getDisconnectedBalance = async (
        params: GetDisconnectedBalanceParams
    ): Promise<string> => {
        try {
            return (
                await this.contract
                    .connect(params.providerOrSigner)
                    .getDisconnectedBalance(params.time)
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting disconnected balance.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the flow rate for a specific member.
     * @param member The member's address.
     * @param providerOrSigner A provider or signer object
     * @returns The flow rate for the specified member.
     */
    getMemberFlowRate = async (
        params: GetMemberFlowRateParams
    ): Promise<string> => {
        try {
            return (
                await this.contract
                    .connect(params.providerOrSigner)
                    .getMemberFlowRate(params.member)
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting member flow rate.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the flow rate for a specific member.
     * @param member The member's address.
     * @param providerOrSigner A provider or signer object
     * @returns The total amount received by the member.
     */
    getTotalAmountReceivedByMember = async (
        params: GetTotalAmountReceivedByMemberParams
    ): Promise<string> => {
        try {
            return (
                await this.contract
                    .connect(params.providerOrSigner)
                    .getTotalAmountReceivedByMember(params.member)
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message:
                    "There was an error getting the total amount received by member.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the claimable amount for a specific member and time.
     * @param member The member's address.
     * @param time The amount claimable at time.
     * @param providerOrSigner A provider or signer object
     * @returns The claimable amount.
     */
    getClaimable = async (params: GetClaimableParams): Promise<string> => {
        const normalizedMember = normalizeAddress(params.member);
        try {
            return (
                await this.contract
                    .connect(params.providerOrSigner)
                    .getClaimable(normalizedMember, params.time)
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting claimable amount.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the claimable amount for a specific member at the current time.
     * @param member The member's address.
     * @param providerOrSigner A provider or signer object
     * @returns ClaimableData: { timestamp, claimableBalance }
     */
    getClaimableNow = async (
        params: GetClaimableNowParams
    ): Promise<ClaimableData> => {
        try {
            const data = await this.contract
                .connect(params.providerOrSigner)
                .getClaimableNow(params.member);
            return {
                timestamp: data.timestamp.toString(),
                claimableBalance: data.claimableBalance.toString(),
            };
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting claimable amount.",
                cause: err,
            });
        }
    };

    /**
     * Updates the units for a specific member.
     * @param member The member's address.
     * @param newUnits The new units value.
     * @param signer The transaction signer.
     * @returns A promise that resolves when the update is complete.
     */
    updateMemberUnits = async (
        params: UpdateMemberParams
    ): Promise<ContractTransaction> => {
        const normalizedMember = normalizeAddress(params.member);
        return await this.contract
            .connect(params.signer)
            .updateMemberUnits(normalizedMember, params.newUnits);
    };

    /**
     * Claims all available funds for a specific member.
     * @param member The member's address.
     * @param signer The transaction signer.
     * @returns A promise that resolves when the claim is complete.
     */
    claimAllForMember = async (
        params: ClaimAllForMemberParams
    ): Promise<ContractTransaction> => {
        return await this.contract
            .connect(params.signer)
            ["claimAll(address)"](params.member);
    };

    /**
     * Claims all available funds.
     * @returns A promise that resolves when the claim is complete.
     */
    claimAll = async (signer: ethers.Signer): Promise<ContractTransaction> => {
        return await this.contract.connect(signer)["claimAll()"]();
    };

    /**
     * Increases the allowance for a specific spender.
     * @param spender The spender's address.
     * @param amount The amount to increase the allowance by.
     * @param signer The transaction signer.
     * @returns A promise that resolves when the allowance increase is complete.
     */
    increaseAllowance = async (
        params: SuperfluidPoolIncreaseAllowanceParams
    ): Promise<ContractTransaction> => {
        const normalizedSpender = normalizeAddress(params.spender);
        return await this.contract
            .connect(params.signer)
            .increaseAllowance(normalizedSpender, params.amount);
    };

    /**
     * Decreases the allowance for a specific spender.
     * @param spender The spender's address.
     * @param amount The amount to decrease the allowance by.
     * @param signer The transaction signer.
     * @param overrides The transaction overrides.
     * @returns A promise that resolves when the allowance decrease is complete.
     */
    decreaseAllowance = async (
        params: SuperfluidPoolDecreaseAllowanceParams
    ): Promise<ContractTransaction> => {
        const normalizedSpender = normalizeAddress(params.spender);
        return await this.contract
            .connect(params.signer)
            .decreaseAllowance(normalizedSpender, params.amount);
    };

    /**
     * Retrieves the total supply.
     * Returns the same value as getTotalUnits.
     * @returns The total supply.
     */
    totalSupply = async (
        providerOrSigner: ethers.providers.Provider | ethers.Signer
    ): Promise<string> => {
        try {
            return (
                await this.contract.connect(providerOrSigner).totalSupply()
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting total supply.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the balance of an account.
     * @param account The account's address.
     * @param providerOrSigner A provider or signer object
     * @returns The account's balance.
     */
    balanceOf = async (params: ERC20BalanceOfParams): Promise<string> => {
        const normalizedAccount = normalizeAddress(params.account);
        try {
            return (
                await this.contract
                    .connect(params.providerOrSigner)
                    .balanceOf(normalizedAccount)
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting balance.",
                cause: err,
            });
        }
    };

    /**
     * Retrieves the allowance for a specific owner and spender.
     * @param owner The owner's address.
     * @param spender The spender's address.
     * @param providerOrSigner A provider or signer object
     * @returns The allowance.
     */
    allowance = async (params: ERC20AllowanceParams): Promise<string> => {
        const normalizedOwner = normalizeAddress(params.owner);
        const normalizedSpender = normalizeAddress(params.spender);
        try {
            return (
                await this.contract
                    .connect(params.providerOrSigner)
                    .allowance(normalizedOwner, normalizedSpender)
            ).toString();
        } catch (err) {
            throw new SFError({
                type: "SUPERFLUID_POOL_READ",
                message: "There was an error getting allowance.",
                cause: err,
            });
        }
    };

    /**
     * Approves an amount to be spent by a specific spender.
     * @param spender The spender's address.
     * @param amount The amount to approve.
     * @param signer The transaction signer.
     * @returns A promise that resolves when the approval is complete.
     */
    approve = async (
        params: ERC20ApproveParams
    ): Promise<ContractTransaction> => {
        const normalizedSpender = normalizeAddress(params.spender);
        return await this.contract
            .connect(params.signer)
            .approve(normalizedSpender, params.amount);
    };

    /**
     * Transfers an amount to a specific recipient.
     * @param to The recipient's address.
     * @param amount The amount to transfer.
     * @param signer The transaction signer.
     * @returns A promise that resolves when the transfer is complete.
     */
    transfer = async (
        params: ERC20TransferParams
    ): Promise<ContractTransaction> => {
        const normalizedTo = normalizeAddress(params.to);
        return await this.contract
            .connect(params.signer)
            .transfer(normalizedTo, params.amount);
    };

    /**
     * Transfers an amount from a specific sender to a recipient.
     * @param from The sender's address.
     * @param to The recipient's address.
     * @param amount The amount to transfer.
     * @param signer The transaction signer.
     * @returns A promise that resolves when the transfer is complete.
     */
    transferFrom = async (
        params: ERC20TransferFromParams
    ): Promise<ContractTransaction> => {
        const normalizedFrom = normalizeAddress(params.from);
        const normalizedTo = normalizeAddress(params.to);
        return await this.contract
            .connect(params.signer)
            .transferFrom(normalizedFrom, normalizedTo, params.amount);
    };
}
