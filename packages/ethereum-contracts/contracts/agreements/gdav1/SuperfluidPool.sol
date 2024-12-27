// SPDX-License-Identifier: AGPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.23;

// Notes: We use these interfaces in natspec documentation below, grep @inheritdoc
// solhint-disable-next-line no-unused-import
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {
    BasicParticle,
    SemanticMoney,
    PDPoolMember,
    PDPoolIndex,
    PDPoolMemberMU,
    Value,
    Time,
    FlowRate,
    Unit
} from "@superfluid-finance/solidity-semantic-money/src/SemanticMoney.sol";
import { ISuperfluid } from "../../interfaces/superfluid/ISuperfluid.sol";
import { ISuperfluidToken } from "../../interfaces/superfluid/ISuperfluidToken.sol";
import { ISuperToken } from "../../interfaces/superfluid/ISuperToken.sol";
import { ISuperfluidPool } from "../../interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { GeneralDistributionAgreementV1 } from "../../agreements/gdav1/GeneralDistributionAgreementV1.sol";
import { BeaconProxiable } from "../../upgradability/BeaconProxiable.sol";
import { IPoolMemberNFT } from "../../interfaces/agreements/gdav1/IPoolMemberNFT.sol";

using SafeCast for uint256;
using SafeCast for int256;

function toSemanticMoneyUnit(uint128 units) pure returns (Unit) {
    // @note safe upcasting from uint128 to uint256
    // and use of safecast library for downcasting from uint256 to int128
    return Unit.wrap(uint256(units).toInt256().toInt128());
}

function poolIndexDataToWrappedParticle(SuperfluidPool.PoolIndexData memory data)
    pure
    returns (BasicParticle memory wrappedParticle)
{
    wrappedParticle = BasicParticle({
        _settled_at: Time.wrap(data.wrappedSettledAt),
        _flow_rate: FlowRate.wrap(int128(data.wrappedFlowRate)), // upcast from int96 is safe
        _settled_value: Value.wrap(data.wrappedSettledValue)
    });
}

function poolIndexDataToPDPoolIndex(SuperfluidPool.PoolIndexData memory data)
    pure
    returns (PDPoolIndex memory pdPoolIndex)
{
    pdPoolIndex = PDPoolIndex({
        total_units: toSemanticMoneyUnit(data.totalUnits),
        _wrapped_particle: poolIndexDataToWrappedParticle(data)
    });
}

/**
 * @title SuperfluidPool
 * @author Superfluid
 * @notice A SuperfluidPool which can be used to distribute any SuperToken.
 * @dev Because we are using uint128, uint256 doesn't work here.
 */
