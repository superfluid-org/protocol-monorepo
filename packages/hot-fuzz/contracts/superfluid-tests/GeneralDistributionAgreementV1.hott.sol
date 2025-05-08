// SPDX-License-Identifier: AGPLv3
// solhint-disable reason-string
pragma solidity >= 0.8.0;

import {SuperToken} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {ISuperfluidPool} from
    "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import {PoolConfig} from
    "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import {HotFuzzBase, SuperfluidTester} from "../HotFuzzBase.sol";

abstract contract GDAHotFuzzMixin is HotFuzzBase {
    using SuperTokenV1Library for SuperToken;

    ISuperfluidPool[] public pools;

    function getRandomPool(uint8 input) public view returns (ISuperfluidPool pool) {
        if (pools.length > 0) {
            pool = pools[input % (pools.length - 1)];
        }
    }

    function createPool(uint8 a, PoolConfig memory config) public {
        (SuperfluidTester tester) = _getOneTester(a);
        ISuperfluidPool pool = tester.createPool(address(tester), config);
        _addPool(pool);
    }

    function maybeConnectPool(bool doConnect, uint8 a, uint8 b) public {
        (SuperfluidTester tester) = _getOneTester(a);
        ISuperfluidPool pool = getRandomPool(b);
        if (doConnect) {
            tester.connectPool(pool);
        } else {
            tester.disconnectPool(pool);
        }
    }

    function distribute(uint8 a, uint8 b, uint128 requestedAmount) public {
        (SuperfluidTester tester) = _getOneTester(a);
        ISuperfluidPool pool = getRandomPool(b);

        tester.distribute(address(tester), pool, requestedAmount);
    }

    function distributeFlow(uint8 a, uint8 b, uint8 c, int96 flowRate) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);
        ISuperfluidPool pool = getRandomPool(c);

        testerA.distributeFlow(address(testerB), pool, flowRate);
    }

    /// @notice testerA liquidates a flow from testerB to pool
    /// @dev testerA can be the same as testerB
    function gdaLiquidateFlow(uint8 a, uint8 b, uint8 c) public {
        (SuperfluidTester liquidator, SuperfluidTester distributor) = _getTwoTesters(a, b);
        ISuperfluidPool pool = getRandomPool(c);

        // we first check the condition for whether a flow exists
        bool flowExists = superToken.getFlowDistributionFlowRate(address(distributor), pool) > 0;

        // then we ensure that the sender has a critical balance
        (int256 availableBalance,,,) = superToken.realtimeBalanceOfNow(address(distributor));
        bool isDistributorCritical = availableBalance < 0;

        // if both conditions are met, a liquidation should occur without fail
        bool isLiquidationValid = flowExists && isDistributorCritical;
        if (isLiquidationValid) {
            // solhint-disable-next-line no-empty-blocks
            try liquidator.gdaLiquidate(address(distributor), pool) {}
            catch {
                liquidationFails = true;
            }
        }
    }

    function updateMemberUnits(uint8 a, uint8 b, uint128 units) public {
        (SuperfluidTester tester) = _getOneTester(a);
        ISuperfluidPool pool = getRandomPool(b);

        tester.updateMemberUnits(pool, address(tester), units);
    }

    function poolTransfer(uint8 a, uint8 b, uint256 amount) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);
        ISuperfluidPool pool = getRandomPool(b);

        testerA.transfer(pool, address(testerB), amount);
    }

    function poolTransferFrom(uint8 a, uint8 b, uint8 c, uint256 amount) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);
        (SuperfluidTester tester) = _getOneTester(c);
        ISuperfluidPool pool = getRandomPool(b);

        testerA.transferFrom(pool, address(tester), address(testerB), amount);
    }

    function poolIncreaseAllowance(uint8 a, uint8 b, uint256 addedValue) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);
        ISuperfluidPool pool = getRandomPool(b);

        testerA.increaseAllowance(pool, address(testerB), addedValue);
    }

    function poolDecreaseAllowance(uint8 a, uint8 b, uint256 subtractedValue) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);
        ISuperfluidPool pool = getRandomPool(b);

        testerA.decreaseAllowance(pool, address(testerB), subtractedValue);
    }

    function poolApprove(uint8 a, uint8 b, uint256 amount) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);
        ISuperfluidPool pool = getRandomPool(b);

        testerA.approve(pool, address(testerB), amount);
    }

    function claimAll(uint8 a, uint8 b) public {
        (SuperfluidTester tester) = _getOneTester(a);
        ISuperfluidPool pool = getRandomPool(b);

        tester.claimAll(pool);
    }

    function claimAllForMember(uint8 a, uint8 b) public {
        (SuperfluidTester testerA, SuperfluidTester testerB) = _getTwoTesters(a, b);
        ISuperfluidPool pool = getRandomPool(b);

        testerA.claimAll(pool, address(testerB));
    }

    function _addPool(ISuperfluidPool pool) internal {
        pools.push(pool);
        _addAccount(address(pool));
    }
}

contract GDAHotFuzz is HotFuzzBase(10), GDAHotFuzzMixin {
    uint256 public constant NUM_POOLS = 3;

    constructor() {
        _initTesters();

        PoolConfig memory config = PoolConfig({transferabilityForUnitsOwner: true, distributionFromAnyAddress: true});

        for (uint256 i; i < NUM_POOLS; i++) {
            (SuperfluidTester tester) = _getOneTester(uint8(i));
            ISuperfluidPool pool = tester.createPool(address(tester), config);
            _addPool(pool);
        }
    }
}
