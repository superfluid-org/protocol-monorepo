// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// solhint-disable not-rely-on-time

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { FlowId, ISuperfluidToken } from "./ISuperfluidToken.sol";
import {
    Time, Value, FlowRate,
    BasicParticle,
    PDPoolIndex
} from "../SemanticMoney.sol";
import { TokenMonad } from "../TokenMonad.sol";
import {
    ISuperfluidPool, ToySuperfluidPool
} from "./ToySuperfluidPool.sol";


/**
 * @dev A very special toy super token implementation.
 *
 * Features:
 * - Pure super token, no ERC20 wrapping business.
 * - Negative account is allowed.
 * - no permission control for account going negative.
 */
contract ToySuperfluidToken is ISuperfluidToken, TokenMonad {
    using EnumerableSet for EnumerableSet.AddressSet;

    ToySuperfluidPool public immutable POOL_CONTRACT_MASTER_COPY;

    Time public liquidationPeriod = Time.wrap(1000 seconds);

    struct AccountData {
        Value    totalBuffer;
        FlowRate totalInflowRate;
        // FlowRate totalAdjustmentFlowRateReceived;
        FlowRate totalOutflowRate;
    }

    struct FlowData {
        address  from;
        address  to;
        FlowRate flowRate;
        Value    buffer;
    }

    struct PoolInfo {
        bool exist;
    }

    mapping (address owner => BasicParticle) public uIndexes;
    mapping (address owner => AccountData) public accountData;
    mapping (bytes32 flowHash => FlowData) public flowData;
    mapping (address pool => PoolInfo) private _poolInfoMap;
    mapping (address owner => EnumerableSet.AddressSet poolConnections) private _poolConnectionsMap;

    constructor () {
        POOL_CONTRACT_MASTER_COPY = new ToySuperfluidPool();
    }

    function setLiquidationPeriod(Time a) external {
        liquidationPeriod = a;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Generalized Payment Primitives
    ////////////////////////////////////////////////////////////////////////////////

    function realtimeBalanceNow(address account) override external view
        returns (Value avb)
    {
        Time t = Time.wrap(uint32(block.timestamp));
        return realtimeBalanceAt(account, t);
    }

    function realtimeBalanceAt(address account, Time t) override public view
        returns (Value avb)
    {
        (Value own, Value fromPools,) = realtimeBalanceVectorAt(account, t);
        avb = own + fromPools;
    }

    function realtimeBalanceVectorNow(address account) override public view
        returns (Value own, Value fromPools, Value deposit)
    {
        Time t = Time.wrap(uint32(block.timestamp));
        return realtimeBalanceVectorAt(account, t);
    }

    function realtimeBalanceVectorAt(address account, Time t) override public view
        returns (Value own, Value fromPools, Value deposit)
    {
        // NB! Adding cumulative disconnected distributions from a pool.
        // It is cumulative because the claimed distributions are already offset via the universal indexes.
        if (_isPool(account)) {
            ISuperfluidPool pool = ISuperfluidPool(account);
            own = pool.getDisconnectedBalance(t);
        } else {
            own = _getUIndex(new bytes(0), account).rtb(t);
        }

        // pool-connected balance
        {
            EnumerableSet.AddressSet storage connections = _poolConnectionsMap[account];
            for (uint i = 0; i < connections.length(); ++i) {
                ISuperfluidPool p = ISuperfluidPool(connections.at(i));
                // NB! Please ask solidity designer why "+=" is not derived for overloaded operator custom types
                fromPools = fromPools + p.getClaimable(account, t);
            }
        }

        deposit = accountData[account].totalBuffer;
    }

    function getNetFlowRate(address account) override external view returns (FlowRate nr) {
        nr = _getUIndex(new bytes(0), account).flow_rate();

        // pool distribution flow rate
        if (_isPool(account)) {
            ISuperfluidPool pool = ISuperfluidPool(account);
            nr = nr + pool.getDisconnectedFlowRate();
        }

        // pool-connected flows
        {
            EnumerableSet.AddressSet storage connections = _poolConnectionsMap[account];
            for (uint i = 0; i < connections.length(); ++i) {
                ISuperfluidPool p = ISuperfluidPool(connections.at(i));
                nr = nr + p.getMemberFlowRate(account);
            }
        }
    }

    function getFlowHash(address from, address to, FlowId flowId) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, "flow", from, to, flowId));
    }

    function getDistributionFlowHash(address from, ISuperfluidPool to, FlowId flowId) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, "distribution_flow", from, address(to), flowId));
    }

    function getPoolAdjustmentFlowHash(address from, address to) public view returns (bytes32)
    {
        // this will never be in conflict with other flow has types
        return keccak256(abi.encode(block.chainid, "pool_adjustment_flow", from, to));
    }

    // getTotalFlowRate(address from, address to)
    function getFlowRate(address from, address to, FlowId flowId) override external view returns (FlowRate) {
        return _getFlowRate(new bytes(0), getFlowHash(from, to, flowId));
    }

    // This is the non-ERC20 version of instant transfer, that can trigger actions defined by "to"
    function _shift(bytes memory eff, address operator, address from, address to, Value amount) internal
        returns (bool success)
    {
        /// check inputs
        require(!_isPool(to), "Use distribute to pool");
        require(Value.unwrap(amount) >= 0, "Amount must not be negative");

        // permission control
        require(_acl(operator, from, to, amount, FlowRate.wrap(0)), "ACL for shift not supported");

        // Make updates
        _doShift(eff, from, to, amount);
        return true;
    }

    function shift(address from, address to, Value amount)
        virtual override external returns (bool success)
    {
        return _shift(new bytes(0), msg.sender, from, to, amount);
    }

    function _flow(bytes memory eff, address operator, address from, address to, FlowId flowId, FlowRate flowRate)
        internal returns (bool success)
    {
        /// check inputs
        require(!_isPool(to), "Use distributeFlow to pool");
        require(FlowRate.unwrap(flowRate) >= 0, "Flow rate must not be negative");
        require(from != to, "Shall not send flow to oneself");

        // permission control
        require(_acl(operator, from, to, Value.wrap(0), flowRate), "ACL for flow not supported");

        /// prepare local variables (let bindings)
        Time t = Time.wrap(uint32(block.timestamp));
        bytes32 flowHash = getFlowHash(from, to, flowId);
        FlowRate oldFlowRate = _getFlowRate(eff, flowHash);

        // Make updates
        eff = _doFlow(eff, from, to, flowHash, flowRate, t);
        eff = _adjustBuffer(eff, from, flowHash, oldFlowRate, flowRate /* assert(newFlowRate == flowRate) */);

        return true;
    }

    function flow(address from, address to, FlowId flowId, FlowRate flowRate)
        virtual override external returns (bool success)
    {
        return _flow(new bytes(0), msg.sender, from, to, flowId, flowRate);
    }

    function _distribute(bytes memory eff, address operator, address from, ISuperfluidPool to, Value reqAmount)
        internal returns (bool success, Value actualAmount)
    {
        /// check inputs
        require(_isPool(address(to)), "Distribute to pool only");
        require(Value.unwrap(reqAmount) >= 0, "Requested amount must not be negative");

        // permission control
        // FIXME actualAmount
        require(_acl(operator, from, address(to), reqAmount, FlowRate.wrap(0)), "ACL for distribute not supported");

        // Make updates
        (, actualAmount) = _doDistributeViaPool(eff, from, address(to), reqAmount);
        success = true;
    }

    function distribute(address from, ISuperfluidPool to, Value reqAmount)
        virtual override external returns (bool success, Value actualAmount)
    {
        return _distribute(new bytes(0), msg.sender, from, to, reqAmount);
    }

    function _distributeFlow(bytes memory eff, address operator, address from, ISuperfluidPool to,
                             FlowId flowId, FlowRate reqFlowRate)
        internal returns (bool success, FlowRate actualFlowRate, FlowRate newDistributionFlowRate)
    {
        /// check inputs
        require(_isPool(address(to)), "Distribute flow to pool only");
        require(FlowRate.unwrap(reqFlowRate) >= 0, "Requested flow rate must not be negative");

        /// prepare local variables
        Time t = Time.wrap(uint32(block.timestamp));
        bytes32 flowHash = getDistributionFlowHash(from, to, flowId);
        FlowRate oldFlowRate = _getFlowRate(eff, flowHash);

        // permission control
        // FIXME actualFlowRate
        require(_acl(operator, from, address(to), Value.wrap(0), reqFlowRate), "ACL for distribute not supported");

        // Make updates
        (eff, actualFlowRate, newDistributionFlowRate) = _doDistributeFlowViaPool
            (eff, from, address(to), flowHash, reqFlowRate, t);
        eff = _adjustBuffer(eff, from, flowHash, oldFlowRate, actualFlowRate);
        success = true;
    }

    function distributeFlow(address from, ISuperfluidPool to, FlowId flowId, FlowRate reqFlowRate)
        virtual override external returns (bool success, FlowRate actualFlowRate, FlowRate newDistributionFlowRate)
    {
        return _distributeFlow(new bytes(0), msg.sender, from, to, flowId, reqFlowRate);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Pool Operations
    ////////////////////////////////////////////////////////////////////////////////

    function createPool() external
        returns (ToySuperfluidPool pool)
    {
        pool = ToySuperfluidPool(Clones.clone(address(POOL_CONTRACT_MASTER_COPY)));
        pool.initialize(msg.sender);
        _registerPool(address(pool));
    }

    function isPool(address p) override external view returns (bool) {
        return _isPool(p);
    }

    function getNumConnections(address account) override external view returns (uint) {
        return _poolConnectionsMap[account].length();
    }

    function connectPool(ISuperfluidPool to) override external
        returns (bool success) {
        return connectPool(to, true);
    }

    function disconnectPool(ISuperfluidPool to) override external
        returns (bool success) {
        return connectPool(to, false);
    }

    function connectPool(ISuperfluidPool to, bool doConnect) override public
        returns (bool success)
    {
        require(_isPool(address(to)), "Not a pool!!");

        Time t = Time.wrap(uint32(block.timestamp));
        if (doConnect) {
            if (!_poolConnectionsMap[msg.sender].contains(address(to))) {
                _poolConnectionsMap[msg.sender].add(address(to));
                assert(to.operatorConnectMember(msg.sender, true, t));
            }
        } else {
            if (_poolConnectionsMap[msg.sender].contains(address(to))) {
                _poolConnectionsMap[msg.sender].remove(address(to));
                assert(to.operatorConnectMember(msg.sender, false, t));
            }
        }
        return true;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Pool Admin Operations
    ////////////////////////////////////////////////////////////////////////////////

    function isMemberConnected(ISuperfluidPool to, address memberAddr) override external view returns (bool) {
        return _poolConnectionsMap[memberAddr].contains(address(to));
    }

    function getPoolAdjustmentFlowInfo(ISuperfluidPool pool) override external view
        returns (address recipient, bytes32 flowHash, FlowRate flowRate)
    {
        return _getPoolAdjustmentFlowInfo(new bytes(0), address(pool));
    }

    function _appendIndexUpdateByPool(bytes memory eff, address pool, BasicParticle memory p, Time t) internal {
        require(_isPool(pool), "Only a pool can adjust flow!");
        uIndexes[pool] = uIndexes[pool].mappend(p);
        _setPoolAdjustmentFlowRate(eff, pool, true /* doShift? */, p.flow_rate(), t);
    }

    function appendIndexUpdateByPool(BasicParticle memory p, Time t)
        virtual override external returns (bool)
    {
        _appendIndexUpdateByPool(new bytes(0), msg.sender, p, t);
        return true;
    }

    function _poolSettleClaim(bytes memory eff, address claimRecipient, Value amount)
        internal
    {
        require(_isPool(msg.sender), "Only a pool can settle claim!");
        _doShift(eff, msg.sender, claimRecipient, amount);
    }

    /// Settle the claim
    function poolSettleClaim(address claimRecipient, Value amount)
        virtual override external returns (bool)
    {
        _poolSettleClaim(new bytes(0), claimRecipient, amount);
        return true;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Other Internal Functions
    ////////////////////////////////////////////////////////////////////////////////

    function _isPool(address pool) internal view virtual returns (bool) {
        return _poolInfoMap[pool].exist;
    }
    function _registerPool(address pool) internal virtual {
        _poolInfoMap[pool].exist = true;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ACL Hook
    ////////////////////////////////////////////////////////////////////////////////

    function _acl(address operator, address from, address /* to */,
                  Value /* shiftAmount */, FlowRate /* shiftFlowRate */)
        virtual internal returns (bool)
    {
        return operator == from /* || to != address(this) */;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Buffer Based Solvency
    ////////////////////////////////////////////////////////////////////////////////

    function _adjustBuffer(bytes memory eff,
                           address /* from */, bytes32 /* flowHash */,
                           FlowRate /* oldFlowRate */, FlowRate /* newFlowRate */)
        virtual internal returns (bytes memory)
    {
        return eff;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Token Monad Overrides
    ////////////////////////////////////////////////////////////////////////////////

    function _getUIndex(bytes memory /*eff*/, address owner)
        virtual override internal view returns (BasicParticle memory)
    {
        return uIndexes[owner];
    }
    function _setUIndex(bytes memory eff, address owner, BasicParticle memory p)
        virtual override internal returns (bytes memory)
    {
        uIndexes[owner] = p;
        return eff;
    }

    function _getPDPIndex(bytes memory /*eff*/, address pool)
        virtual override internal view returns (PDPoolIndex memory)
    {
        return ISuperfluidPool(pool).getIndex();
    }
    function _setPDPIndex(bytes memory eff, address pool, PDPoolIndex memory p)
        virtual override internal returns (bytes memory)
    {
        assert(ISuperfluidPool(pool).operatorSetIndex(p));
        return eff;
    }

    function _getFlowRate(bytes memory /*eff*/, bytes32 flowHash)
        virtual override internal view returns (FlowRate)
    {
        return flowData[flowHash].flowRate;
    }
    function _setFlowInfo(bytes memory eff, bytes32 flowHash, address from, address to,
                          FlowRate newFlowRate, FlowRate flowRateDelta)
        virtual override internal returns (bytes memory)
    {
        // the buffer amount now mismatches the newFlowRate, it should be adjusted separately.
        flowData[flowHash] = FlowData(from, to, newFlowRate, flowData[flowHash].buffer);
        accountData[from].totalOutflowRate = accountData[from].totalOutflowRate + flowRateDelta;
        accountData[to].totalInflowRate = accountData[from].totalInflowRate + flowRateDelta;
        return eff;
    }

    function _getPoolAdjustmentFlowInfo(bytes memory eff, address pool)
        internal view returns (address adjustmentRecipient, bytes32 flowHash, FlowRate)
    {
        adjustmentRecipient = ToySuperfluidPool(pool).admin();
        flowHash = getPoolAdjustmentFlowHash(pool, adjustmentRecipient);
        return (adjustmentRecipient, flowHash, _getFlowRate(eff, flowHash));
    }

    function _getPoolAdjustmentFlowRate(bytes memory eff, address pool)
        override internal view returns (FlowRate flowRate) {
        (,,flowRate) = _getPoolAdjustmentFlowInfo(eff, pool);
    }

    function _setPoolAdjustmentFlowRate(bytes memory eff, address pool, FlowRate flowRate, Time t)
        override internal returns (bytes memory)
    {
        return _setPoolAdjustmentFlowRate(eff, pool, false /* doShift? */, flowRate, t);
    }

    function _setPoolAdjustmentFlowRate(bytes memory eff, address pool,
                                        bool doShiftFlow, FlowRate flowRate, Time t)
        internal returns (bytes memory)
    {
        address adjustmentRecipient = ToySuperfluidPool(pool).admin();
        bytes32 adjustmentFlowHash = getPoolAdjustmentFlowHash(pool, adjustmentRecipient);

        if (doShiftFlow) {
            flowRate = flowRate + _getFlowRate(eff, adjustmentFlowHash);
        }

        eff = _doFlow(eff, pool, adjustmentRecipient, adjustmentFlowHash, flowRate, t);

        return eff;
    }
}
