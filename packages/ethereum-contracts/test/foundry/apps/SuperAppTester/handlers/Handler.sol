// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "./IStreamHandler.sol";
import { SuperTokenV1Library, ISuperToken } from "../../../../../contracts/apps/SuperTokenV1Library.sol";

contract Handler is IStreamHandler, Test {
    using SuperTokenV1Library for ISuperToken;

    address public superAppAddress;
    ISuperToken public superToken;

    // default flow rate bounds, can be overridden on constructor
    int96 public minFlowRate = 1;
    int96 public maxFlowRate = (type(int96).max) >> 14;

    // counters
    uint256 public _createFlowCallCount;
    uint256 public _skipCreateFlowCount;
    uint256 public _updateFlowCallCount;
    uint256 public _skipUpdateFlowCount;
    uint256 public _deleteFlowCallCount;
    uint256 public _skipDeleteFlowCount;

    constructor(address _superAppAddress, ISuperToken _superToken, int96 _minFlowRate, int96 _maxFlowRate) {
        superAppAddress = _superAppAddress;
        superToken = _superToken;
        if (_minFlowRate > 0) {
            minFlowRate = _minFlowRate;
        }
        if (_maxFlowRate > 0) {
            maxFlowRate = _maxFlowRate;
        }
    }

    function createFlow(address sender, int96 flowRate) external override {
        bound(flowRate, minFlowRate, maxFlowRate);
        vm.startPrank(sender);
        if (superToken.getFlowRate(sender, superAppAddress) == 0) {
            _createFlowCallCount++;
            superToken.createFlow(superAppAddress, flowRate);
        } else {
            _skipCreateFlowCount++;
        }

        vm.stopPrank();
    }

    function updateFlow(address sender, int96 flowRate) external override {
        bound(flowRate, minFlowRate, maxFlowRate);
        vm.startPrank(sender);
        if (superToken.getFlowRate(sender, superAppAddress) > 0) {
            _updateFlowCallCount++;
            superToken.updateFlow(superAppAddress, flowRate);
        } else {
            _skipUpdateFlowCount++;
        }
        vm.stopPrank();
    }

    function deleteFlow(address sender) external override {
        vm.startPrank(sender);
        if (superToken.getFlowRate(sender, superAppAddress) > 0) {
            _deleteFlowCallCount++;
            superToken.deleteFlow(sender, superAppAddress);
        } else {
            _skipDeleteFlowCount++;
        }
        vm.stopPrank();
    }

    function printCounters() external view {
        console.log("createFlowCallCount: %s", _createFlowCallCount);
        console.log("skipCreateFlowCount: %s", _skipCreateFlowCount);
        console.log("updateFlowCallCount: %s", _updateFlowCallCount);
        console.log("skipUpdateFlowCount: %s", _skipUpdateFlowCount);
        console.log("deleteFlowCallCount: %s", _deleteFlowCallCount);
        console.log("skipDeleteFlowCount: %s", _skipDeleteFlowCount);
    }
}
