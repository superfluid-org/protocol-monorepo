// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {
    Time, Value, FlowRate,
    BasicParticle,
    PDPoolIndex
} from "./SemanticMoney.sol";

/*******************************************************************************
 * Alternative monadic interface for semantic money using library.
 *
 * Notes:
 *
 * - This is a much more ergonomic interface favoring chaining of functions.
 * - However certora tooling does not support function pointers well, and it is
 *   then unfortunately not used in the production code.
 ******************************************************************************/

/**
 * @title Struct for the monadic interface of semantic money.
 */
struct TokenEff {
    // Function pointers used by effectful token functions

    function (TokenEff memory, address /*owner*/) internal view returns (BasicParticle memory)
        getUIndex;
    function (TokenEff memory, address /*owner*/, BasicParticle memory) internal returns (TokenEff memory)
        setUIndex;

    function (TokenEff memory, address /*pool*/) internal view returns (PDPoolIndex memory)
        getPDPIndex;
    function (TokenEff memory, address /*pool*/, PDPoolIndex memory) internal returns (TokenEff memory)
        setPDPIndex;

    function (TokenEff memory, bytes32 /*flowHash*/) internal view returns (FlowRate)
        getFlowRate;
    function (TokenEff memory, bytes32 /*flowHash*/, address /*from*/, address /*to*/, FlowRate /*flowRate*/)
        internal returns (TokenEff memory)
        setFlowInfo;

    /*
     * @dev Opaque context for all monadic effects. They should be used to provide the context for the getter/setters.
     *      Its naming is inspired by the effect systems.
     */
    bytes ctx;
}

/**
 * @title Library for the monadic interface of semantic money.
 */
library TokenEffLib {
    // these are lightweight library wrappers for chaining function calls using TokenEff

    function getUIndex(TokenEff memory eff, address owner) internal view returns (BasicParticle memory) {
        return eff.getUIndex(eff, owner);
    }
    function setUIndex(TokenEff memory eff, address owner, BasicParticle memory p) internal returns (TokenEff memory) {
        return eff.setUIndex(eff, owner, p);
    }
    function getPDPIndex(TokenEff memory eff, address pool) internal view returns (PDPoolIndex memory) {
        return eff.getPDPIndex(eff, pool);
    }
    function setPDPIndex(TokenEff memory eff, address pool, PDPoolIndex memory p) internal returns (TokenEff memory) {
        return eff.setPDPIndex(eff, pool, p);
    }
    function getFlowRate(TokenEff memory eff, bytes32 flowHash) internal view returns (FlowRate) {
        return eff.getFlowRate(eff, flowHash);
    }
    function setFlowInfo(TokenEff memory eff, bytes32 flowHash, address from, address to, FlowRate flowRate)
        internal returns (TokenEff memory)
    {
        return eff.setFlowInfo(eff, flowHash, from, to, flowRate);
    }

    // these are the actual effectful functions

    function shift(TokenEff memory eff, address from, address to, Value amount)
        internal returns (TokenEff memory)
    {
        // NOTE: using mappend so that it works when from == to, why not
        BasicParticle memory mempty;
        (BasicParticle memory a, BasicParticle memory b) = mempty.shift2(mempty, amount);
        return eff.setUIndex(from, eff.getUIndex(from).mappend(a))
            .setUIndex(to, eff.getUIndex(to).mappend(b));
    }

    function flow(TokenEff memory eff, address from, address to, bytes32 flowHash, FlowRate flowRate, Time t)
        internal returns (TokenEff memory)
    {
        FlowRate flowRateDelta = flowRate - eff.getFlowRate(flowHash);
        BasicParticle memory a = eff.getUIndex(from);
        BasicParticle memory b = eff.getUIndex(to);
        (a, b) = a.shift_flow2b(b, flowRateDelta, t);
        return eff.setUIndex(from, a)
            .setUIndex(to, b)
            .setFlowInfo(eff, flowHash, from, to, flowRate);
    }

    function distribute(TokenEff memory eff, address from, address to, Value reqAmount)
        internal returns (TokenEff memory, Value actualAmount)
    {
        BasicParticle memory a = eff.getUIndex(from);
        PDPoolIndex memory pdpIndex = eff.getPDPIndex(to);
        (a, pdpIndex, actualAmount) = a.shift2b(pdpIndex, reqAmount);
        return (eff.setUIndex(from, a)
                .setPDPIndex(to, pdpIndex)
                , actualAmount);
    }

    function distributeFlow(TokenEff memory eff,
                            address from, address to, bytes32 flowHash, FlowRate reqFlowRate, Time t)
        internal returns (TokenEff memory, FlowRate actualFlowRate)
    {
        BasicParticle memory a = eff.getUIndex(from);
        PDPoolIndex memory pdpIndex = eff.getPDPIndex(to);
        FlowRate flowRateDelta = reqFlowRate - eff.getFlowRate(flowHash);
        (a, pdpIndex, actualFlowRate) = a.shift_flow2b(pdpIndex, flowRateDelta, t);
        return (eff.setUIndex(from, a)
                .setPDPIndex(to, pdpIndex)
                .setFlowInfo(flowHash, from, to, actualFlowRate)
                , actualFlowRate);
    }
}

using TokenEffLib for TokenEff global;
