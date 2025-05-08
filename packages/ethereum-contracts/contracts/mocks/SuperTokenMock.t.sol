// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ISuperfluid, IERC20, IPoolAdminNFT, IPoolMemberNFT
} from "../interfaces/superfluid/ISuperfluid.sol";
import { UUPSProxiable } from "../upgradability/UUPSProxiable.sol";
import { ERC777Helper } from "../libs/ERC777Helper.sol";
import { SuperToken, IConstantOutflowNFT, IConstantInflowNFT } from "../superfluid/SuperToken.sol";
import { SuperfluidToken } from "../superfluid/SuperfluidToken.sol";

contract SuperTokenStorageLayoutTester is SuperToken {
    constructor(
        ISuperfluid host,
        IConstantOutflowNFT constantOutflowNFTProxy,
        IConstantInflowNFT constantInflowNFTProxy,
        IPoolAdminNFT poolAdminNFTProxy,
        IPoolMemberNFT poolMemberNFTProxy
    ) SuperToken(host, constantOutflowNFTProxy, constantInflowNFTProxy, poolAdminNFTProxy, poolMemberNFTProxy)
    // solhint-disable-next-line no-empty-blocks
    { }

    // @dev Make sure the storage layout never change over the course of the development
    function validateStorageLayout() external pure {
        uint256 slot;
        uint256 offset;

        // Initializable _initialized and _initialized

        // SuperfluidToken storages

        assembly { slot:= _inactiveAgreementBitmap.slot offset := _inactiveAgreementBitmap.offset }
        require (slot == 1 && offset == 0, "_inactiveAgreementBitmap changed location");

        assembly { slot:= _sharedSettledBalances.slot offset := _sharedSettledBalances.offset }
        require (slot == 2 && offset == 0, "_sharedSettledBalances changed location");

        assembly { slot:= _totalSupply.slot offset := _totalSupply.offset }
        require (slot == 3 && offset == 0, "_totalSupply changed location");

        assembly { slot:= _reserve4.slot offset := _reserve4.offset }
        require (slot == 4 && offset == 0, "_reserve4 changed location");

        assembly { slot:= _reserve13.slot offset := _reserve13.offset }
        require (slot == 13 && offset == 0, "_reserve9 changed location");

        // SuperToken storages

        assembly { slot:= _underlyingToken.slot offset := _underlyingToken.offset }
        require (slot == 14 && offset == 0, "_underlyingToken changed location");

        assembly { slot:= _underlyingDecimals.slot offset := _underlyingDecimals.offset }
        require (slot == 14 && offset == 20, "_underlyingDecimals changed location");

        assembly { slot:= _name.slot offset := _name.offset }
        require (slot == 15 && offset == 0, "_name changed location");

        assembly { slot:= _symbol.slot offset := _symbol.offset }
        require (slot == 16 && offset == 0, "_symbol changed location");

        assembly { slot:= _allowances.slot offset := _allowances.offset }
        require (slot == 17 && offset == 0, "_allowances changed location");

        assembly { slot:= _operators.slot offset := _operators.offset }
        require (slot == 18 && offset == 0, "_operators changed location");
        // uses 4 slots

        assembly { slot:= _reserve23.slot offset := _reserve23.offset }
        require (slot == 23 && offset == 0, "_reserve23 changed location");

        assembly { slot:= _reserve31.slot offset := _reserve31.offset }
        require (slot == 31 && offset == 0, "_reserve31 changed location");
    }

    function getLastSuperTokenStorageSlot() external pure returns (uint slot) {
        assembly { slot:= _reserve31.slot }
    }
}

contract SuperTokenMock is SuperToken {
    uint256 public immutable waterMark;

    constructor(
        ISuperfluid host,
        uint256 w,
        IConstantOutflowNFT constantOutflowNFTProxy,
        IConstantInflowNFT constantInflowNFTProxy,
        IPoolAdminNFT poolAdminNFTProxy,
        IPoolMemberNFT poolMemberNFTProxy
    ) SuperToken(host, constantOutflowNFTProxy, constantInflowNFTProxy, poolAdminNFTProxy, poolMemberNFTProxy) {
        waterMark = w;
    }

    /**
     * ERC-20 mockings
     */
    function approveInternal(address owner, address spender, uint256 value) external {
        _approve(owner, spender, value);
    }

    function transferInternal(address from, address to, uint256 value) external {
        _transferFrom(from, from, to, value);
    }

    /**
     * ERC-777 mockings
     */
    function setupDefaultOperators(address[] memory operators) external {
        _setupDefaultOperators(operators);
    }

    function mintInternal(address to, uint256 amount, bytes memory userData, bytes memory operatorData) external {
        _mint(msg.sender, to, amount, true, /* invokeHook */ true, /* requireReceptionAck */ userData, operatorData);
    }
}

