// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {
    Time, Value, FlowRate,
    BasicParticle,
    PDPoolIndex
} from "./SemanticMoney.sol";

/**
 * @title Monadic interface for Semantic Money as abstract contract.
 *
 * Note:
 *
 * eff - Opaque context for all monadic effects. They should be used to provide the context for the getter/setters.
 *       Its naming is inspired by effect systems.
 */
abstract contract TokenMonad {
    function _getUIndex(bytes memory eff, address owner)
        virtual internal view returns (BasicParticle memory);
    function _setUIndex(bytes memory eff, address owner, BasicParticle memory p)
        virtual internal returns (bytes memory);
    function _getPDPIndex(bytes memory eff, address pool)
        virtual internal view returns (PDPoolIndex memory);
    function _setPDPIndex(bytes memory eff, address pool, PDPoolIndex memory p)
        virtual internal returns (bytes memory);
    function _getFlowRate(bytes memory, bytes32 flowHash)
        virtual internal view returns (FlowRate);
    function _setFlowInfo(bytes memory eff, bytes32 flowHash, address from, address to,
                          FlowRate newFlowRate, FlowRate flowRateDelta)
        virtual internal returns (bytes memory);
    function _getPoolAdjustmentFlowRate(bytes memory eff, address pool)
        virtual internal view returns (FlowRate);
    function _setPoolAdjustmentFlowRate(bytes memory eff, address pool, FlowRate flowRate, Time)
        virtual internal returns (bytes memory);

    function _doShift(bytes memory eff, address from, address to, Value amount)
        internal returns (bytes memory)
    {
        if (from == to) return eff; // short circuit
        BasicParticle memory a = _getUIndex(eff, from);
        BasicParticle memory b = _getUIndex(eff, to);

        (a, b) = a.shift2(b, amount);

        eff = _setUIndex(eff, from, a);
        eff = _setUIndex(eff, to, b);

        return eff;
    }

    function _doFlow(bytes memory eff,
                     address from, address to, bytes32 flowHash, FlowRate flowRate,
                     Time t)
        internal returns (bytes memory)
    {
        if (from == to) return eff; // short circuit
        FlowRate flowRateDelta = flowRate - _getFlowRate(eff, flowHash);
        BasicParticle memory a = _getUIndex(eff, from);
        BasicParticle memory b = _getUIndex(eff, to);

        (a, b) = a.shift_flow2b(b, flowRateDelta, t);

        eff = _setUIndex(eff, from, a);
        eff = _setUIndex(eff, to, b);
        eff = _setFlowInfo(eff, flowHash, from, to, flowRate, flowRateDelta);

        return eff;
    }

    function _doDistributeViaPool(bytes memory eff, address from, address pool, Value reqAmount)
        internal returns (bytes memory, Value actualAmount)
    {
        assert(from != pool);
        // a: from uidx -> b: pool uidx -> c: pool pdpidx
        // b is completely by-passed
        BasicParticle memory a = _getUIndex(eff, from);
        PDPoolIndex memory c = _getPDPIndex(eff, pool);

        (a, c, actualAmount) = a.shift2b(c, reqAmount);

        eff = _setUIndex(eff, from, a);
        eff = _setPDPIndex(eff, pool, c);

        return (eff, actualAmount);
    }

    // Note: because of no-via-ir builds and stack too deep :)
    struct DistributeFlowVars {
        FlowRate currentAdjustmentFlowRate;
        FlowRate newAdjustmentFlowRate;
        FlowRate actualFlowRateDelta;
    }
    function _doDistributeFlowViaPool(bytes memory eff,
                                      address from, address pool, bytes32 flowHash, FlowRate reqFlowRate,
                                      Time t)
        internal returns (bytes memory, FlowRate newActualFlowRate, FlowRate newDistributionFlowRate)
    {
        assert(from != pool);
        // a: from uidx -> b: pool uidx -> c: pool pdpidx
        // b handles the adjustment flow through _get/_setPoolAdjustmentFlowRate.
        BasicParticle memory a = _getUIndex(eff, from);
        BasicParticle memory b = _getUIndex(eff, pool);
        PDPoolIndex memory c = _getPDPIndex(eff, pool);
        DistributeFlowVars memory vars;
        vars.currentAdjustmentFlowRate = _getPoolAdjustmentFlowRate(eff, pool);

        {
            FlowRate oldFlowRate = _getFlowRate(eff, flowHash); // flow rate of : from -> pool
            FlowRate oldDistributionFlowRate = c.flow_rate();
            FlowRate shiftFlowRate = reqFlowRate - oldFlowRate;

            // to readjust, include the current adjustment flow rate here
            (b, c, newDistributionFlowRate) = b.shift_flow2b(c, shiftFlowRate + vars.currentAdjustmentFlowRate, t);
            assert(FlowRate.unwrap(newDistributionFlowRate) >= 0);
            newActualFlowRate = oldFlowRate
                + (newDistributionFlowRate - oldDistributionFlowRate)
                - vars.currentAdjustmentFlowRate;

            if (FlowRate.unwrap(newActualFlowRate) >= 0) {
                // previous adjustment flow is fully utilized
                vars.newAdjustmentFlowRate = FlowRate.wrap(0);
            } else {
                // previous adjustment flow still needed
                vars.newAdjustmentFlowRate = -newActualFlowRate;
                newActualFlowRate = FlowRate.wrap(0);
            }

            vars.actualFlowRateDelta = newActualFlowRate - oldFlowRate;
            (a, b) = a.shift_flow2b(b, vars.actualFlowRateDelta, t);
        }

        eff = _setUIndex(eff, from, a);
        eff = _setUIndex(eff, pool, b);
        eff = _setPDPIndex(eff, pool, c);
        eff = _setFlowInfo(eff, flowHash, from, pool, newActualFlowRate, vars.actualFlowRateDelta);
        eff = _setPoolAdjustmentFlowRate(eff, pool, vars.newAdjustmentFlowRate, t);

        return (eff, newActualFlowRate, newDistributionFlowRate);
    }
}
