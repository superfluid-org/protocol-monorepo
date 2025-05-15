import {type BaseSuperTokenMutation, type NothingString} from '../../../argTypes';

/**
 * Create a flow of the token of this class.
 */
export interface FlowCreateMutation extends BaseSuperTokenMutation {
    /** The sender of the flow. Signer is used when left empty. */
    senderAddress?: string;
    /** The receiver of the flow. */
    receiverAddress: string;
    /** The specified flow rate. */
    flowRateWei: string;
    /** Extra user data provided. */
    userDataBytes: string | NothingString;
}

/**
 * Update a flow of the token of this class.
 */
export interface FlowUpdateMutation extends BaseSuperTokenMutation {
    /** The sender of the flow. If not specified then signer address is used. */
    senderAddress?: string;
    /** The receiver of the flow. */
    receiverAddress: string;
    /** The specified flow rate. */
    flowRateWei: string;
    /** Extra user data provided. */
    userDataBytes: string | NothingString;
}

/**
 * Delete a flow of the token of this class.
 */
export interface FlowDeleteMutation extends BaseSuperTokenMutation {
    /** The sender of the flow. */
    senderAddress?: string;
    /** The receiver of the flow. */
    receiverAddress: string;
    /** Extra user data provided. */
    userDataBytes: string | NothingString;
}
