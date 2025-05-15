import {type BaseQuery, type BaseSuperTokenMutation} from '../../../argTypes';

/**
 * Downgrade `amount` SuperToken's.
 */
export interface SuperTokenDowngradeMutation extends BaseSuperTokenMutation {
    /** The amount to be downgraded. */
    amountWei: string;
}

/**
 * Upgrade `amount` SuperToken's.
 */
export interface SuperTokenUpgradeMutation extends BaseSuperTokenMutation {
    /** The amount to be upgraded. */
    amountWei: string;
}

/**
 * How much does the underlying token have allowance for super token upgrade.
 */
export interface SuperTokenUpgradeAllowanceQuery extends BaseQuery<string> {
    /**
     * Account whose allowance to check.
     */
    accountAddress: string;
    superTokenAddress: string;
}

/**
 * Transfer `receiver` `amount` tokens.
 */
export interface SuperTokenTransferMutation extends BaseSuperTokenMutation {
    /** The receiver of the transfer. */
    receiverAddress: string;
    /** The amount to be transferred. */
    amountWei: string;
}
