// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * A yield backend acts as interface between an ERC20 wrapper SuperToken and a yield generating protocol.
 * The underlying token can be deposited on upgrade and withdrawn on downgrade.
 *
 * It is possible to transition from no/one yield backend to another/no yield backend.
 * one -> another could be seen as a composition of one -> no -> another
 *
 * one -> no means withdraw not in the context of a downgrade.
 */
interface IYieldBackend {
    function init() external;
    function deinit() external;

    function deposit(uint256 amount) external;
    function depositMax() external;
    function withdraw(uint256 amount) external;
    function withdrawMax() external;
}
