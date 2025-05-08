// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// solhint-disable not-rely-on-time

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    Time, Value, FlowRate,
    BasicParticle, PDPoolIndex,
    ISuperfluidPool,
    FlowId, ToySuperfluidToken
} from "./ToySuperfluidToken.sol";


/**
 * @dev A very special toy super token implementation.
 *
 * Features:
 * - Pure super token, no ERC20 wrapping business.
 * - Negative account is allowed.
 * - no permission control for account going negative.
 */
contract ToySuperToken is ToySuperfluidToken, IERC20 {
    mapping (address owner => mapping(address => uint256) allowances) private _allowances;

    ////////////////////////////////////////////////////////////////////////////////
    // ERC20 operations
    ////////////////////////////////////////////////////////////////////////////////

    function totalSupply() external pure returns (uint256) {
        // Yes, I mean it.
        return 0;
    }

    function balanceOf(address account) override external view returns (uint256) {
        Time t = Time.wrap(uint32(block.timestamp));
        Value avb = realtimeBalanceAt(account, t);
        return Value.unwrap(avb) > 0 ? uint256(Value.unwrap(avb)) : 0;
    }

    function transfer(address to, uint256 amount) override external returns (bool) {
        bytes memory eff = _tokenEff("transfer", new bytes(0));
        return _shift(eff, msg.sender, msg.sender, to, Value.wrap(SafeCast.toInt256(amount)));
    }

    function transferFrom(address from, address to, uint256 amount) override external returns (bool) {
        bytes memory eff = _tokenEff("transferFrom", new bytes(0));
        return _shift(eff, msg.sender, from, to, Value.wrap(SafeCast.toInt256(amount)));
    }

    function allowance(address owner, address spender) override external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) override external returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ERC20-style approval/allowance System for shift2
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _acl(address operator, address from, address /* to */,
                  Value shiftAmount, FlowRate shiftFlowRate)
        override internal returns (bool)
    {
        if (from != operator) {
            // No ACL support for flows
            if (FlowRate.unwrap(shiftFlowRate) != 0) return false;

            // NOTE: uint256 casting is safe: amount is required to be non negative
            _spendAllowance(from, operator, uint256(Value.unwrap(shiftAmount)));
        }
        return true;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Buffer Based Solvency
    ////////////////////////////////////////////////////////////////////////////////

    function _adjustBuffer(bytes memory eff,
                           address from, bytes32 flowHash,
                           FlowRate /* oldFlowRate */, FlowRate newFlowRate)
        override internal returns (bytes memory)
    {
        // not using oldFlowRate in this model
        // surprising effect: reducing flow rate may require more buffer when liquidation_period adjusted upward
        Value newBufferAmount = newFlowRate.mul(liquidationPeriod);
        Value bufferDelta = newBufferAmount - flowData[flowHash].buffer;
        eff = _doShift(eff, from, address(this), bufferDelta);
        accountData[from].totalBuffer = accountData[from].totalBuffer + bufferDelta;
        flowData[flowHash].buffer = newBufferAmount;
        return eff;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Fancier Token Monad Overrides
    ////////////////////////////////////////////////////////////////////////////////

    function shift(address from, address to, Value amount) override external
        returns (bool success)
    {
        bytes memory eff = _tokenEff("shift", new bytes(0));
        return _shift(eff, msg.sender, from, to, amount);
    }

    function flow(address from, address to, FlowId flowId, FlowRate flowRate) override external
        returns (bool success)
    {
        bytes memory eff = _tokenEff("flow", new bytes(0));
        return _flow(eff, msg.sender, from, to, flowId, flowRate);
    }

    function distribute(address from, ISuperfluidPool to, Value reqAmount) override external
        returns (bool success, Value actualAmount)
    {
        bytes memory eff = _tokenEff("distribute", new bytes(0));
        return _distribute(eff, msg.sender, from, to, reqAmount);
    }

    function distributeFlow(address from, ISuperfluidPool to, FlowId flowId, FlowRate reqFlowRate) override external
        returns (bool success, FlowRate actualFlowRate, FlowRate newDistributionFlowRate)
    {
        bytes memory eff = _tokenEff("distributeFlow", new bytes(0));
        return _distributeFlow(eff, msg.sender, from, to, flowId, reqFlowRate);
    }

    function appendIndexUpdateByPool(BasicParticle memory p, Time t)
        override external returns (bool)
    {
        bytes memory eff = _tokenEff("appendIndexUpdateByPool", new bytes(0));
        _appendIndexUpdateByPool(eff, msg.sender, p, t);
        return true;
    }

    function poolSettleClaim(address claimRecipient, Value amount)
        override external returns (bool)
    {
        bytes memory eff = _tokenEff("poolSettleClaim", new bytes(0));
        _poolSettleClaim(eff, claimRecipient, amount);
        return true;
    }

    struct TokenEff {
        address msgSender;
        string prim;
        bytes primExtra;
    }

    function _tokenEff(string memory prim, bytes memory primExtra) internal view returns (bytes memory)
    {
        return abi.encode(TokenEff(msg.sender, prim, primExtra));
    }

    function _getUIndex(bytes memory /*eff*/, address owner)
        virtual override internal view returns (BasicParticle memory)
    {
        return ToySuperfluidToken._getUIndex(new bytes(0), owner);
    }
    event UIndexSet(address indexed msgSender, string indexed prim, address indexed owner,
                    BasicParticle p, bytes primEtra);
    function _setUIndex(bytes memory eff, address owner, BasicParticle memory p)
        virtual override internal returns (bytes memory)
    {
        (TokenEff memory teff) = abi.decode(eff, (TokenEff));
        emit UIndexSet(teff.msgSender, teff.prim, owner, p, teff.primExtra);
        ToySuperfluidToken._setUIndex(new bytes(0), owner, p);
        return eff;
    }

    function _getPDPIndex(bytes memory /*eff*/, address pool)
        virtual override internal view returns (PDPoolIndex memory)
    {
        return ISuperfluidPool(pool).getIndex();
    }
    event PDPIndexSet(address indexed msgSender, string indexed prim, address indexed pool,
                      PDPoolIndex p, bytes primEtra);
    function _setPDPIndex(bytes memory eff, address pool, PDPoolIndex memory p)
        internal virtual override returns (bytes memory)
    {
        (TokenEff memory teff) = abi.decode(eff, (TokenEff));
        emit PDPIndexSet(teff.msgSender, teff.prim, pool, p, teff.primExtra);
        ToySuperfluidToken._setPDPIndex(new bytes(0), pool, p);
        return eff;
    }

    function _getFlowRate(bytes memory /*eff*/, bytes32 flowHash)
        virtual override internal view returns (FlowRate)
    {
        return ToySuperfluidToken._getFlowRate(new bytes(0), flowHash);
    }
    event FlowInfoSet(address indexed msgSender, string indexed prim, bytes32 indexed flowHash,
                      FlowRate flowRate, bytes primEtra);
    function _setFlowInfo(bytes memory eff, bytes32 flowHash, address from, address to,
                          FlowRate newFlowRate, FlowRate flowRateDelta)
        internal virtual override returns (bytes memory)
    {
        (TokenEff memory teff) = abi.decode(eff, (TokenEff));
        emit FlowInfoSet(teff.msgSender, teff.prim, flowHash, newFlowRate, teff.primExtra);
        ToySuperfluidToken._setFlowInfo(new bytes(0), flowHash, from, to, newFlowRate, flowRateDelta);
        return eff;
    }
}
