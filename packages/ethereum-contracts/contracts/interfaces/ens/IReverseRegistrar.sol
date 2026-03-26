// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

/**
 * @dev Minimal interface for ENS Reverse Registrar.
 * Used to set the reverse record (address -> name) for the calling contract at deployment.
 */
interface IReverseRegistrar {
    /**
     * @dev Sets the `name()` record for the reverse ENS record associated with the calling account.
     * When called from a contract constructor, the caller is the contract being deployed.
     * @param name The ENS name to set (e.g. "clearmacro.base.eth")
     *
     * NOTE:
     * - L1 ReverseRegistrar returns the node hash.
     * - L2ReverseRegistrar returns no value.
     *
     * We intentionally model this as returning nothing so the call remains ABI-compatible
     * with both variants and does not revert due to return-data decoding mismatch.
     */
    function setName(string memory name) external;
}
