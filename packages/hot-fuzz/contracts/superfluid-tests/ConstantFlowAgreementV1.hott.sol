// SPDX-License-Identifier: AGPLv3
// solhint-disable reason-string
pragma solidity >= 0.8.0;

import {SuperToken} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import "../HotFuzzBase.sol";

abstract contract CFAHotFuzzMixin is HotFuzzBase {
    using SuperTokenV1Library for SuperToken;

    function createFlow(uint8 a, uint8 b, int64 flowRate) public {
        require(flowRate > 0);
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);

        testerA.flow(address(testerB), int96(flowRate));
    }

    function deleteFlow(uint8 a, uint8 b) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);

        testerA.flow(address(testerB), 0);
    }

    /// @notice testerA liquidates a flow from testerB to testerC
    /// @dev Self-liquidate (A == B) is allowed; reward balance asserts are skipped in that case
    ///      because sender and liquidator are the same account.
    function cfaLiquidateFlow(uint8 a, uint8 b, uint8 c) public {
        (SuperfluidTester liquidator, SuperfluidTester sender, SuperfluidTester recipient) = _getThreeTesters(a, b, c);

        bool flowExists = superToken.getFlowRate(address(sender), address(recipient)) > 0;
        (,, uint256 singleDeposit,) = superToken.getFlowInfo(address(sender), address(recipient));
        (bool isPatricianPeriod,) = sf.cfa.isPatricianPeriodNow(superToken, address(sender));
        LiquidationExpectations memory expectations =
            _getLiquidationExpectations(address(sender), address(liquidator), singleDeposit, isPatricianPeriod);

        if (!(flowExists && expectations.isCritical)) return;

        bool selfLiquidate = address(liquidator) == address(sender);
        try liquidator.cfaLiquidate(address(sender), address(recipient)) {
            if (superToken.getFlowRate(address(sender), address(recipient)) != 0) {
                liquidationPostconditionViolated = true;
            } else if (!selfLiquidate && !_checkLiquidationBalances(expectations, address(liquidator))) {
                liquidationPostconditionViolated = true;
            }
        } catch {
            liquidationFails = true;
        }
    }

    function setFlowPermissions(
        uint8 a,
        uint8 b,
        bool allowCreate,
        bool allowUpdate,
        bool allowDelete,
        int96 flowRateAllowance
    ) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);

        testerA.setFlowPermissions(address(testerB), allowCreate, allowUpdate, allowDelete, flowRateAllowance);
    }

    function setMaxFlowPermissions(uint8 a, uint8 b) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);

        testerA.setMaxFlowPermissions(address(testerB));
    }

    function revokeFlowPermissions(uint8 a, uint8 b) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);

        testerA.revokeFlowPermissions(address(testerB));
    }

    function increaseFlowRateAllowance(uint8 a, uint8 b, int96 addedFlowRateAllowance) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);

        testerA.increaseFlowRateAllowance(address(testerB), addedFlowRateAllowance);
    }

    function decreaseFlowRateAllowance(uint8 a, uint8 b, int96 subtractedFlowRateAllowance) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);

        testerA.decreaseFlowRateAllowance(address(testerB), subtractedFlowRateAllowance);
    }

    function increaseFlowRateAllowanceWithPermissions(
        uint8 a,
        uint8 b,
        uint8 permissionsToAdd,
        int96 addedFlowRateAllowance
    ) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);

        testerA.increaseFlowRateAllowanceWithPermissions(address(testerB), permissionsToAdd, addedFlowRateAllowance);
    }

    function decreaseFlowRateAllowanceWithPermissions(
        uint8 a,
        uint8 b,
        uint8 permissionsToRemove,
        int96 subtractedFlowRateAllowance
    ) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);

        testerA.decreaseFlowRateAllowanceWithPermissions(
            address(testerB), permissionsToRemove, subtractedFlowRateAllowance
        );
    }
}

contract CFAHotFuzz is CFAHotFuzzMixin {
    constructor() HotFuzzBase(10) {
        _initTesters();
    }
}
