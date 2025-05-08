// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// solhint-disable not-rely-on-time

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {
    Time, Value, FlowRate, Unit,
    BasicParticle,
    PDPoolIndex, PDPoolMember, PDPoolMemberMU
} from "../SemanticMoney.sol";
import {
    ISuperfluidPool, ISuperfluidPoolOperator
} from "./ISuperfluidPool.sol";


/**
 * @dev A toy implementation for proportional distribution pool.
 *
 * NOTE: Solidity public getter function for the storage fields do not support structs,
 *       hence their public getter are added manually instead.
 */
contract ToySuperfluidPool is Initializable, ISuperfluidPool {
    // pool operator is the contract that can call privileged functions prefixed with `operator`.
    address public immutable POOL_OPERATOR;

    // pool admin is the one that can update pool's member units.
    address public admin;
    PDPoolIndex internal _pdpIndex;
    mapping (address member => PDPoolMember member_data) internal _members;
    mapping (address member => Value claimed_value) internal _claimedValues;
    // This is a pseudo member, representing all the disconnected members
    PDPoolMember internal _disconnectedMembers;
    Value internal _claimedByDisconnectedMembers;

    constructor () {
        POOL_OPERATOR = msg.sender;
    }

    function initialize(address admin_) public initializer() {
        admin = admin_;
    }

    function getIndex() override external view returns (PDPoolIndex memory) {
        return _pdpIndex;
    }

    function getTotalUnits() override external view returns (Unit) {
        return _pdpIndex.total_units;
    }

    function getDisconnectedUnits() override external view returns (Unit) {
        return _disconnectedMembers.owned_units;
    }

    function getUnits(address memberAddr) override external view returns (Unit) {
        return _members[memberAddr].owned_units;
    }

    function getDistributionFlowRate() external view returns (FlowRate) {
        return _pdpIndex.flow_rate();
    }

    function getConnectedFlowRate() override external view returns (FlowRate) {
        return _pdpIndex.flow_rate_per_unit().mul(_pdpIndex.total_units);
    }

    function getDisconnectedFlowRate() override external view returns (FlowRate) {
        return _pdpIndex.flow_rate_per_unit().mul(_disconnectedMembers.owned_units);
    }

    function getDisconnectedBalance(Time t) override external view returns (Value) {
        return PDPoolMemberMU(_pdpIndex, _disconnectedMembers).rtb(t)
            - _claimedByDisconnectedMembers;
    }

    function getMemberFlowRate(address memberAddr) override external view returns (FlowRate) {
        Unit u = _members[memberAddr].owned_units;
        if (Unit.unwrap(u) == 0) return FlowRate.wrap(0);
        else return _pdpIndex.flow_rate_per_unit().mul(u);
    }

    function getClaimable(address memberAddr, Time t) override public view returns (Value) {
        return PDPoolMemberMU(_pdpIndex, _members[memberAddr]).rtb(t) - _claimedValues[memberAddr];
    }

    function getClaimable(address memberAddr) override external view returns (Value v) {
        Time t = Time.wrap(uint32(block.timestamp));
        v = getClaimable(memberAddr, t);
    }

    function updateMember(address memberAddr, Unit newUnits) override external returns (bool) {
        require(Unit.unwrap(newUnits) >= 0, "No negative unit amount!");
        require(admin == msg.sender, "Not pool admin!");
        Time t = Time.wrap(uint32(block.timestamp));
        bool isConnected = ISuperfluidPoolOperator(POOL_OPERATOR).isMemberConnected(this, memberAddr);
        PDPoolMemberMU memory mu = PDPoolMemberMU(_pdpIndex, _members[memberAddr]);

        if (!isConnected) {
            // trigger the side effect of claiming all if not connected
            Value claimedAmount = _claimAll(memberAddr, t);

            // update pool's disconnected units
            _shiftDisconnectedUnits(newUnits - mu.m.owned_units, claimedAmount, t);
        }

        // update pool member's units
        {
            BasicParticle memory p;
            (_pdpIndex, _members[memberAddr], p) = mu.pool_member_update(p, newUnits, t);
            assert(ISuperfluidPoolOperator(POOL_OPERATOR).appendIndexUpdateByPool(p, t));
        }

        return true;
    }

    function claimAll(address memberAddr) override public returns (bool) {
        bool isConnected = ISuperfluidPoolOperator(POOL_OPERATOR).isMemberConnected(this, memberAddr);
        Time t = Time.wrap(uint32(block.timestamp));
        Value claimedAmount = _claimAll(memberAddr, t);
        if (!isConnected) {
            _shiftDisconnectedUnits(Unit.wrap(0), claimedAmount, t);
        }
        return true;
    }

    function claimAll() override external returns (bool) {
        return claimAll(msg.sender);
    }

    function _claimAll(address memberAddr, Time t) internal returns (Value amount) {
        amount = getClaimable(memberAddr, t);
        assert(ISuperfluidPoolOperator(POOL_OPERATOR).poolSettleClaim(memberAddr, amount));
        _claimedValues[memberAddr] = _claimedValues[memberAddr] + amount;
    }

    function operatorSetIndex(PDPoolIndex calldata index) override external
        onlyOperator returns (bool)
    {
        _pdpIndex = index;
        return true;
    }

    function operatorConnectMember(address memberAddr, bool doConnect, Time t) override external
        onlyOperator returns (bool)
    {
        // NB! This is an assumption that isConnected = !doConnect,
        //     and it should be respected by the operator.

        // trigger the side effects of claiming all
        Value claimedAmount = _claimAll(memberAddr, t);

        // update pool's disconnected units
        {
            Unit u = _members[memberAddr].owned_units;
            if (doConnect) {
                // previous disconnected, now to be connected
                // => removing from the disconnected distribution group
                _shiftDisconnectedUnits(-u, claimedAmount, t);
            } else {
                // previous connected, now to be disconnected
                // => adding to disconnected distribution group
                _shiftDisconnectedUnits(u, Value.wrap(0), t);
            }
        }

        return true;
    }

    function _shiftDisconnectedUnits(Unit shiftUnits, Value claimedAmount, Time t) internal {
        PDPoolMemberMU memory mu = PDPoolMemberMU(_pdpIndex, _disconnectedMembers);
        mu = mu.settle(t);
        mu.m.owned_units = mu.m.owned_units + shiftUnits;
        _disconnectedMembers = mu.m;
        // Note to implementers:
        //
        // As an optimization, this additional storage field may be merged with _disconnectedMembers._settled_value.
        // The toy model though holds conceptual clarity as top priority instead, and accessing the private field
        // `_settled_value` is deemed breaking such clarity.
        _claimedByDisconnectedMembers = _claimedByDisconnectedMembers + claimedAmount;
    }

    modifier onlyOperator () {
        assert(POOL_OPERATOR == msg.sender);
        _;
    }
}
