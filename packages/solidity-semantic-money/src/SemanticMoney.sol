// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/*******************************************************************************
 * On Coding Style: Functional Programming In Solidity
 *
 * This library is a translation of the Haskell Specification of Semantic Money.
 *
 * All functions are pure functions, more so than the "pure" solidity function
 * in that memory input data are always cloned. This makes true referential
 * transparency for all functions defined here.
 *
 * To visually inform the library users about this paradigm, the coding style
 * is deliberately chosen to go against the commonly recommended solhint sets.
 * Namely:
 *
 * - All library and "free range" function names are in snake_cases.
 * - All struct variables are in snake_cases.
 * - All types are in capitalized CamelCases.
 * - Comments are scarce, and written only for solidity specifics. This is to
 *   minimize regurgitation of the facts and keep original the original
 *   information where it belongs to. The clarity of the semantics and grunular
 *   of the API should compensate for that controversial take.
 */
// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase

////////////////////////////////////////////////////////////////////////////////
// Monetary Types and Their Helpers
////////////////////////////////////////////////////////////////////////////////

/********************************************************************************
 * About Fix-point Arithmetic
 *
 * There are two types of integral mul/div used in the system:
 *
 *  - FlowRate `mul`|`div` Time
 *  - Value `mul`|`div` Unit
 *
 * There are two major reasons that there is no built-in fixed-point arithmetic
 * support in this library:
 *
 * 1. To avoid any hardcoded decimal assumptions for the types at all cost. This
 *    means until there is generics for type-level decimal support in solidity,
 *    we are out of luck.
 * 2. The library requires high fidelity arithmetic to adhere strictly to the
 *    law of conservation of values. Such arithmetic would require:
 *
 *    - distributive laws for multiplications
 *    - mul.div is a fixed-point function
 *    - quot remainder law
 *
 *    Fixed-point arithmetic does not satisfy these laws.
 *
 * Generally speaking, this is the recommended configurations for the decimals
 * that works with this library:
 *
 * - Time, 0 decimals
 * - Value, 18 decimals
 * - Unit, 0 decimals
 * - FlowRate, 18 decimals (in-sync with Value)
 *
 */

/**
 * @title Absolute time value in seconds represented by uint32 unix timestamp.
 * @dev - This should represents absolute values, e.g. block timestamps.
 */
type Time is uint32;
function mt_t_eq(Time a, Time b) pure returns (bool) { return Time.unwrap(a) == Time.unwrap(b); }
function mt_t_neq(Time a, Time b) pure returns (bool) { return Time.unwrap(a) != Time.unwrap(b); }
function mt_t_le(Time a, Time b) pure returns (bool) { return Time.unwrap(a) < Time.unwrap(b); }
function mt_t_lte(Time a, Time b) pure returns (bool) { return Time.unwrap(a) <= Time.unwrap(b); }
function mt_t_gt(Time a, Time b) pure returns (bool) { return Time.unwrap(a) > Time.unwrap(b); }
function mt_t_gte(Time a, Time b) pure returns (bool) { return Time.unwrap(a) >= Time.unwrap(b); }
function mt_t_add_t(Time a, Time b) pure returns (Time) { return Time.wrap(Time.unwrap(a) + Time.unwrap(b)); }
function mt_t_sub_t(Time a, Time b) pure returns (Time) { return Time.wrap(Time.unwrap(a) - Time.unwrap(b)); }
using { mt_t_eq as ==, mt_t_neq as !=, mt_t_le as <, mt_t_lte as <=, mt_t_gt as >, mt_t_gte as >=,
        mt_t_add_t as +, mt_t_sub_t as - } for Time global;

/**
 * @title Unit value of monetary value represented with 256bits of signed integer.
 */
