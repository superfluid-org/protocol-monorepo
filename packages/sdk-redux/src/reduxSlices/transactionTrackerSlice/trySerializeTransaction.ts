import {SignatureLike} from '@ethersproject/bytes';
import {ethers, Transaction} from 'ethers';

/**
 * The use-case arose from Gnosis Safe transaction serialization failing.
 */
export const trySerializeTransaction = (
    transaction: Partial<Transaction>,
    signature?: SignatureLike
): string | undefined => {
    try {
        return ethers.utils.serializeTransaction(transaction, signature);
    } catch (error) {
        // This tends to happen with Gnosis Safe which changes the transaction response structure.

        if (transaction.hash) {
            // Check if the transaction hash contains a prefix (e.g. chainId) followed by colon
            const parts = transaction.hash.split(':');
            if (parts.length === 2) {
                // Remove the prefix and set the plain transaction hash
                transaction.hash = parts[1];
                // Second attempt to serialize the transaction with the correct (?) hash
                try {
                    return ethers.utils.serializeTransaction(transaction, signature);
                } catch {
                    // Log the first error instead
                    console.warn(error);
                }
            }
        }

        console.warn(error);
    }
    return undefined;
};