/// @title NoNFTSuperTokenMock
/// @author Superfluid
/// @notice Minimal SuperToken implementation to test flow creation if no NFT proxy contract variable exists.
/// Storage layout is made to mimic SuperToken.
contract NoNFTSuperTokenMock is UUPSProxiable, SuperfluidToken {
    using SafeERC20 for IERC20;

    /// @dev The underlying ERC20 token
    IERC20 internal _underlyingToken;

    /// @dev Decimals of the underlying token
    uint8 internal _underlyingDecimals;

    /// @dev TokenInfo Name property
    string internal _name;

    /// @dev TokenInfo Symbol property
    string internal _symbol;

    /// @dev ERC20 Allowances Storage
    mapping(address => mapping(address => uint256)) internal _allowances;

    /// @dev ERC777 operators support data
    ERC777Helper.Operators internal _operators;

    constructor(ISuperfluid host) SuperfluidToken(host) { }

    /// @dev Initialize the Super Token proxy
    function initialize(IERC20 underlyingToken, uint8 underlyingDecimals, string calldata n, string calldata s)
        external
        initializer // OpenZeppelin Initializable
    {
        _underlyingToken = underlyingToken;
        _underlyingDecimals = underlyingDecimals;

        _name = n;
        _symbol = s;

        // register interfaces
        ERC777Helper.register(address(this));
    }

    /// @dev ISuperToken.upgrade implementation
    function upgrade(uint256 amount) external {
        _upgrade(msg.sender, msg.sender, msg.sender, amount, "", "");
    }

    /**
     * @dev Handle decimal differences between underlying token and super token
     */
    function _toUnderlyingAmount(uint256 amount)
        private
        view
        returns (uint256 underlyingAmount, uint256 adjustedAmount)
    {
        uint256 factor;
        if (_underlyingDecimals < 18) {
            // if underlying has less decimals
            // one can upgrade less "granualar" amount of tokens
            factor = 10 ** (18 - _underlyingDecimals);
            underlyingAmount = amount / factor;
            // remove precision errors
            adjustedAmount = underlyingAmount * factor;
        } else if (_underlyingDecimals > 18) {
            // if underlying has more decimals
            // one can upgrade more "granualar" amount of tokens
            factor = 10 ** (_underlyingDecimals - 18);
            underlyingAmount = amount * factor;
            adjustedAmount = amount;
        } else {
            underlyingAmount = adjustedAmount = amount;
        }
    }

    function _upgrade(
        address operator,
        address account,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) private {
        if (address(_underlyingToken) == address(0)) revert("");

        (uint256 underlyingAmount, uint256 adjustedAmount) = _toUnderlyingAmount(amount);

        uint256 amountBefore = _underlyingToken.balanceOf(address(this));
        _underlyingToken.safeTransferFrom(account, address(this), underlyingAmount);
        uint256 amountAfter = _underlyingToken.balanceOf(address(this));
        uint256 actualUpgradedAmount = amountAfter - amountBefore;
        if (underlyingAmount != actualUpgradedAmount) revert("");

        _mint(
            operator,
            to,
            adjustedAmount,
            // if `userData.length` than 0, we requireReceptionAck
            userData.length != 0,
            userData,
            operatorData
        );
    }

    /// dummy impl
    function _mint(
        address, // operator,
        address account,
        uint256 amount,
        bool, // requireReceptionAck,
        bytes memory, // userData,
        bytes memory // operatorData
    ) internal {
        if (account == address(0)) {
            revert("");
        }

        SuperfluidToken._mint(account, amount);
    }

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("org.superfluid-finance.contracts.SuperToken.implementation");
    }

    // solhint-disable-next-line no-empty-blocks
    function updateCode(address newAddress) external override { }
}
