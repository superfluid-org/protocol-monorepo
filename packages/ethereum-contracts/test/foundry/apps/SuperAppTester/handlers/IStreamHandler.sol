// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

// Interface to define expected behavior of a stream handler.
// We are defining a stream operation as a create, update, or delete flow.
interface IStreamHandler {
    function createFlow(address sender, int96 flowRate) external;
    function updateFlow(address sender, int96 flowRate) external;
    function deleteFlow(address sender) external;
}
