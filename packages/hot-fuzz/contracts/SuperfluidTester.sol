// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.8.0;

import "@superfluid-finance/ethereum-contracts/contracts/superfluid/Superfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import {ISuperfluidPool} from
    "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import {PoolConfig} from
    "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import "@superfluid-finance/ethereum-contracts/contracts/agreements/ConstantFlowAgreementV1.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";

contract SuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    SuperfluidFrameworkDeployer.Framework internal sf;
    IERC20 internal token;
    ISuperToken internal superToken;

    constructor(SuperfluidFrameworkDeployer.Framework memory sf_, IERC20 token_, ISuperToken superToken_) {
        sf = sf_;
        token = token_;
        superToken = superToken_;
    }

    // ERC20 Functions
    function approve(address spender, uint256 amount) public {
        superToken.approve(spender, amount);
    }

    function transfer(address recipient, uint256 amount) public {
        superToken.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public {
        superToken.transferFrom(sender, recipient, amount);
    }

    // SuperToken Functions
    function upgradeSuperToken(uint256 amount) public {
        token.approve(address(superToken), amount);
        superToken.upgrade(amount);
    }

    function downgradeSuperToken(uint256 amount) public {
        superToken.downgrade(amount);
    }

    function transferAll(address recipient) public {
        superToken.transferAll(recipient);
    }

    function increaseAllowance(address spender, uint256 addedValue) public {
        superToken.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public {
        superToken.decreaseAllowance(spender, subtractedValue);
    }

    // CFA functions

    function flow(address receiver, int96 flowRate) public {
        (, int96 currentFlowRate,,) = sf.cfa.getFlow(superToken, address(this), receiver);
        if (flowRate == 0) {
            superToken.deleteFlow(address(this), receiver);
        } else if (currentFlowRate == 0) {
            superToken.createFlow(receiver, flowRate);
        } else {
            superToken.updateFlow(receiver, flowRate);
        }
    }

    function cfaLiquidate(address sender, address receiver) public {
        superToken.deleteFlow(sender, receiver);
    }

    function setFlowPermissions(
        address flowOperator,
        bool allowCreate,
        bool allowUpdate,
        bool allowDelete,
        int96 flowRateAllowance
    ) public {
        superToken.setFlowPermissions(flowOperator, allowCreate, allowUpdate, allowDelete, flowRateAllowance);
    }

    function setMaxFlowPermissions(address flowOperator) public {
        superToken.setMaxFlowPermissions(flowOperator);
    }

    function revokeFlowPermissions(address flowOperator) public {
        superToken.revokeFlowPermissions(flowOperator);
    }

    function increaseFlowRateAllowance(address flowOperator, int96 addedFlowRateAllowance) public {
        superToken.increaseFlowRateAllowance(flowOperator, addedFlowRateAllowance);
    }

    function decreaseFlowRateAllowance(address flowOperator, int96 subtractedFlowRateAllowance) public {
        superToken.decreaseFlowRateAllowance(flowOperator, subtractedFlowRateAllowance);
    }

    function increaseFlowRateAllowanceWithPermissions(
        address flowOperator,
        uint8 permissionsToAdd,
        int96 addedFlowRateAllowance
    ) public {
        superToken.increaseFlowRateAllowanceWithPermissions(flowOperator, permissionsToAdd, addedFlowRateAllowance);
    }

    function decreaseFlowRateAllowanceWithPermissions(
        address flowOperator,
        uint8 permissionsToRemove,
        int96 subtractedFlowRateAllowance
    ) public {
        superToken.decreaseFlowRateAllowanceWithPermissions(
            flowOperator, permissionsToRemove, subtractedFlowRateAllowance
        );
    }

    // GDA functions
    function createPool(address admin, PoolConfig memory config) public returns (ISuperfluidPool pool) {
        pool = superToken.createPool(admin, config);
    }

    function connectPool(ISuperfluidPool pool) public {
        superToken.connectPool(pool);
    }

    function disconnectPool(ISuperfluidPool pool) public {
        superToken.disconnectPool(pool);
    }

    function distribute(address from, ISuperfluidPool pool, uint256 requestedAmount) public {
        superToken.distribute(from, pool, requestedAmount);
    }

    function distributeFlow(address from, ISuperfluidPool pool, int96 flowRate) public {
        superToken.distributeFlow(from, pool, flowRate);
    }

    function gdaLiquidate(address from, ISuperfluidPool pool) public {
        superToken.distributeFlow(from, pool, 0);
    }

    // SuperfluidPool
    function updateMemberUnits(ISuperfluidPool pool, address member, uint128 units) public {
        pool.updateMemberUnits(member, units);
    }

    function claimAll(ISuperfluidPool pool) public {
        pool.claimAll();
    }

    function claimAll(ISuperfluidPool pool, address memberAddress) public {
        pool.claimAll(memberAddress);
    }

    // SuperfluidPool-ERC20
    function transfer(ISuperfluidPool pool, address to, uint256 amount) public {
        pool.transfer(to, amount);
    }

    function transferFrom(ISuperfluidPool pool, address from, address to, uint256 amount) public {
        pool.transferFrom(from, to, amount);
    }

    function increaseAllowance(ISuperfluidPool pool, address spender, uint256 addedValue) public {
        pool.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(ISuperfluidPool pool, address spender, uint256 subtractedValue) public {
        pool.decreaseAllowance(spender, subtractedValue);
    }

    function approve(ISuperfluidPool pool, address spender, uint256 amount) public {
        pool.approve(spender, amount);
    }
}