type Value is int256;
function mt_v_eq(Value a, Value b) pure returns (bool) { return Value.unwrap(a) == Value.unwrap(b); }
function mt_v_neq(Value a, Value b) pure returns (bool) { return Value.unwrap(a) != Value.unwrap(b); }
function mt_v_le(Value a, Value b) pure returns (bool) { return Value.unwrap(a) < Value.unwrap(b); }
function mt_v_lte(Value a, Value b) pure returns (bool) { return Value.unwrap(a) <= Value.unwrap(b); }
function mt_v_gt(Value a, Value b) pure returns (bool) { return Value.unwrap(a) > Value.unwrap(b); }
function mt_v_gte(Value a, Value b) pure returns (bool) { return Value.unwrap(a) >= Value.unwrap(b); }
function mt_v_add_v(Value a, Value b) pure returns (Value) { return Value.wrap(Value.unwrap(a) + Value.unwrap(b)); }
function mt_v_sub_v(Value a, Value b) pure returns (Value) { return Value.wrap(Value.unwrap(a) - Value.unwrap(b)); }
function mt_v_inv(Value a) pure returns (Value) { return Value.wrap(-Value.unwrap(a)); }
using { mt_v_eq as ==, mt_v_neq as !=, mt_v_le as <, mt_v_lte as <=, mt_v_gt as >, mt_v_gte as >=,
        mt_v_add_v as +, mt_v_sub_v as -, mt_v_inv as - } for Value global;

/**
 * @title Number of units represented with half the size of `Value`.
 */
type Unit is int128;
function mt_u_eq(Unit a, Unit b) pure returns (bool) { return Unit.unwrap(a) == Unit.unwrap(b); }
function mt_u_neq(Unit a, Unit b) pure returns (bool) { return Unit.unwrap(a) != Unit.unwrap(b); }
function mt_u_le(Unit a, Unit b) pure returns (bool) { return Unit.unwrap(a) < Unit.unwrap(b); }
function mt_u_lte(Unit a, Unit b) pure returns (bool) { return Unit.unwrap(a) <= Unit.unwrap(b); }
function mt_u_gt(Unit a, Unit b) pure returns (bool) { return Unit.unwrap(a) > Unit.unwrap(b); }
function mt_u_gte(Unit a, Unit b) pure returns (bool) { return Unit.unwrap(a) >= Unit.unwrap(b); }
function mt_u_add_u(Unit a, Unit b) pure returns (Unit) { return Unit.wrap(Unit.unwrap(a) + Unit.unwrap(b)); }
function mt_u_sub_u(Unit a, Unit b) pure returns (Unit) { return Unit.wrap(Unit.unwrap(a) - Unit.unwrap(b)); }
function mt_u_inv(Unit a) pure returns (Unit) { return Unit.wrap(-Unit.unwrap(a)); }
using { mt_u_eq as ==, mt_u_neq as !=, mt_u_le as <, mt_u_lte as <=, mt_u_gt as >, mt_u_gte as >=,
        mt_u_add_u as +, mt_u_sub_u as -, mt_u_inv as - } for Unit global;

/**
 * @title FlowRate value represented with half the size of `Value`.
 */
type FlowRate is int128;
function mt_r_eq(FlowRate a, FlowRate b) pure returns (bool) { return FlowRate.unwrap(a) == FlowRate.unwrap(b); }
function mt_r_neq(FlowRate a, FlowRate b) pure returns (bool) { return FlowRate.unwrap(a) != FlowRate.unwrap(b); }
function mt_r_le(FlowRate a, FlowRate b) pure returns (bool) { return FlowRate.unwrap(a) < FlowRate.unwrap(b); }
function mt_r_lte(FlowRate a, FlowRate b) pure returns (bool) { return FlowRate.unwrap(a) <= FlowRate.unwrap(b); }
function mt_r_gt(FlowRate a, FlowRate b) pure returns (bool) { return FlowRate.unwrap(a) > FlowRate.unwrap(b); }
function mt_r_gte(FlowRate a, FlowRate b) pure returns (bool) { return FlowRate.unwrap(a) >= FlowRate.unwrap(b); }
function mt_r_add_r(FlowRate a, FlowRate b) pure returns (FlowRate) {
    return FlowRate.wrap(FlowRate.unwrap(a) + FlowRate.unwrap(b));
}
function mt_r_sub_r(FlowRate a, FlowRate b) pure returns (FlowRate) {
    return FlowRate.wrap(FlowRate.unwrap(a) - FlowRate.unwrap(b));
}
function mt_r_inv(FlowRate a) pure returns (FlowRate) { return FlowRate.wrap(-FlowRate.unwrap(a)); }
using { mt_r_eq as ==, mt_r_neq as !=, mt_r_le as <, mt_r_lte as <=, mt_r_gt as >, mt_r_gte as >=,
        mt_r_add_r as +, mt_r_sub_r as -, mt_r_inv as - } for FlowRate global;

