// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "@superfluid-finance/solidity-semantic-money/src/SemanticMoney.sol";
import { GeneralDistributionAgreementV1 } from "../../../contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol";
import {
    poolIndexDataToWrappedParticle,
    poolIndexDataToPDPoolIndex,
    SuperfluidPool
} from "../../../contracts/agreements/gdav1/SuperfluidPool.sol";

/// @title SuperfluidPool Property Tests
/// @author Superfluid
/// @notice This is a contract that runs property tests for the SuperfluidPool
/// It involves testing the pure functions of the SuperfluidPool to ensure that we get
/// the expected output for a range of inputs.
contract SuperfluidPoolProperties is SuperfluidPool, Test {
    constructor() SuperfluidPool(GeneralDistributionAgreementV1(address(0))) { }

    function _helperAssertWrappedParticle(PoolIndexData memory poolIndexData, BasicParticle memory particle)
        internal pure
    {
        assertEq(
            FlowRate.unwrap(particle.flow_rate()),
            int128(poolIndexData.wrappedFlowRate),
            "SuperfluidPool.prop (PoolIndex): flowRate not equal"
        );
        assertEq(
            Time.unwrap(particle.settled_at()),
            poolIndexData.wrappedSettledAt,
            "SuperfluidPool.prop (PoolIndex): settledAt not equal"
        );
        assertEq(
            Value.unwrap(particle._settled_value),
            poolIndexData.wrappedSettledValue,
            "SuperfluidPool.prop (PoolIndex): settledValue not equal"
        );
    }

    function _helperAssertWrappedParticle(MemberData memory memberData, BasicParticle memory particle) internal pure {
        assertEq(
            FlowRate.unwrap(particle.flow_rate()),
            int128(memberData.syncedFlowRate),
            "SuperfluidPool.prop (BasicParticle): flowRate not equal"
        );
        assertEq(
            Time.unwrap(particle.settled_at()),
            memberData.syncedSettledAt,
            "SuperfluidPool.prop (BasicParticle): settledAt not equal"
        );
        assertEq(
            Value.unwrap(particle._settled_value),
            memberData.syncedSettledValue,
            "SuperfluidPool.prop (BasicParticle): settledValue not equal"
        );
    }

    function testPoolIndexDataToWrappedParticle(PoolIndexData memory data) public pure {
        BasicParticle memory wrappedParticle = poolIndexDataToWrappedParticle(data);
        _helperAssertWrappedParticle(data, wrappedParticle);
    }

    function testPoolIndexDataToPDPoolIndex(PoolIndexData memory data) public pure {
        vm.assume(data.totalUnits < uint128(type(int128).max));

        PDPoolIndex memory pdPoolIndex = poolIndexDataToPDPoolIndex(data);
        assertEq(
            uint128(Unit.unwrap(pdPoolIndex.total_units)), data.totalUnits, "SuperfluidPool.prop: total units not equal"
        );
        _helperAssertWrappedParticle(data, pdPoolIndex._wrapped_particle);
    }

    function testPDPoolIndexToPoolIndexData(
        int128 totalUnits,
        uint32 wrappedSettledAt,
        int96 wrappedFlowRate,
        int256 wrappedSettledValue
    ) public pure {
        vm.assume(totalUnits > 0);
        PDPoolIndex memory pdPoolIndex = PDPoolIndex(
            Unit.wrap(totalUnits),
            BasicParticle(Time.wrap(wrappedSettledAt), FlowRate.wrap(wrappedFlowRate), Value.wrap(wrappedSettledValue))
        );
        PoolIndexData memory poolIndexData = _pdPoolIndexToPoolIndexData(pdPoolIndex);
        assertEq(
            poolIndexData.totalUnits,
            uint128(Unit.unwrap(pdPoolIndex.total_units)),
            "SuperfluidPool.prop: total units not equal"
        );
        _helperAssertWrappedParticle(poolIndexData, pdPoolIndex._wrapped_particle);
    }

    function testMemberDataToPDPoolMember(MemberData memory data) public pure {
        vm.assume(data.ownedUnits < uint128(type(int128).max));

        PDPoolMember memory pdPoolMember = _memberDataToPDPoolMember(data);
        assertEq(
            uint128(Unit.unwrap(pdPoolMember.owned_units)),
            data.ownedUnits,
            "SuperfluidPool.prop: owned units not equal"
        );
        assertEq(
            Value.unwrap(pdPoolMember._settled_value), data.settledValue, "SuperfluidPool.prop: settled value not equal"
        );
        _helperAssertWrappedParticle(data, pdPoolMember._synced_particle);
    }
}
