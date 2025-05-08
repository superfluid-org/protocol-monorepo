// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import {
    Value, FlowRate, Time, Unit,
    BasicParticle, PDPoolIndex, PDPoolMember, PDPoolMemberMU
} from "@superfluid-finance/solidity-semantic-money/src/SemanticMoney.sol";

contract SemanticMoneyTest is Test {

    // make the overflow errors go away for test cases
    function limitToSafeParticle(BasicParticle memory p) internal pure {
        p._settled_at = Time.wrap(Time.unwrap(p._settled_at) >> 2);
        p._settled_value = Value.wrap(Value.unwrap(p._settled_value) >> 2);
        p._flow_rate = FlowRate.wrap(FlowRate.unwrap(p._flow_rate) >> 2);
    }

    function assertEq(FlowRate a, FlowRate b, string memory e) internal pure {
        assertEq(FlowRate.unwrap(a), FlowRate.unwrap(b), e);
    }
    function assertEq(Unit a, Unit b, string memory e) internal pure {
        assertEq(Unit.unwrap(a), Unit.unwrap(b), e);
    }
    function assertEq(Value a, Value b, string memory e) internal pure {
        assertEq(Value.unwrap(a), Value.unwrap(b), e);
    }
    function assertEq(Time a, Time b, string memory e) internal pure {
        assertEq(Time.unwrap(a), Time.unwrap(b), e);
    }
    function assertEq(BasicParticle memory a, BasicParticle memory b, string memory e) internal pure {
        assertEq(a._settled_at, b._settled_at, e);
        assertEq(a._settled_value, b._settled_value, e);
        assertEq(a._flow_rate, b._flow_rate, e);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Monetary Types
    ////////////////////////////////////////////////////////////////////////////////

    /// value `mul` unit distributive law: v * (u1 + u2) = v * u1 + v * u2
    function test_value_mul_unit_distributive_law(int128 x_, Unit u1, Unit u2) external pure {
        Value x = Value.wrap(x_);
        int256 tu = int256(Unit.unwrap(u1)) + int256(Unit.unwrap(u2));
        // FIXME NB! vm.assume crashes solc/yul 0.8.19
        if (tu > type(int128).max || tu < type(int128).min) return;
        assertEq(x.mul(u1) + x.mul(u2), x.mul(u1 + u2), "e1");
    }

    /// Value `mul.div` unit is a fixed-point function
    function test_value_muldiv_unit_fixed(int128 x_, Unit u) external pure {
        if (Unit.unwrap(u) == 0) return;
        Value x = Value.wrap(x_);
        assertEq(x.div(u).mul(u), x.div(u).mul(u).div(u).mul(u), "e1");
    }

    /// flowrate `mul` unit distributive law: r * (u1 + u2) = r * u1 + r * u2
    function test_flowrate_mul_unit_distributive_law(int64 r_, int64 u1_, int64 u2_) external pure {
        // eliminate the signed integer overflow case
        if (int256(r_) * (int256(u1_) + int256(u2_)) > type(int128).max ||
            int256(r_) * (int256(u1_) + int256(u2_)) < type(int128).min) return;
        FlowRate r = FlowRate.wrap(int128(r_));
        Unit u1 = Unit.wrap(int128(u1_));
        Unit u2 = Unit.wrap(int128(u2_));
        assertEq(r.mul(u1) + r.mul(u2), r.mul(u1 + u2), "e1");
    }

    /// FlowRate `mul.div` unit is a fixed-point function
    function test_flowrate_muldiv_unit_fixed(int64 r_, int64 u_) external pure {
        if (u_ == 0) return;
        FlowRate r = FlowRate.wrap(r_);
        Unit u = Unit.wrap(u_);
        assertEq(r.div(u).mul(u), r.div(u).mul(u).div(u).mul(u), "e1");
    }

    /// flowrate and unit quotien remainder law:  (q, e) = r \ u => q * u + e = r
    function test_flowrate_quotrem_unit(FlowRate r, Unit u) external pure {
        // FIXME NB! vm.assume crashes solc/yul 0.8.19 atm, using simpler prunings
        if (Unit.unwrap(u) == 0) return; // eliminate the div by 0 case
        if (FlowRate.unwrap(r) == type(int128).min) return; // eliminate the signed integer overflow case
        (FlowRate q, FlowRate e) = r.quotrem(u);
        assertEq(q.mul(u) + e, r, "e1");
    }

    function test_operators() external pure {
        assertTrue(Time.wrap(0) == Time.wrap(0));
        assertTrue(Time.wrap(0) != Time.wrap(1));
        assertTrue(Time.wrap(0) < Time.wrap(1));
        assertFalse(Time.wrap(1) < Time.wrap(1));
        assertTrue(Time.wrap(0) <= Time.wrap(1));
        assertTrue(Time.wrap(1) <= Time.wrap(1));
        assertTrue(Time.wrap(1) > Time.wrap(0));
        assertFalse(Time.wrap(1) > Time.wrap(1));
        assertTrue(Time.wrap(1) >= Time.wrap(0));
        assertTrue(Time.wrap(1) >= Time.wrap(1));
        {
            (uint256 quot, uint256 rem) = Time.wrap(5).quotrem(Time.wrap(2));
            assertEq(quot, 2);
            assertEq(rem, 1);
        }

        assertTrue(FlowRate.wrap(0) == FlowRate.wrap(0));
        assertTrue(FlowRate.wrap(0) != FlowRate.wrap(1));
        assertTrue(FlowRate.wrap(0) < FlowRate.wrap(1));
        assertFalse(FlowRate.wrap(1) < FlowRate.wrap(1));
        assertTrue(FlowRate.wrap(0) <= FlowRate.wrap(1));
        assertTrue(FlowRate.wrap(1) <= FlowRate.wrap(1));
        assertTrue(FlowRate.wrap(1) > FlowRate.wrap(0));
        assertFalse(FlowRate.wrap(1) > FlowRate.wrap(1));
        assertTrue(FlowRate.wrap(1) >= FlowRate.wrap(0));
        assertTrue(FlowRate.wrap(1) >= FlowRate.wrap(1));
        {
            (int256 quot, int256 rem) = FlowRate.wrap(5).quotrem(FlowRate.wrap(2));
            assertEq(quot, 2);
            assertEq(rem, 1);
            (quot, rem) = FlowRate.wrap(-5).quotrem(FlowRate.wrap(2));
            assertEq(quot, -2);
            assertEq(rem, -1);
            (quot, rem) = FlowRate.wrap(5).quotrem(FlowRate.wrap(-2));
            assertEq(quot, -2);
            assertEq(rem, 1);
            (quot, rem) = FlowRate.wrap(-5).quotrem(FlowRate.wrap(-2));
            assertEq(quot, 2);
            assertEq(rem, -1);
        }

        assertTrue(Value.wrap(0) == Value.wrap(0));
        assertTrue(Value.wrap(0) != Value.wrap(1));
        assertTrue(Value.wrap(0) < Value.wrap(1));
        assertFalse(Value.wrap(1) < Value.wrap(1));
        assertTrue(Value.wrap(0) <= Value.wrap(1));
        assertTrue(Value.wrap(1) <= Value.wrap(1));
        assertTrue(Value.wrap(1) > Value.wrap(0));
        assertFalse(Value.wrap(1) > Value.wrap(1));
        assertTrue(Value.wrap(1) >= Value.wrap(0));
        assertTrue(Value.wrap(1) >= Value.wrap(1));
        {
            (int256 quot, int256 rem) = Value.wrap(5).quotrem(Value.wrap(2));
            assertEq(quot, 2);
            assertEq(rem, 1);
        }

        assertTrue(Unit.wrap(0) == Unit.wrap(0));
        assertTrue(Unit.wrap(0) != Unit.wrap(1));
        assertTrue(Unit.wrap(0) < Unit.wrap(1));
        assertFalse(Unit.wrap(1) < Unit.wrap(1));
        assertTrue(Unit.wrap(0) <= Unit.wrap(1));
        assertTrue(Unit.wrap(1) <= Unit.wrap(1));
        assertTrue(Unit.wrap(1) > Unit.wrap(0));
        assertFalse(Unit.wrap(1) > Unit.wrap(1));
        assertTrue(Unit.wrap(1) >= Unit.wrap(0));
        assertTrue(Unit.wrap(1) >= Unit.wrap(1));
        {
            (int256 quot, int256 rem) = Unit.wrap(5).quotrem(Unit.wrap(2));
            assertEq(quot, 2);
            assertEq(rem, 1);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Particle/Universal Index Properties: Monoidal Laws & Monetary Unit Laws
    ////////////////////////////////////////////////////////////////////////////////

    function test_u_monoid_identity(BasicParticle memory p1) external pure {
        BasicParticle memory id;
        assertEq(p1, p1.mappend(id), "e1");
        assertEq(p1, id.mappend(p1), "e2");
    }

    function test_u_monoid_assoc(BasicParticle memory p1, BasicParticle memory p2, BasicParticle memory p3)
        external pure
    {
        limitToSafeParticle(p1);
        limitToSafeParticle(p2);
        limitToSafeParticle(p3);
        assertEq(p1.mappend(p2).mappend(p3), p1.mappend(p2.mappend(p3)), "e2");
    }

    function test_u_settle_idempotence(BasicParticle memory p, uint16 m) external pure {
        limitToSafeParticle(p);

        Time t1 = p.settled_at() + Time.wrap(m);
        BasicParticle memory p1 = p.settle(t1);
        BasicParticle memory p2 = p1.settle(t1);
        assertEq(p1.settled_at(), t1, "e1");
        assertEq(p1, p2, "e2");
    }

    function test_u_constant_rtb(BasicParticle memory p, uint16 m1, uint16 m2, uint16 m3) external pure {
        limitToSafeParticle(p);

        Time t1 = p.settled_at() + Time.wrap(m1);
        Time t2 = t1 + Time.wrap(m2);
        Time t3 = t2 + Time.wrap(m3);
        assertEq(p.settle(t1).rtb(t3), p.rtb(t3), "e1");
        assertEq(p.settle(t2).rtb(t3), p.rtb(t3), "e2");
        assertEq(p.settle(t1).settle(t2).rtb(t3), p.rtb(t3), "e3");
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Universal Index to Universal Index 2-primitives Properties
    ////////////////////////////////////////////////////////////////////////////////

    function uu_shift2(BasicParticle memory a, BasicParticle memory b, Time /* t */, int64 v)
        internal pure returns (BasicParticle memory, BasicParticle memory){
        return a.shift2(b, Value.wrap(v));
    }
    function uu_flow2(BasicParticle memory a, BasicParticle memory b, Time t, int64 v)
        internal pure returns (BasicParticle memory, BasicParticle memory) {
        return a.flow2(b, FlowRate.wrap(v), t);
    }
    struct UUTestVars {
        BasicParticle a;
        BasicParticle b;
        Time t1;
        Time t2;
        Time t3;
        Time t4;
        Time t5;
    }
    function run_uu_test(uint16 m1, int64 x1, uint16 m2, int64 x2, uint16 m3,
                         function (BasicParticle memory, BasicParticle memory, Time, int64)
                         internal pure returns (BasicParticle memory, BasicParticle memory) op1,
                         function (BasicParticle memory, BasicParticle memory, Time, int64)
                         internal pure returns (BasicParticle memory, BasicParticle memory) op2) internal pure {
        UUTestVars memory d;
        d.t1 = Time.wrap(m1);
        d.t2 = d.t1 + Time.wrap(m2);
        d.t3 = d.t2 + Time.wrap(m3);

        (d.a, d.b) = op1(d.a, d.b, d.t1, x1);
        (d.a, d.b) = op2(d.a, d.b, d.t2, x2);
        assertEq(0, Value.unwrap(d.a.rtb(d.t3) + d.b.rtb(d.t3)));
    }
    function test_uu_ss(uint16 m1, int64 x1, uint16 m2, int64 x2, uint16 m3) external pure {
        run_uu_test(m1, x1, m2, x2, m3, uu_shift2, uu_shift2);
    }
    function test_uu_ff(uint16 m1, int64 r1, uint16 m2, int64 r2, uint16 m3) external pure {
        run_uu_test(m1, r1, m2, r2, m3, uu_flow2, uu_flow2);
    }
    function test_uu_fs(uint16 m1, int64 r1, uint16 m2, int64 x2, uint16 m3) external pure {
        run_uu_test(m1, r1, m2, x2, m3, uu_flow2, uu_shift2);
    }
    function test_uu_sf(uint16 m1, int64 x1, uint16 m2, int64 r2, uint16 m3) external pure {
        run_uu_test(m1, x1, m2, r2, m3, uu_shift2, uu_flow2);
    }
    function test_uu_flow2(uint16 m1, int64 r1, uint16 m2, int64 r2, uint16 m3) external pure {
        UUTestVars memory d;
        d.t1 = Time.wrap(m1);
        d.t2 = d.t1 + Time.wrap(m2);
        d.t3 = d.t2 + Time.wrap(m3);

        (d.a, d.b) = d.a.flow2(d.b, FlowRate.wrap(r1), d.t1);
        (d.a, d.b) = d.a.flow2(d.b, FlowRate.wrap(r2), d.t2);

        assertEq(Value.unwrap(-d.a.rtb(d.t3)), Value.unwrap(d.b.rtb(d.t3)));
        assertEq(Value.unwrap(d.b.rtb(d.t3)),
                 int256(r1) * int256(uint256(m2)) + int256(r2) * int256(uint256(m3)));
    }
    function test_uu_shift_flow2b(uint16 m1, int64 r1, uint16 m2, int64 r2, uint16 m3) external pure {
        UUTestVars memory d;
        d.t1 = Time.wrap(m1);
        d.t2 = d.t1 + Time.wrap(m2);
        d.t3 = d.t2 + Time.wrap(m3);

        (d.a, d.b) = d.a.shift_flow2b(d.b, FlowRate.wrap(r1), d.t1);
        (d.a, d.b) = d.a.shift_flow2b(d.b, FlowRate.wrap(r2), d.t2);

        assertEq(Value.unwrap(-d.a.rtb(d.t3)), Value.unwrap(d.b.rtb(d.t3)));
        assertEq(Value.unwrap(d.b.rtb(d.t3)),
                 int256(r1) * int256(uint256(m2)) + (int256(r1) + int256(r2)) * int256(uint256(m3)));
    }
    function test_uu_shift_flow2ab_equiv(int64 r1, uint16 m1, int64 r2, uint16 m2) external pure {
        Time t1 = Time.wrap(m1);
        Time t2 = Time.wrap(m1) + Time.wrap(m2);
        BasicParticle memory a0;
        BasicParticle memory b0;

        (BasicParticle memory a1a, BasicParticle memory b1a) = a0.shift_flow2a(b0, FlowRate.wrap(r1), t1);
        (BasicParticle memory a1b, BasicParticle memory b1b) = a0.shift_flow2b(b0, FlowRate.wrap(r1), t1);
        assertEq(a1a, a1b, "a1");
        assertEq(b1a, b1b, "b1");

        (BasicParticle memory a2a, BasicParticle memory b2a) = a1a.shift_flow2a(b1a, FlowRate.wrap(r2), t2);
        (BasicParticle memory a2b, BasicParticle memory b2b) = a1b.shift_flow2b(b1b, FlowRate.wrap(r2), t2);
        assertEq(a2a, a2b, "a2");
        assertEq(b2a, b2b, "b2");
    }

    // Universal Index to Proportional Distribution Pool
    function updp_shift2(BasicParticle memory a, PDPoolIndex memory b, Time /* t */, int64 v)
        internal pure returns (BasicParticle memory a2, PDPoolIndex memory b2){
        (a2, b2,) = a.shift2b(b, Value.wrap(v));
    }
    function updp_flow2(BasicParticle memory a, PDPoolIndex memory b, Time t, int64 v)
        internal pure returns (BasicParticle memory a2, PDPoolIndex memory b2) {
        (a2, b2,) = a.flow2(b, FlowRate.wrap(v), t);
    }
    struct UPDPTestVars {
        BasicParticle a;
        PDPoolIndex b;
        PDPoolMember b1;
        PDPoolMember b2;
        Time t1;
        Time t2;
        Time t3;
        Time t4;
        Time t5;
    }
    function run_updp_1m_test(// update unit
                              uint16 m1, int64 u1,
                              // op1
                              uint16 m2, int64 v2,
                              function (BasicParticle memory, PDPoolIndex memory, Time, int64)
                              internal pure returns (BasicParticle memory, PDPoolIndex memory) op1,
                              // update unit
                              uint16 m3, int64 u2,
                              // op 2
                              uint16 m4, int64 v4,
                              function (BasicParticle memory, PDPoolIndex memory, Time, int64)
                              internal pure returns (BasicParticle memory, PDPoolIndex memory) op2,
                              // final test time
                              uint16 m5) internal pure {
        UPDPTestVars memory d;
        d.t1 = Time.wrap(m1);
        d.t2 = d.t1 + Time.wrap(m2);
        d.t3 = d.t2 + Time.wrap(m3);
        d.t4 = d.t3 + Time.wrap(m4);
        d.t5 = d.t4 + Time.wrap(m5);

        (d.b, d.b1, d.a) = PDPoolMemberMU(d.b, d.b1).pool_member_update(d.a, Unit.wrap(u1), d.t1);
        assertEq(Value.unwrap(d.b1._synced_particle._settled_value), 0, "e1");
        assertEq(Unit.unwrap(d.b.total_units), u1, "e2");
        assertEq(Unit.unwrap(d.b1.owned_units), u1, "e3");

        (d.a, d.b) = op1(d.a, d.b, d.t2,v2);

        (d.b, d.b1, d.a) = PDPoolMemberMU(d.b, d.b1).pool_member_update(d.a, Unit.wrap(u2), d.t3);
        assertEq(Unit.unwrap(d.b.total_units), u2, "e4");
        assertEq(Unit.unwrap(d.b1.owned_units), u2, "e5");

        (d.a, d.b) = op2(d.a, d.b, d.t4,v4);

        assertEq(Value.unwrap(d.a.rtb(d.t5) + PDPoolMemberMU(d.b, d.b1).rtb(d.t5)), 0, "e6");
    }
    function test_updp_1m_ss(uint16 m1, int64 u1, // update unit
                             uint16 m2, int64 x2, // distribute
                             uint16 m3, int64 u2, // update unit
                             uint16 m4, int64 x4, // distribute
                             uint16 m5) external pure {
        run_updp_1m_test(m1, u1, m2, x2, updp_shift2, m3, u2, m4, x4, updp_shift2, m5);
    }
    function test_updp_1m_ff(uint16 m1, int64 u1, // update unit
                             uint16 m2, int64 r2, // distribute flow
                             uint16 m3, int64 u2, // update unit
                             uint16 m4, int64 r4, // distribute flow
                             uint16 m5) external pure {
        run_updp_1m_test(m1, u1, m2, r2, updp_flow2, m3, u2, m4, r4, updp_flow2, m5);
    }
    function test_updp_1m_sf(uint16 m1, int64 u1, // update unit
                             uint16 m2, int64 x2, // distribute
                             uint16 m3, int64 u2, // update unit
                             uint16 m4, int64 r4, // distribute flow
                             uint16 m5) external pure {
        run_updp_1m_test(m1, u1, m2, x2, updp_shift2, m3, u2, m4, r4, updp_flow2, m5);
    }
    function test_updp_1m_fs(uint16 m1, int64 u1, // update unit
                             uint16 m2, int64 r2, // distribute flow
                             uint16 m3, int64 u2, // update unit
                             uint16 m4, int64 x4, // distribute
                             uint16 m5) external pure {
        run_updp_1m_test(m1, u1, m2, r2, updp_flow2, m3, u2, m4, x4, updp_shift2, m5);
    }

    function run_updp_2m_test(// update unit
                              uint16 m1, int64 u1,
                              // op1
                              uint16 m2, int64 v2,
                              function (BasicParticle memory, PDPoolIndex memory, Time, int64)
                              internal pure returns (BasicParticle memory, PDPoolIndex memory) op1,
                              // update unit
                              uint16 m3, int64 u2,
                              // op 2
                              uint16 m4, int64 v4,
                              function (BasicParticle memory, PDPoolIndex memory, Time, int64)
                              internal pure returns (BasicParticle memory, PDPoolIndex memory) op2,
                              // final test time
                              uint16 m5) internal pure {
        UPDPTestVars memory d;
        d.t1 = Time.wrap(m1);
        d.t2 = d.t1 + Time.wrap(m2);
        d.t3 = d.t2 + Time.wrap(m3);
        d.t4 = d.t3 + Time.wrap(m4);
        d.t5 = d.t4 + Time.wrap(m5);

        (d.b, d.b1, d.a) = PDPoolMemberMU(d.b, d.b1).pool_member_update(d.a, Unit.wrap(u1), d.t1);
        assertEq(Value.unwrap(d.b1._synced_particle._settled_value), 0, "e1");
        assertEq(Unit.unwrap(d.b.total_units), u1, "e2");
        assertEq(Unit.unwrap(d.b1.owned_units), u1, "e3");

        (d.a, d.b) = op1(d.a, d.b, d.t2, v2);

        (d.b, d.b2, d.a) = PDPoolMemberMU(d.b, d.b2).pool_member_update(d.a, Unit.wrap(u2), d.t3);
        assertEq(Unit.unwrap(d.b.total_units), int256(u1) + int256(u2), "e4");
        assertEq(Unit.unwrap(d.b2.owned_units), u2, "e5");

        (d.a, d.b) = op2(d.a, d.b, d.t4, v4);

        assertEq(Value.unwrap(d.a.rtb(d.t5)
                              + PDPoolMemberMU(d.b, d.b1).rtb(d.t5)
                              + PDPoolMemberMU(d.b, d.b2).rtb(d.t5)), 0, "e5");
    }
    function test_updp_2m_ss(uint16 m1, int64 u1, // update unit
                             uint16 m2, int64 x2, // distribute
                             uint16 m3, int64 u2, // update unit
                             uint16 m4, int64 x4, // distribute
                             uint16 m5) external pure {
        run_updp_2m_test(m1, u1, m2, x2, updp_shift2, m3, u2, m4, x4, updp_shift2, m5);
    }
    function test_updp_2m_ff(uint16 m1, int64 u1, // update unit
                             uint16 m2, int64 r2, // distribute flow
                             uint16 m3, int64 u2, // update unit
                             uint16 m4, int64 r4, // distribute flow
                             uint16 m5) external pure {
        run_updp_2m_test(m1, u1, m2, r2, updp_flow2, m3, u2, m4, r4, updp_flow2, m5);
    }
    function test_updp_2m_sf(uint16 m1, int64 u1, // update unit
                             uint16 m2, int64 x2, // distribute
                             uint16 m3, int64 u2, // update unit
                             uint16 m4, int64 r4, // distribute flow
                             uint16 m5) external pure {
        run_updp_2m_test(m1, u1, m2, x2, updp_shift2, m3, u2, m4, r4, updp_flow2, m5);
    }
    function test_updp_2m_fs(uint16 m1, int64 u1, // update unit
                             uint16 m2, int64 r2, // distribute flow
                             uint16 m3, int64 u2, // update unit
                             uint16 m4, int64 x4, // distribute
                             uint16 m5) external pure {
        run_updp_2m_test(m1, u1, m2, r2, updp_flow2, m3, u2, m4, x4, updp_shift2, m5);
    }
    function test_updp_flow2(uint16 m1, int64 r1, uint16 m2, int64 r2, uint16 m3) external pure {
        UPDPTestVars memory d;
        d.t1 = Time.wrap(m1);
        d.t2 = d.t1 + Time.wrap(m2);
        d.t3 = d.t2 + Time.wrap(m3);

        (d.b, d.b1, d.a) = PDPoolMemberMU(d.b, d.b1).pool_member_update(d.a, Unit.wrap(1), d.t1);
        (d.a, d.b,) = d.a.flow2(d.b, FlowRate.wrap(r1), d.t1);
        (d.a, d.b,) = d.a.flow2(d.b, FlowRate.wrap(r2), d.t2);

        assertEq(Value.unwrap(PDPoolMemberMU(d.b, d.b1).rtb(d.t3)),
                 int256(r1) * int256(uint256(m2)) + int256(r2) * int256(uint256(m3)));
    }
}
