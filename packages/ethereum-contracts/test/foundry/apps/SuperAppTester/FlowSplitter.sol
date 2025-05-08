// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// code taken from:
// https://github.com/superfluid-finance/super-examples/blob/main/projects/flow-splitter/contracts/FlowSplitter.sol

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { CFASuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/CFASuperAppBase.sol";
import {
    ISuperfluid,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

contract FlowSplitter is CFASuperAppBase {
    using SuperTokenV1Library for ISuperToken;

    /// @dev Account that ought to be routed the majority of the inflows
    address public mainReceiver;

    /// @dev Accout that ought to be routed the minority of the inflows
    address public sideReceiver;

    /// @dev number out of 1000 representing portion of inflows to be redirected to sideReceiver
    ///      Ex: 300 would represent 30%
    int96 public sideReceiverPortion;

    /// @dev Super Token that the FlowSplitter will accept streams of
    ISuperToken public acceptedSuperToken;

    constructor(
        address _mainReceiver,
        address _sideReceiver,
        int96 _sideReceiverPortion,
        ISuperToken _acceptedSuperToken,
        ISuperfluid _host
    ) CFASuperAppBase(_host) {
        selfRegister(true, true, true);
        mainReceiver = _mainReceiver;
        sideReceiver = _sideReceiver;
        sideReceiverPortion = _sideReceiverPortion;
        acceptedSuperToken = _acceptedSuperToken;
    }

    /// @dev checks that only the acceptedToken is used when sending streams into this contract
    /// @param superToken the token being streamed into the contract
    function isAcceptedSuperToken(ISuperToken superToken) public view override returns (bool) {
        return superToken == acceptedSuperToken;
    }

    /// @dev updates the split of the outflow to mainReceiver and sideReceiver
    /// @param newSideReceiverPortion the new portion of inflows to be redirected to sideReceiver
    function updateSplit(int96 newSideReceiverPortion) public {
        sideReceiverPortion = newSideReceiverPortion;

        // get current outflow rate
        int96 totalOutflowRate = acceptedSuperToken.getFlowRate(address(this), mainReceiver)
            + acceptedSuperToken.getFlowRate(address(this), sideReceiver);

        // update outflows
        acceptedSuperToken.updateFlow(mainReceiver, (totalOutflowRate * (1000 - newSideReceiverPortion)) / 1000);

        acceptedSuperToken.updateFlow(sideReceiver, (totalOutflowRate * newSideReceiverPortion) / 1000);
    }

    // ---------------------------------------------------------------------------------------------
    // CALLBACK LOGIC

    function onFlowCreated(ISuperToken superToken, address sender, bytes calldata ctx)
        internal
        override
        returns (bytes memory newCtx)
    {
        newCtx = ctx;

        // get inflow rate from sender
        int96 inflowRate = superToken.getFlowRate(sender, address(this));

        // if there's no outflow already, create outflows
        if (superToken.getFlowRate(address(this), mainReceiver) == 0) {
            newCtx =
                superToken.createFlowWithCtx(mainReceiver, (inflowRate * (1000 - sideReceiverPortion)) / 1000, newCtx);

            newCtx = superToken.createFlowWithCtx(sideReceiver, (inflowRate * sideReceiverPortion) / 1000, newCtx);
        }
        // otherwise, there's already outflows which should be increased
        else {
            newCtx = superToken.updateFlowWithCtx(
                mainReceiver,
                acceptedSuperToken.getFlowRate(address(this), mainReceiver)
                    + (inflowRate * (1000 - sideReceiverPortion)) / 1000,
                newCtx
            );

            newCtx = superToken.updateFlowWithCtx(
                sideReceiver,
                acceptedSuperToken.getFlowRate(address(this), sideReceiver) + (inflowRate * sideReceiverPortion) / 1000,
                newCtx
            );
        }
    }

    function onFlowUpdated(
        ISuperToken superToken,
        address sender,
        int96 previousFlowRate,
        uint256, /*lastUpdated*/
        bytes calldata ctx
    ) internal override returns (bytes memory newCtx) {
        newCtx = ctx;

        // get inflow rate change from sender
        int96 inflowChange = superToken.getFlowRate(sender, address(this)) - previousFlowRate;

        // update outflows
        newCtx = superToken.updateFlowWithCtx(
            mainReceiver,
            acceptedSuperToken.getFlowRate(address(this), mainReceiver)
                + (inflowChange * (1000 - sideReceiverPortion)) / 1000,
            newCtx
        );

        newCtx = superToken.updateFlowWithCtx(
            sideReceiver,
            acceptedSuperToken.getFlowRate(address(this), sideReceiver) + (inflowChange * sideReceiverPortion) / 1000,
            newCtx
        );
    }

    function onFlowDeleted(
        ISuperToken superToken,
        address, /*sender*/
        address receiver,
        int96 previousFlowRate,
        uint256, /*lastUpdated*/
        bytes calldata ctx
    ) internal override returns (bytes memory newCtx) {
        newCtx = ctx;

        // remaining inflow is equal to total outflow less the inflow that just got deleted
        int96 remainingInflow = (
            acceptedSuperToken.getFlowRate(address(this), mainReceiver)
                + acceptedSuperToken.getFlowRate(address(this), sideReceiver)
        ) - previousFlowRate;

        // handle "rogue recipients" with sticky stream - see readme
        if (receiver == mainReceiver || receiver == sideReceiver) {
            newCtx = superToken.createFlowWithCtx(receiver, previousFlowRate, newCtx);
        }

        // if there is no more inflow, outflows should be deleted
        if (remainingInflow <= 0) {
            newCtx = superToken.deleteFlowWithCtx(address(this), mainReceiver, newCtx);

            newCtx = superToken.deleteFlowWithCtx(address(this), sideReceiver, newCtx);
        }
        // otherwise, there's still inflow left and outflows must be updated
        else {
            newCtx = superToken.updateFlowWithCtx(
                mainReceiver, (remainingInflow * (1000 - sideReceiverPortion)) / 1000, newCtx
            );

            newCtx = superToken.updateFlowWithCtx(sideReceiver, (remainingInflow * sideReceiverPortion) / 1000, newCtx);
        }
    }
}