/**
 * @dev Additional helper functions for the monetary types
 *
 * Note that due to solidity current limitations, operators for mixed user defined value types
 * are not supported, hence the need of this library.
 * Read more at: https://github.com/ethereum/solidity/issues/11969#issuecomment-1448445474
 */
library AdditionalMonetaryTypeHelpers {
    // Additional Time operators
    //
    function quotrem(Time a, Time b) internal pure returns (uint256 quot, uint256 rem) {
        quot = Time.unwrap(a) / Time.unwrap(b);
        rem = Time.unwrap(a) - quot * Time.unwrap(b);
    }

    // Additional Value operators
    //
    function quotrem(Value a, Value b) internal pure returns (int256 quot, int256 rem) {
        quot = Value.unwrap(a) / Value.unwrap(b);
        rem = Value.unwrap(a) - quot * Value.unwrap(b);
    }
    function mul(Value a, Unit b) internal pure returns (Value) {
        return Value.wrap(Value.unwrap(a) * Unit.unwrap(b));
    }
    function div(Value a, Unit b) internal pure returns (Value) {
        return Value.wrap(Value.unwrap(a) / Unit.unwrap(b));
    }

    // Additional FlowRate operators
    //
    function quotrem(FlowRate a, FlowRate b) internal pure returns (int256 quot, int256 rem) {
        quot = FlowRate.unwrap(a) / FlowRate.unwrap(b);
        rem = FlowRate.unwrap(a) - quot * FlowRate.unwrap(b);
    }
    function mul(FlowRate r, Time t) internal pure returns (Value) {
        return Value.wrap(FlowRate.unwrap(r) * int256(uint256(Time.unwrap(t))));
    }
    function mul(FlowRate r, Unit u) internal pure returns (FlowRate) {
        return FlowRate.wrap(FlowRate.unwrap(r) * Unit.unwrap(u));
    }
    function div(FlowRate a, Unit b) internal pure returns (FlowRate) {
        return FlowRate.wrap(FlowRate.unwrap(a) / Unit.unwrap(b));
    }
    function quotrem(FlowRate r, Unit u) internal pure returns (FlowRate nr, FlowRate er) {
        // quotient and remainder (error term), without using the '%'/modulo operator
        nr = r.div(u);
        er = r - nr.mul(u);
    }
    function mul_quotrem(FlowRate r, Unit u1, Unit u2) internal pure returns (FlowRate nr, FlowRate er) {
        return r.mul(u1).quotrem(u2);
    }

    // Additional Unit operators
    //
    function quotrem(Unit a, Unit b) internal pure returns (int256 quot, int256 rem) {
        quot = Unit.unwrap(a) / Unit.unwrap(b);
        rem = Unit.unwrap(a) - quot * Unit.unwrap(b);
    }
}
using AdditionalMonetaryTypeHelpers for Time global;
using AdditionalMonetaryTypeHelpers for Value global;
using AdditionalMonetaryTypeHelpers for FlowRate global;
using AdditionalMonetaryTypeHelpers for Unit global;

