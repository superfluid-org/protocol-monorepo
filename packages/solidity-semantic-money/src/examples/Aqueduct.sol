// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;


import {
    FlowRate, Unit
} from "@superfluid-finance/solidity-semantic-money/src/SemanticMoney.sol";
import {
    FlowId, ToySuperfluidToken
} from "@superfluid-finance/solidity-semantic-money/src/ref-impl/ToySuperfluidToken.sol";
import {
    ToySuperfluidPool
} from "@superfluid-finance/solidity-semantic-money/src/ref-impl/ToySuperfluidPool.sol";


/**
 * @dev Aqueduct - a zero-intermediate liquidity market maker (ZILMM)
 */
library AqueductLibrary {
    int128 internal constant FLOW_RATE_SCALING_FACTOR = 1e9;

    struct PoolSideState {
        FlowRate totalInFlowRate;
    }

    struct TraderSideState {
        Unit nUnits;
    }

    // Down scale the flow rate: minimum 1 unit unless input is 0.
    function _clip(FlowRate r) internal pure returns(int128)
    {
        if (FlowRate.unwrap(r) == 0) return 0;
        int128 rr = FlowRate.unwrap(r) / FLOW_RATE_SCALING_FACTOR;
        return rr == 0 ? int128(1) : rr;
    }

    function updateSide(PoolSideState memory poolA, FlowRate r0, FlowRate r1) internal pure
        returns (PoolSideState memory poolAu, TraderSideState memory tradeBu, FlowRate distributionFlowRate)
    {
        poolAu.totalInFlowRate = poolA.totalInFlowRate - r0 + r1;
        // TODO: assuming 100% distributed for now
        distributionFlowRate = poolAu.totalInFlowRate;

        tradeBu.nUnits = Unit.wrap(_clip(r1));
    }
}

contract Aqueduct {
    FlowId constant public SWAP_DISTRIBUTE_FLOW_ID = FlowId.wrap(0);
    FlowId constant public ADJUSTMENT_FLOW_ID = FlowId.wrap(0);

    struct Side {
        ToySuperfluidToken token;
        ToySuperfluidPool pool;
        // it is unnecessary to store everything in storage, but it's a toy model
        AqueductLibrary.PoolSideState state;
        // remainder flowrate goes to the last taker
        address remFlowReceiver;
    }

    Side internal _left;
    Side internal _right;

    function token1() external view returns (ToySuperfluidToken) { return _left.token; }
    function token2() external view returns (ToySuperfluidToken) { return _right.token; }
    function pool1() external view returns (ToySuperfluidPool) { return _left.pool; }
    function pool2() external view returns (ToySuperfluidPool) { return _right.pool; }

    constructor (ToySuperfluidToken tokenL, ToySuperfluidToken tokenR) {
        _left.token = tokenL;
        _left.pool = tokenL.createPool();
        _right.token = tokenR;
        _right.pool = tokenR.createPool();
    }

    /**
     * @dev Flow updated callback
     * @param token - token for the flow
     * @param from - flow sender
     * @param ir0 - previous (input) flow rate
     * @param ir1 - new (input) flow rate
     */
    function onFlowUpdate(ToySuperfluidToken token, address from, FlowRate ir0, FlowRate ir1) external {
        if (token == _left.token) {
            _onFlowUpdate(_left, _right, from, ir0, ir1);
        } else if (token == _right.token) {
            _onFlowUpdate(_right, _left, from, ir0, ir1);
        } else revert("Unknown token");
    }

    function _onFlowUpdate(Side storage a, Side storage b, address from, FlowRate ir0, FlowRate ir1) internal {
        AqueductLibrary.TraderSideState memory tssB;
        FlowRate drr; // distribution rate requested
        (a.state, tssB, drr) = AqueductLibrary.updateSide(a.state, ir0, ir1);
        {
            FlowRate dr0 = a.pool.getDistributionFlowRate();
            (,,FlowRate dr1) = a.token.distributeFlow(address(this), a.pool, SWAP_DISTRIBUTE_FLOW_ID, drr);
            _adjustFlowRemainder(a, from, ir1 - ir0, dr1 - dr0);
        }
        {
            // cancel existing remainder flow
            FlowRate ar0 = b.token.getFlowRate(address(this), from, ADJUSTMENT_FLOW_ID);
            FlowRate dr0 = b.pool.getDistributionFlowRate();
            b.pool.updateMember(from, tssB.nUnits);
            (,,FlowRate dr1) = b.token.distributeFlow(address(this), b.pool, SWAP_DISTRIBUTE_FLOW_ID, dr0 + ar0);
            _adjustFlowRemainder(b, from, FlowRate.wrap(0), dr1 - dr0);
        }
    }

    /**
     * @dev Helper function for adjusting flow remainder for the new receiver
     *
     * @param a - side of the pool to be adjusted,
     * @param newRemFlowReceiver - new (maybe) remainder flow receiver.
     * @param ird - input rate delta.
     * @param drd - flow distribution rate delta before/after flow distribution update.
     */
    function _adjustFlowRemainder(Side storage a, address newRemFlowReceiver,
                                  FlowRate ird, FlowRate drd) internal {
        // * Given definitions:
        //
        // 1) ird, drd defined in parameters. Additionally,
        // 2) br0: flow rate to the current remainder flow receiver.
        // 3) crd: the control flow rate delta. Control flow is flow from aqueduct to the pool itself.
        // 4) jrd: pool adjustment flow rate delta.
        // 5) ar0: current remainder flow rate to the new remainder receiver.
        // 6) ar1: new remainder flow rate to the new remainder receiver.
        //
        // * We have:
        //
        // a) when changing remainder flow receiver:
        //      ird + jrd = ar1 - ar0 - br0 + crd && ar0 == 0
        //    otherwise:
        //      ird + jrd = ar1 - br0 + crd
        //    so that net flow rate to aqueduct is always 0
        // b) crd = drd + jrd
        //    so that netflow rate to the pool is always 0
        //
        // * Then the solution to ar1 is always:
        //
        // c) ar1 = ird - drd + br0
        FlowRate br0 = a.token.getFlowRate(address(this), a.remFlowReceiver, ADJUSTMENT_FLOW_ID);
        FlowRate ar1 = ird - drd + br0;
        if (a.remFlowReceiver != newRemFlowReceiver) {
            a.token.flow(address(this), a.remFlowReceiver, ADJUSTMENT_FLOW_ID, FlowRate.wrap(0));
            a.remFlowReceiver = newRemFlowReceiver;
        }
        a.token.flow(address(this), newRemFlowReceiver, ADJUSTMENT_FLOW_ID, ar1);
    }
}
