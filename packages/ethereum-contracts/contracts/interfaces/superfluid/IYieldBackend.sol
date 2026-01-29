// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.11;

/**
 * A yield backend acts as interface between an ERC20 wrapper SuperToken and a yield generating protocol.
 * The underlying token can be deposited on upgrade and withdrawn on downgrade.
 *
 * It is possible to transition from no/one yield backend to another/no yield backend.
 * one -> another could be seen as a composition of one -> no -> another
 *
 * one -> no means withdraw not in the context of a downgrade.
 *
 * Contracts implementing this act as a kind of hot-pluggable library,
 * using delegatecall to execute its logic on the SuperToken contract.
 * This means that underlying tokens are transferred directly between the SuperToken contract and the yield protocol,
 * as are yield protocol tokens representing positions in that protocol.
 * If an implementation requires to hold state, it shall do so using a namespaced storage layout (EIP-7201).
 */
interface IYieldBackend {
    /// Invoked by `SuperToken` as delegatecall.
    /// Sets up the SuperToken as needed, e.g. by giving required approvals.
    function enable() external;

    /// Invoked by `SuperToken` as delegatecall.
    /// Restores the prior state, e.g. by revoking given approvals
    function disable() external;

    /// Invoked by `SuperToken` as delegatecall.
    /// Deposits the given amount of the underlying asset into the yield backend.
    function deposit(uint256 amount) external;

    /// Invoked by `SuperToken` as delegatecall.
    /// Withdraws the given amount of the underlying asset from the yield backend.
    function withdraw(uint256 amount) external;

    /// Invoked by `SuperToken` as delegatecall.
    /// Withdraws the maximum withdrawable amount of the underlying asset from the yield backend.
    function withdrawMax() external;

    /// Invoked by `SuperToken` as delegatecall.
    /// tranfers the deposited asset exceeding totalSupply of the SuperToken to the preset receiver account
    function withdrawSurplus(uint256 totalSupply) external;
}