////////////////////////////////////////////////////////////////////////////////
// Basic particle
////////////////////////////////////////////////////////////////////////////////
/**
 * @title Basic particle: the building block for payment primitives.
 */
struct BasicParticle {
    Time     _settled_at;
    FlowRate _flow_rate;
    Value    _settled_value;
}

////////////////////////////////////////////////////////////////////////////////
// Proportional Distribution Pool Data Structures.
//
// Such pool has one index and many members.
////////////////////////////////////////////////////////////////////////////////
/**
 * @dev Proportional distribution pool index data.
 */
struct PDPoolIndex {
    Unit          total_units;
    // The value here are usually measured per unit
    BasicParticle _wrapped_particle;
}

/**
 * @dev Proportional distribution pool member data.
 */
struct PDPoolMember {
    Unit          owned_units;
    Value         _settled_value;
    // It is a copy of the wrapped_particle of the index at the time an operation is performed.
    BasicParticle _synced_particle;
}

/**
 * @dev Proportional distribution pool "monetary unit" for a member.
 */
struct PDPoolMemberMU {
    PDPoolIndex  i;
    PDPoolMember m;
}

/**
 * @dev Semantic Money Library: providing generalized payment primitives.
 *
 * Notes:
 *
 * - Basic payment 2-primitives include shift2 and flow2.
 * - As its name suggesting, 2-primitives work over two parties, each party is represented by an "index".
 * - A universal index is BasicParticle plus being a Monoid. It is universal in the sense that every monetary
 * unit should have one and only one such index.
 * - Proportional distribution pool has one index per pool.
 * - This solidity library provides 2-primitives for `UniversalIndex-to-UniversalIndex` and
 *   `UniversalIndex-to-ProportionalDistributionPoolIndex`.
 */
