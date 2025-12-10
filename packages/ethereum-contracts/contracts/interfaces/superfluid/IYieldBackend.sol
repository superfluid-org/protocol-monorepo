// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * A yield backend acts as interface between an ERC20 wrapper SuperToken and a yield generating protocol.
 * The underlying token can be deposited on updrade and withdrawn on downgrade.
 *
 * It is possible to transition from no/one yield backend to another/no yield backend.
 * one -> another could be seen as a composition of one -> no -> another
 *
 * one -> no means withdraw not in the context of a downgrade.
 */
interface IYieldBackend {
    // returns the config to be provided to delegateInitSuperToken() and deinit()
    function getConfig() external returns (bytes memory config);

    // to be invoked as delegatecall
    function delegateInitSuperToken(bytes memory config) external;
    // to be invoked as delegatecall
    function delegateDeinitSuperToken(bytes memory config) external;

    function deposit(uint256 amount) external;
    function depositMax() external;

    function withdraw(uint256 amount) external;
    function withdrawMax() external;
}