contract SuperfluidPool is ISuperfluidPool, BeaconProxiable {
    using SemanticMoney for BasicParticle;

    // Structs
    struct PoolIndexData {
        uint128 totalUnits;
        uint32 wrappedSettledAt;
        int96 wrappedFlowRate;
        int256 wrappedSettledValue;
    }

    struct MemberData {
        uint128 ownedUnits;
        uint32 syncedSettledAt;
        int96 syncedFlowRate;
        int256 syncedSettledValue;
        int256 settledValue;
        int256 claimedValue;
    }

    // Constants & Immutables

    string internal constant _DEFAULT_ERC20_NAME = "Superfluid Pool";
    string internal constant _DEFAULT_ERC20_SYMBOL = "POOL";
    // ERC20 decimals implicitly defaults to 0

    GeneralDistributionAgreementV1 public immutable GDA;

    // State variables - NEVER REORDER!

    ISuperfluidToken public superToken;
    address public admin;
    PoolIndexData internal _index;
    mapping(address => MemberData) internal _membersData;

    /// @dev This is a pseudo member, representing all the disconnected members
    MemberData internal _disconnectedMembers;

    /// @dev owner => (spender => amount)
    mapping(address => mapping(address => uint256)) internal _allowances;

    /// @inheritdoc ISuperfluidPool
    bool public transferabilityForUnitsOwner;

    /// @inheritdoc ISuperfluidPool
    bool public distributionFromAnyAddress;

    // ERC20 metadata
    string internal _erc20Name;
    string internal _erc20Symbol;
    uint8 internal _erc20Decimals;

    constructor(GeneralDistributionAgreementV1 gda) {
        GDA = gda;
    }

    function initialize(
        address admin_,
        ISuperfluidToken superToken_,
        bool transferabilityForUnitsOwner_,
        bool distributionFromAnyAddress_,
        string memory erc20Name_,
        string memory erc20Symbol_,
        uint8 erc20Decimals_
    ) external initializer {
        admin = admin_;
        superToken = superToken_;
        transferabilityForUnitsOwner = transferabilityForUnitsOwner_;
        distributionFromAnyAddress = distributionFromAnyAddress_;
        _erc20Name = erc20Name_;
        _erc20Symbol = erc20Symbol_;
        _erc20Decimals = erc20Decimals_;
    }

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("org.superfluid-finance.contracts.SuperfluidPool.implementation");
    }

    /// @dev This function is only meant to be called by the GDAv1 contract
    function poolOperatorGetIndex() external view returns (PoolIndexData memory) {
        return _index;
    }

    /// @inheritdoc ISuperfluidPool
    function getTotalUnits() external view override returns (uint128) {
        return _getTotalUnits();
    }

    function _getTotalUnits() internal view returns (uint128) {
        return _index.totalUnits;
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    /// @inheritdoc ISuperfluidPool

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }
    /// @inheritdoc ISuperfluidPool

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] - subtractedValue);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /// @dev Transfers `amount` units from `msg.sender` to `to`
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);

        return true;
    }

    /// @dev Transfers `amount` units from `from` to `to`
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];

        // if allowed - amount is negative, this reverts due to overflow
        if (allowed != type(uint256).max) _allowances[from][msg.sender] = allowed - amount;

        _transfer(from, to, amount);

        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == to) revert SUPERFLUID_POOL_SELF_TRANSFER_NOT_ALLOWED();
        if (!transferabilityForUnitsOwner) revert SUPERFLUID_POOL_TRANSFER_UNITS_NOT_ALLOWED();

        uint128 fromUnitsBefore = _getUnits(from);
        uint128 toUnitsBefore = _getUnits(to);
        _updateMemberUnits(from, fromUnitsBefore - amount.toUint128());
        _updateMemberUnits(to, toUnitsBefore + amount.toUint128());
        // assert that the units are updated correctly for from and for to.
        emit Transfer(from, to, amount);
    }

    /// @notice Returns the total number of units for a pool
    function totalSupply() external view override returns (uint256) {
        return _getTotalUnits();
    }

    /// @inheritdoc ISuperfluidPool
    function getTotalConnectedUnits() external view override returns (uint128) {
        return _index.totalUnits - _disconnectedMembers.ownedUnits;
    }

    /// @inheritdoc ISuperfluidPool
    function getTotalDisconnectedUnits() external view override returns (uint128) {
        return _disconnectedMembers.ownedUnits;
    }

    /// @inheritdoc ISuperfluidPool
    function getUnits(address memberAddr) external view override returns (uint128) {
        return _getUnits(memberAddr);
    }

    function _getUnits(address memberAddr) internal view returns (uint128) {
        return _membersData[memberAddr].ownedUnits;
    }

    /// @notice Returns the total number of units for an account for this pool
    /// @dev Although the type is uint256, this can never be greater than type(int128).max
    /// because the custom user type Unit is int128 in the SemanticMoney library
    /// @param account The account to query
    /// @return The total number of owned units of the account
    function balanceOf(address account) external view override returns (uint256) {
        return uint256(_getUnits(account));
    }

    /// @inheritdoc ISuperfluidPool
    function getTotalFlowRate() external view override returns (int96) {
        return _getTotalFlowRate();
    }

    function _getTotalFlowRate() internal view returns (int96) {
        return (_index.wrappedFlowRate * uint256(_index.totalUnits).toInt256()).toInt96();
    }

    /// @inheritdoc ISuperfluidPool
    function getTotalConnectedFlowRate() external view override returns (int96) {
        return _getTotalFlowRate() - _getTotalDisconnectedFlowRate();
    }

    function _getTotalDisconnectedFlowRate() internal view returns (int96 flowRate) {
        PDPoolIndex memory pdPoolIndex = poolIndexDataToPDPoolIndex(_index);
        PDPoolMember memory disconnectedMembers = _memberDataToPDPoolMember(_disconnectedMembers);

        return int256(FlowRate.unwrap(pdPoolIndex.flow_rate_per_unit().mul(disconnectedMembers.owned_units))).toInt96();
    }

    /// @inheritdoc ISuperfluidPool
    function getTotalDisconnectedFlowRate() external view override returns (int96 flowRate) {
        return _getTotalDisconnectedFlowRate();
    }

    /// @inheritdoc ISuperfluidPool
    function getDisconnectedBalance(uint32 time) external view override returns (int256 balance) {
        PDPoolIndex memory pdPoolIndex = poolIndexDataToPDPoolIndex(_index);
        PDPoolMember memory pdPoolMember = _memberDataToPDPoolMember(_disconnectedMembers);
        return Value.unwrap(PDPoolMemberMU(pdPoolIndex, pdPoolMember).rtb(Time.wrap(time)));
    }

    /// @inheritdoc ISuperfluidPool
    function getTotalAmountReceivedByMember(address memberAddr) external view override returns (uint256) {
        MemberData memory memberData = _membersData[memberAddr];

        // max timestamp is uint32.max
        return uint256(
            Value.unwrap(
                // PDPoolMemberMU(poolIndex, memberData)
                PDPoolMemberMU(poolIndexDataToPDPoolIndex(_index), _memberDataToPDPoolMember(memberData)).settle(
                    Time.wrap(uint32(block.timestamp))
                ).m._settled_value
            )
        );
    }

    /// @inheritdoc ISuperfluidPool
    function getMemberFlowRate(address memberAddr) external view override returns (int96) {
        uint128 units = _getUnits(memberAddr);
        if (units == 0) return 0;
        // @note total units must never exceed type(int96).max
        else return (_index.wrappedFlowRate * uint256(units).toInt256()).toInt96();
    }

    /// @inheritdoc IERC20Metadata
    function name() external view override returns (string memory) {
        return bytes(_erc20Name).length == 0 ? "Superfluid Pool" : _erc20Name;
    }

    /// @inheritdoc IERC20Metadata
    function symbol() external view override returns (string memory) {
        return bytes(_erc20Symbol).length == 0 ? "POOL" : _erc20Symbol;
    }

    /// @inheritdoc IERC20Metadata
    function decimals() external view override returns (uint8) {
        return _erc20Decimals;
    }

    function _pdPoolIndexToPoolIndexData(PDPoolIndex memory pdPoolIndex)
        internal
        pure
        returns (PoolIndexData memory data)
    {
        data = PoolIndexData({
            totalUnits: int256(Unit.unwrap(pdPoolIndex.total_units)).toUint256().toUint128(),
            wrappedSettledAt: Time.unwrap(pdPoolIndex.settled_at()),
            wrappedFlowRate: int256(FlowRate.unwrap(pdPoolIndex.flow_rate_per_unit())).toInt96(),
            wrappedSettledValue: Value.unwrap(pdPoolIndex._wrapped_particle._settled_value)
        });
    }

    function _memberDataToPDPoolMember(MemberData memory memberData)
        internal
        pure
        returns (PDPoolMember memory pdPoolMember)
    {
        pdPoolMember = PDPoolMember({
            owned_units: toSemanticMoneyUnit(memberData.ownedUnits),
            _synced_particle: BasicParticle({
                _settled_at: Time.wrap(memberData.syncedSettledAt),
                _flow_rate: FlowRate.wrap(int128(memberData.syncedFlowRate)), // upcast from int96 is safe
                _settled_value: Value.wrap(memberData.syncedSettledValue)
            }),
            _settled_value: Value.wrap(memberData.settledValue)
        });
    }

    function _pdPoolMemberToMemberData(PDPoolMember memory pdPoolMember, int256 claimedValue)
        internal
        pure
        returns (MemberData memory memberData)
    {
        memberData = MemberData({
            ownedUnits: uint256(int256(Unit.unwrap(pdPoolMember.owned_units))).toUint128(),
            syncedSettledAt: Time.unwrap(pdPoolMember._synced_particle._settled_at),
            syncedFlowRate: int256(FlowRate.unwrap(pdPoolMember._synced_particle._flow_rate)).toInt96(),
            syncedSettledValue: Value.unwrap(pdPoolMember._synced_particle._settled_value),
            settledValue: Value.unwrap(pdPoolMember._settled_value),
            claimedValue: claimedValue
        });
    }

    /// @inheritdoc ISuperfluidPool
    function getClaimableNow(address memberAddr)
        external
        view
        override
        returns (int256 claimableBalance, uint256 timestamp)
    {
        timestamp = ISuperfluid(superToken.getHost()).getNow();
        return (getClaimable(memberAddr, uint32(timestamp)), timestamp);
    }

    /// @inheritdoc ISuperfluidPool
    function getClaimable(address memberAddr, uint32 time) public view override returns (int256) {
        Time t = Time.wrap(time);
        PDPoolIndex memory pdPoolIndex = poolIndexDataToPDPoolIndex(_index);
        PDPoolMember memory pdPoolMember = _memberDataToPDPoolMember(_membersData[memberAddr]);
        return Value.unwrap(
            PDPoolMemberMU(pdPoolIndex, pdPoolMember).rtb(t) - Value.wrap(_membersData[memberAddr].claimedValue)
        );
    }

    /// @inheritdoc ISuperfluidPool
    function updateMemberUnits(address memberAddr, uint128 newUnits) external returns (bool) {
        if (msg.sender != admin && msg.sender != address(GDA)) revert SUPERFLUID_POOL_NOT_POOL_ADMIN_OR_GDA();

        _updateMemberUnits(memberAddr, newUnits);

        return true;
    }

    /**
     * @notice Checks whether or not the NFT hook can be called.
     * @dev A staticcall, so `POOL_MEMBER_NFT` must be a view otherwise the assumption is that it reverts
     * @param token the super token that is being streamed
     * @return poolMemberNFT the address returned by low level call
     */
    function _canCallNFTHook(ISuperfluidToken token) internal view returns (address poolMemberNFT) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) =
            address(token).staticcall(abi.encodeWithSelector(ISuperToken.POOL_MEMBER_NFT.selector));

        if (success) {
            // @note We are aware this may revert if a Custom SuperToken's
            // POOL_MEMBER_NFT does not return data that can be
            // decoded to an address. This would mean it was intentionally
            // done by the creator of the Custom SuperToken logic and is
            // fully expected to revert in that case as the author desired.
            poolMemberNFT = abi.decode(data, (address));
        }
    }

    function _handlePoolMemberNFT(address memberAddr, uint128 newUnits) internal {
        // Pool Member NFT Logic
        IPoolMemberNFT poolMemberNFT = IPoolMemberNFT(_canCallNFTHook(superToken));
        if (address(poolMemberNFT) != address(0)) {
            uint256 tokenId = poolMemberNFT.getTokenId(address(this), memberAddr);
            if (newUnits == 0) {
                if (poolMemberNFT.poolMemberDataByTokenId(tokenId).member != address(0)) {
                    poolMemberNFT.onDelete(address(this), memberAddr);
                }
            } else {
                // if not minted, we mint a new pool member nft
                if (poolMemberNFT.poolMemberDataByTokenId(tokenId).member == address(0)) {
                    poolMemberNFT.onCreate(address(this), memberAddr);
                } else {
                    // if minted, we update the pool member nft
                    poolMemberNFT.onUpdate(address(this), memberAddr);
                }
            }
        }
    }

    function _updateMemberUnits(address memberAddr, uint128 newUnits) internal returns (bool) {
        // @note normally we keep the sanitization in the external functions, but here
        // this is used in both updateMemberUnits and transfer
        if (GDA.isPool(superToken, memberAddr)) revert SUPERFLUID_POOL_NO_POOL_MEMBERS();
        if (memberAddr == address(0)) revert SUPERFLUID_POOL_NO_ZERO_ADDRESS();

        uint32 time = uint32(ISuperfluid(superToken.getHost()).getNow());
        Time t = Time.wrap(time);
        Unit wrappedUnits = toSemanticMoneyUnit(newUnits);

        PDPoolIndex memory pdPoolIndex = poolIndexDataToPDPoolIndex(_index);
        MemberData memory memberData = _membersData[memberAddr];
        PDPoolMember memory pdPoolMember = _memberDataToPDPoolMember(memberData);

        uint128 oldUnits = memberData.ownedUnits;

        PDPoolMemberMU memory mu = PDPoolMemberMU(pdPoolIndex, pdPoolMember);

        // update pool's disconnected units
        if (!GDA.isMemberConnected(ISuperfluidPool(address(this)), memberAddr)) {
            _shiftDisconnectedUnits(wrappedUnits - mu.m.owned_units, Value.wrap(0), t);
        }

        // update pool member's units
        {
            BasicParticle memory p;
            (pdPoolIndex, pdPoolMember, p) = mu.pool_member_update(p, wrappedUnits, t);
            _index = _pdPoolIndexToPoolIndexData(pdPoolIndex);
            int256 claimedValue = _membersData[memberAddr].claimedValue;
            _membersData[memberAddr] = _pdPoolMemberToMemberData(pdPoolMember, claimedValue);
            assert(GDA.appendIndexUpdateByPool(superToken, p, t));
        }
        emit MemberUnitsUpdated(superToken, memberAddr, oldUnits, newUnits);

        _handlePoolMemberNFT(memberAddr, newUnits);

        return true;
    }

    function _claimAll(address memberAddr, uint32 time) internal returns (int256 amount) {
        amount = getClaimable(memberAddr, time);
        assert(GDA.poolSettleClaim(superToken, memberAddr, (amount)));
        _membersData[memberAddr].claimedValue += amount;

        emit DistributionClaimed(superToken, memberAddr, amount, _membersData[memberAddr].claimedValue);
    }

    /// @inheritdoc ISuperfluidPool
    function claimAll() external returns (bool) {
        return claimAll(msg.sender);
    }

    /// @inheritdoc ISuperfluidPool
    function claimAll(address memberAddr) public returns (bool) {
        bool isConnected = GDA.isMemberConnected(ISuperfluidPool(address(this)), memberAddr);
        uint32 time = uint32(ISuperfluid(superToken.getHost()).getNow());
        int256 claimedAmount = _claimAll(memberAddr, time);
        if (!isConnected) {
            _shiftDisconnectedUnits(Unit.wrap(0), Value.wrap(claimedAmount), Time.wrap(time));
        }

        return true;
    }

    function operatorSetIndex(PDPoolIndex calldata index) external onlyGDA returns (bool) {
        _index = _pdPoolIndexToPoolIndexData(index);

        return true;
    }

    // WARNING for operators: it is undefined behavior if member is already connected or disconnected
    function operatorConnectMember(address memberAddr, bool doConnect, uint32 time) external onlyGDA returns (bool) {
        int256 claimedAmount = _claimAll(memberAddr, time);
        int128 units = uint256(_getUnits(memberAddr)).toInt256().toInt128();
        if (doConnect) {
            _shiftDisconnectedUnits(Unit.wrap(-units), Value.wrap(claimedAmount), Time.wrap(time));
        } else {
            _shiftDisconnectedUnits(Unit.wrap(units), Value.wrap(0), Time.wrap(time));
        }
        return true;
    }

    function _shiftDisconnectedUnits(Unit shiftUnits, Value claimedAmount, Time t) internal {
        PDPoolIndex memory pdPoolIndex = poolIndexDataToPDPoolIndex(_index);
        PDPoolMember memory disconnectedMembers = _memberDataToPDPoolMember(_disconnectedMembers);
        PDPoolMemberMU memory mu = PDPoolMemberMU(pdPoolIndex, disconnectedMembers);
        mu = mu.settle(t);
        mu.m.owned_units = mu.m.owned_units + shiftUnits;
        // offset the claimed amount from the settled value if any
        mu.m._settled_value = mu.m._settled_value - claimedAmount;
        _disconnectedMembers = _pdPoolMemberToMemberData(mu.m, 0);
    }

    modifier onlyGDA() {
        if (msg.sender != address(GDA)) revert SUPERFLUID_POOL_NOT_GDA();
        _;
    }
}