library SemanticMoney {
    //
    // Basic Particle Operations
    //

    /// Pure data clone function.
    function clone(BasicParticle memory a) internal pure returns (BasicParticle memory b) {
        // TODO memcpy
        b._settled_at = a._settled_at;
        b._flow_rate = a._flow_rate;
        b._settled_value = a._settled_value;
    }

    function settled_at(BasicParticle memory a) internal pure returns (Time) {
        return a._settled_at;
    }

    /// Monetary unit settle function for basic particle/universal index.
    function settle(BasicParticle memory a, Time t) internal pure returns (BasicParticle memory b) {
        b = a.clone();
        b._settled_value = rtb(a, t);
        b._settled_at = t;
    }

    function flow_rate(BasicParticle memory a) internal pure returns (FlowRate) {
        return a._flow_rate;
    }

    /// Monetary unit rtb function for basic particle/universal index.
    function rtb(BasicParticle memory a, Time t) internal pure returns (Value v) {
        return a._flow_rate.mul(t - a._settled_at) + a._settled_value;
    }

    function shift1(BasicParticle memory a, Value x) internal pure returns (BasicParticle memory b) {
        b = a.clone();
        b._settled_value = b._settled_value + x;
    }

    function flow1(BasicParticle memory a, FlowRate r) internal pure returns (BasicParticle memory b) {
        b = a.clone();
        b._flow_rate = r;
    }

    //
    // Universal Index Additional Operations
    //

    // Note: the identity element is trivial, the default BasicParticle value will do.

    /// Monoid binary operator for basic particle/universal index.
    function mappend(BasicParticle memory a, BasicParticle memory b)
        internal pure returns (BasicParticle memory c)
    {
        // Note that the original spec abides the monoid laws even when time value is negative.
        Time t = Time.unwrap(a._settled_at) > Time.unwrap(b._settled_at) ? a._settled_at : b._settled_at;
        BasicParticle memory a1 = a.settle(t);
        BasicParticle memory b1 = b.settle(t);
        c._settled_at = t;
        c._settled_value = a1._settled_value + b1._settled_value;
        c._flow_rate = a1._flow_rate + b1._flow_rate;
    }

    //
    // Proportional Distribution Pool Index Operations
    //

    /// Pure data clone function.
    function clone(PDPoolIndex memory a) internal pure
        returns (PDPoolIndex memory b)
    {
        b.total_units = a.total_units;
        b._wrapped_particle = a._wrapped_particle.clone();
    }

    function settled_at(PDPoolIndex memory a) internal pure returns (Time) {
        return a._wrapped_particle.settled_at();
    }

    /// Monetary unit settle function for pool index.
    function settle(PDPoolIndex memory a, Time t) internal pure
        returns (PDPoolIndex memory m)
    {
        m = a.clone();
        m._wrapped_particle = m._wrapped_particle.settle(t);
    }

    function flow_rate(PDPoolIndex memory a) internal pure returns (FlowRate) {
        return a._wrapped_particle._flow_rate.mul(a.total_units);
    }

    function flow_rate_per_unit(PDPoolIndex memory a) internal pure returns (FlowRate) {
        return a._wrapped_particle.flow_rate();
    }

    function shift1(PDPoolIndex memory a, Value x) internal pure
        returns (PDPoolIndex memory m, Value x1)
    {
        m = a.clone();
        if (Unit.unwrap(a.total_units) != 0) {
            x1 = x.div(a.total_units).mul(a.total_units);
            m._wrapped_particle = a._wrapped_particle.shift1(x1.div(a.total_units));
        }
    }

    function flow1(PDPoolIndex memory a, FlowRate r) internal pure
        returns (PDPoolIndex memory m, FlowRate r1)
    {
        m = a.clone();
        if (Unit.unwrap(a.total_units) != 0) {
            r1 = r.div(a.total_units).mul(a.total_units);
            m._wrapped_particle = m._wrapped_particle.flow1(r1.div(a.total_units));
        }
    }

    //
    // Proportional Distribution Pool Member Operations
    //

    /// Pure data clone function.
    function clone(PDPoolMember memory a) internal pure
        returns (PDPoolMember memory b)
    {
        b.owned_units = a.owned_units;
        b._settled_value = a._settled_value;
        b._synced_particle = a._synced_particle.clone();
    }

    /// Monetary unit settle function for pool member.
    function settle(PDPoolMemberMU memory a, Time t) internal pure
        returns (PDPoolMemberMU memory b)
    {
        b.i = a.i.settle(t);
        b.m = a.m.clone();
        b.m._settled_value = a.rtb(t);
        b.m._synced_particle = b.i._wrapped_particle;
    }

    /// Monetary unit rtb function for pool member.
    function rtb(PDPoolMemberMU memory a, Time t) internal pure
        returns (Value v)
    {
        return a.m._settled_value +
            (a.i._wrapped_particle.rtb(t)
             - a.m._synced_particle.rtb(a.m._synced_particle.settled_at())
            ).mul(a.m.owned_units);
    }

    /// Update the unit amount of the member of the pool
    function pool_member_update(PDPoolMemberMU memory b1, BasicParticle memory a, Unit u, Time t) internal pure
        returns (PDPoolIndex memory p, PDPoolMember memory p1, BasicParticle memory b)
    {
        Unit oldTotalUnit = b1.i.total_units;
        Unit newTotalUnit = oldTotalUnit + u - b1.m.owned_units;
        PDPoolMemberMU memory b1s = b1.settle(t);

        // align "a" because of the change of total units of the pool
        FlowRate nr = b1s.i._wrapped_particle._flow_rate;
        FlowRate er;
        if (Unit.unwrap(newTotalUnit) != 0) {
            (nr, er) = nr.mul_quotrem(oldTotalUnit, newTotalUnit);
            er = er;
        } else {
            er = nr.mul(oldTotalUnit);
            nr = FlowRate.wrap(0);
        }
        b1s.i._wrapped_particle = b1s.i._wrapped_particle.flow1(nr);
        b1s.i.total_units = newTotalUnit;
        b = a.settle(t).flow1(a._flow_rate + er);

        p = b1s.i;
        p1 = b1s.m;
        p1.owned_units = u;
        p1._synced_particle = b1s.i._wrapped_particle.clone();
    }

    //
    // Instances of 2-primitives:
    //
    // Applying 2-primitives:
    //
    //   1) shift2
    //   2) flow2 (and its related: shift_flow2)
    //
    // over:
    //
    //   a) Universal Index to Universal Index
    //   b) Universal Index to Proportional Distribution Index
    //
    // totals FOUR general payment primitives.
    //
    // NB! Some code will look very similar, since without generic programming (or some form of parametric polymorphism)
    // in solidity the code duplications is inevitable.

    // the identity implementations for shift2a & shift2b
    function shift2(BasicParticle memory a, BasicParticle memory b, Value x) internal pure
        returns (BasicParticle memory m, BasicParticle memory n)
    {
        m = a.shift1(-x);
        n = b.shift1(x);
    }

    function flow2(BasicParticle memory a, BasicParticle memory b, FlowRate r, Time t) internal pure
        returns (BasicParticle memory m, BasicParticle memory n)
    {
        m = a.settle(t).flow1(-r);
        n = b.settle(t).flow1(r);
    }

    function shift_flow2b(BasicParticle memory a, BasicParticle memory b, FlowRate dr, Time t) internal pure
        returns (BasicParticle memory m, BasicParticle memory n)
    {
        BasicParticle memory mempty;
        BasicParticle memory a1;
        BasicParticle memory a2;
        FlowRate r = b.flow_rate();
        (a1,  ) = mempty.flow2(b, -r, t);
        (a2, n) = mempty.flow2(b, r + dr,  t);
        m = a.mappend(a1).mappend(a2);
    }

    // Note: This is functionally identity to shift_flow2b for (BasicParticle, BasicParticle).
    //       This is a included to keep fidelity with the semantic money specification.
    function shift_flow2a(BasicParticle memory a, BasicParticle memory b, FlowRate dr, Time t) internal pure
        returns (BasicParticle memory m, BasicParticle memory n)
    {
        BasicParticle memory mempty;
        BasicParticle memory b1;
        BasicParticle memory b2;
        FlowRate r = a.flow_rate();
        ( , b1) = a.flow2(mempty, r, t);
        (m, b2) = a.flow2(mempty, -r + dr, t);
        n = b.mappend(b1).mappend(b2);
    }

    function shift2b(BasicParticle memory a, PDPoolIndex memory b, Value x) internal pure
        returns (BasicParticle memory m, PDPoolIndex memory n, Value x1)
    {
        (n, x1) = b.shift1(x);
        m = a.shift1(-x1);
    }

    function flow2(BasicParticle memory a, PDPoolIndex memory b, FlowRate r, Time t) internal pure
        returns (BasicParticle memory m, PDPoolIndex memory n, FlowRate r1)
    {
        (n, r1) = b.settle(t).flow1(r);
        m = a.settle(t).flow1(-r1);
    }

    function shift_flow2b(BasicParticle memory a, PDPoolIndex memory b, FlowRate dr, Time t) internal pure
        returns (BasicParticle memory m, PDPoolIndex memory n, FlowRate r1)
    {
        BasicParticle memory mempty;
        BasicParticle memory a1;
        BasicParticle memory a2;
        FlowRate r = b.flow_rate();
        (a1,  ,   ) = mempty.flow2(b, -r, t);
        (a2, n, r1) = mempty.flow2(b, r + dr,  t);
        m = a.mappend(a1).mappend(a2);
    }
}
using SemanticMoney for BasicParticle global;
using SemanticMoney for PDPoolIndex global;
using SemanticMoney for PDPoolMember global;
using SemanticMoney for PDPoolMemberMU global;
