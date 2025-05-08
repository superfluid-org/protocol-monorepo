// SPDX-License-Identifier: AGPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.23;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ISuperfluid, ISuperfluidGovernance } from "../../interfaces/superfluid/ISuperfluid.sol";
import {
    BasicParticle,
    PDPoolIndex,
    SemanticMoney,
    Value,
    Time,
    FlowRate
} from "@superfluid-finance/solidity-semantic-money/src/SemanticMoney.sol";
import { TokenMonad } from "@superfluid-finance/solidity-semantic-money/src/TokenMonad.sol";
import { poolIndexDataToPDPoolIndex, SuperfluidPool } from "./SuperfluidPool.sol";
import { SuperfluidPoolDeployerLibrary } from "./SuperfluidPoolDeployerLibrary.sol";
import {
    IGeneralDistributionAgreementV1,
    PoolConfig,
    PoolERC20Metadata
} from "../../interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import { SuperfluidUpgradeableBeacon } from "../../upgradability/SuperfluidUpgradeableBeacon.sol";
import { ISuperfluidToken } from "../../interfaces/superfluid/ISuperfluidToken.sol";
import { ISuperToken } from "../../interfaces/superfluid/ISuperToken.sol";
import { IPoolAdminNFT } from "../../interfaces/agreements/gdav1/IPoolAdminNFT.sol";
import { ISuperfluidPool } from "../../interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { SlotsBitmapLibrary } from "../../libs/SlotsBitmapLibrary.sol";
import { SolvencyHelperLibrary } from "../../libs/SolvencyHelperLibrary.sol";
import { AgreementBase } from "../AgreementBase.sol";
import { AgreementLibrary } from "../AgreementLibrary.sol";


/**
 * @title General Distribution Agreement
 * @author Superfluid
 * @notice
 *
 * Storage Layout Notes
 * Agreement State
 *
 * Universal Index Data
 * slotId           = _UNIVERSAL_INDEX_STATE_SLOT_ID or 0
 * msg.sender       = address of GDAv1
 * account          = context.msgSender
 * Universal Index Data stores a Basic Particle for an account as well as the total buffer and
 * whether the account is a pool or not.
 *
 * SlotsBitmap Data
 * slotId           = _POOL_SUBS_BITMAP_STATE_SLOT_ID or 1
 * msg.sender       = address of GDAv1
 * account          = context.msgSender
 * Slots Bitmap Data Slot stores a bitmap of the slots that are "enabled" for a pool member.
 *
 * Pool Connections Data Slot Id Start
 * slotId (start)   = _POOL_CONNECTIONS_DATA_STATE_SLOT_ID_START or 1 << 128 or 340282366920938463463374607431768211456
 * msg.sender       = address of GDAv1
 * account          = context.msgSender
 * Pool Connections Data Slot Id Start indicates the starting slot for where we begin to store the pools that a
 * pool member is a part of.
 *
 *
 * Agreement Data
 * NOTE The Agreement Data slot is calculated with the following function:
 * keccak256(abi.encode("AgreementData", agreementClass, agreementId))
 * agreementClass       = address of GDAv1
 * agreementId          = DistributionFlowId | PoolMemberId
 *
 * DistributionFlowId   =
 * keccak256(abi.encode(block.chainid, "distributionFlow", from, pool))
 * DistributionFlowId stores FlowDistributionData between a sender (from) and pool.
 *
 * PoolMemberId         =
 * keccak256(abi.encode(block.chainid, "poolMember", member, pool))
 * PoolMemberId stores PoolMemberData for a member at a pool.
 */
contract GeneralDistributionAgreementV1 is AgreementBase, TokenMonad, IGeneralDistributionAgreementV1 {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SemanticMoney for BasicParticle;

    struct UniversalIndexData {
        int96 flowRate;
        uint32 settledAt;
        uint256 totalBuffer;
        bool isPool;
        int256 settledValue;
    }

    struct PoolMemberData {
        address pool;
        uint32 poolID; // the slot id in the pool's subs bitmap
    }

    struct FlowDistributionData {
        uint32 lastUpdated;
        int96 flowRate;
        uint256 buffer; // stored as uint96
    }

    address public constant SLOTS_BITMAP_LIBRARY_ADDRESS = address(SlotsBitmapLibrary);

    address public constant SUPERFLUID_POOL_DEPLOYER_ADDRESS = address(SuperfluidPoolDeployerLibrary);

    /// @dev Universal Index state slot id for storing universal index data
    uint256 private constant _UNIVERSAL_INDEX_STATE_SLOT_ID = 0;
    /// @dev Pool member state slot id for storing subs bitmap
    uint256 private constant _POOL_SUBS_BITMAP_STATE_SLOT_ID = 1;
    /// @dev Pool member state slot id starting point for pool connections
    uint256 private constant _POOL_CONNECTIONS_DATA_STATE_SLOT_ID_START = 1 << 128;
    /// @dev SuperToken minimum deposit key
    bytes32 private constant SUPERTOKEN_MINIMUM_DEPOSIT_KEY =
        keccak256("org.superfluid-finance.superfluid.superTokenMinimumDeposit");

    SuperfluidUpgradeableBeacon public immutable superfluidPoolBeacon;

    constructor(ISuperfluid host, SuperfluidUpgradeableBeacon superfluidPoolBeacon_) AgreementBase(address(host)) {
        superfluidPoolBeacon = superfluidPoolBeacon_;
    }

    function realtimeBalanceOf(ISuperfluidToken token, address account, uint256 time)
        public
        view
        override
        returns (int256 rtb, uint256 buf, uint256 owedBuffer)
    {
        UniversalIndexData memory universalIndexData = _getUIndexData(abi.encode(token), account);

        if (_isPool(token, account)) {
            rtb = ISuperfluidPool(account).getDisconnectedBalance(uint32(time));
        } else {
            rtb = Value.unwrap(_getBasicParticleFromUIndex(universalIndexData).rtb(Time.wrap(uint32(time))));
        }

        int256 fromPools;
        {
            (uint32[] memory slotIds, bytes32[] memory pidList) = _listPoolConnectionIds(token, account);
            for (uint256 i = 0; i < slotIds.length; ++i) {
                address pool = address(uint160(uint256(pidList[i])));
                (bool exist, PoolMemberData memory poolMemberData) =
                    _getPoolMemberData(token, account, ISuperfluidPool(pool));
                assert(exist);
                assert(poolMemberData.pool == pool);
                fromPools += ISuperfluidPool(pool).getClaimable(account, uint32(time));
            }
        }
        rtb += fromPools;

        buf = uint256(universalIndexData.totalBuffer.toInt256()); // upcasting to uint256 is safe
        owedBuffer = 0;
    }

    /// @dev ISuperAgreement.realtimeBalanceOf implementation
    function realtimeBalanceOfNow(ISuperfluidToken token, address account)
        external
        view
        returns (int256 availableBalance, uint256 buffer, uint256 owedBuffer, uint256 timestamp)
    {
        (availableBalance, buffer, owedBuffer) = realtimeBalanceOf(token, account, block.timestamp);
        timestamp = block.timestamp;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function getNetFlow(ISuperfluidToken token, address account) external view override returns (int96 netFlowRate) {
        netFlowRate = int256(FlowRate.unwrap(_getUIndex(abi.encode(token), account).flow_rate())).toInt96();

        if (_isPool(token, account)) {
            netFlowRate += ISuperfluidPool(account).getTotalDisconnectedFlowRate();
        }

        {
            (uint32[] memory slotIds, bytes32[] memory pidList) = _listPoolConnectionIds(token, account);
            for (uint256 i = 0; i < slotIds.length; ++i) {
                ISuperfluidPool pool = ISuperfluidPool(address(uint160(uint256(pidList[i]))));
                netFlowRate += pool.getMemberFlowRate(account);
            }
        }
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function getFlowRate(ISuperfluidToken token, address from, ISuperfluidPool to)
        external
        view
        override
        returns (int96)
    {
        (, FlowDistributionData memory data) = _getFlowDistributionData(token, _getFlowDistributionHash(from, to));
        return data.flowRate;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function getFlow(ISuperfluidToken token, address from, ISuperfluidPool to)
        external
        view
        override
        returns (uint256 lastUpdated, int96 flowRate, uint256 deposit)
    {
        (, FlowDistributionData memory data) = _getFlowDistributionData(token, _getFlowDistributionHash(from, to));
        lastUpdated = data.lastUpdated;
        flowRate = data.flowRate;
        deposit = data.buffer;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function getAccountFlowInfo(ISuperfluidToken token, address account)
        external
        view
        override
        returns (uint256 timestamp, int96 flowRate, uint256 deposit)
    {
        UniversalIndexData memory universalIndexData = _getUIndexData(abi.encode(token), account);
        timestamp = universalIndexData.settledAt;
        flowRate = universalIndexData.flowRate;
        deposit = universalIndexData.totalBuffer;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function estimateFlowDistributionActualFlowRate(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool to,
        int96 requestedFlowRate
    ) external view override returns (int96 actualFlowRate, int96 totalDistributionFlowRate) {
        bytes memory eff = abi.encode(token);
        bytes32 distributionFlowHash = _getFlowDistributionHash(from, to);

        BasicParticle memory fromUIndexData = _getUIndex(eff, from);

        PDPoolIndex memory pdpIndex = _getPDPIndex("", address(to));

        FlowRate oldFlowRate = _getFlowRate(eff, distributionFlowHash);
        FlowRate newActualFlowRate;
        FlowRate oldDistributionFlowRate = pdpIndex.flow_rate();
        FlowRate newDistributionFlowRate;
        FlowRate flowRateDelta = FlowRate.wrap(requestedFlowRate) - oldFlowRate;
        FlowRate currentAdjustmentFlowRate = _getPoolAdjustmentFlowRate(eff, address(to));

        Time t = Time.wrap(uint32(block.timestamp));
        (fromUIndexData, pdpIndex, newDistributionFlowRate) =
            fromUIndexData.shift_flow2b(pdpIndex, flowRateDelta + currentAdjustmentFlowRate, t);
        newActualFlowRate =
            oldFlowRate + (newDistributionFlowRate - oldDistributionFlowRate) - currentAdjustmentFlowRate;

        actualFlowRate = int256(FlowRate.unwrap(newActualFlowRate)).toInt96();
        totalDistributionFlowRate = int256(FlowRate.unwrap(newDistributionFlowRate)).toInt96();

        if (actualFlowRate < 0) {
            actualFlowRate = 0;
        }
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function estimateDistributionActualAmount(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool to,
        uint256 requestedAmount
    ) external view override returns (uint256 actualAmount) {
        bytes memory eff = abi.encode(token);

        Value actualDistributionAmount;
        (,, actualDistributionAmount) =
            _getUIndex(eff, from).shift2b(_getPDPIndex("", address(to)), Value.wrap(requestedAmount.toInt256()));

        actualAmount = uint256(Value.unwrap(actualDistributionAmount));
    }

    function _createPool(
        ISuperfluidToken token,
        address admin,
        PoolConfig memory config,
        PoolERC20Metadata memory poolERC20Metadata
    ) internal returns (ISuperfluidPool pool) {
        // @note ensure if token and admin are the same that nothing funky happens with echidna
        if (admin == address(0)) revert GDA_NO_ZERO_ADDRESS_ADMIN();
        if (_isPool(token, admin)) revert GDA_ADMIN_CANNOT_BE_POOL();

        pool = ISuperfluidPool(
            address(
                SuperfluidPoolDeployerLibrary.deploy(
                    address(superfluidPoolBeacon), admin, token, config, poolERC20Metadata
                )
            )
        );

        // @note We utilize the storage slot for Universal Index State
        // to store whether an account is a pool or not
        bytes32[] memory data = new bytes32[](1);
        data[0] = bytes32(uint256(1));
        token.updateAgreementStateSlot(address(pool), _UNIVERSAL_INDEX_STATE_SLOT_ID, data);

        IPoolAdminNFT poolAdminNFT = IPoolAdminNFT(_getPoolAdminNFTAddress(token));

        if (address(poolAdminNFT) != address(0)) {
            poolAdminNFT.mint(address(pool));
        }

        emit PoolCreated(token, admin, pool);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function createPool(ISuperfluidToken token, address admin, PoolConfig memory config)
        external
        override
        returns (ISuperfluidPool pool)
    {
        return _createPool(
            token,
            admin,
            config,
            PoolERC20Metadata("", "", 0) // use defaults specified by the implementation contract
        );
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function createPoolWithCustomERC20Metadata(
        ISuperfluidToken token,
        address admin,
        PoolConfig memory config,
        PoolERC20Metadata memory poolERC20Metadata
    ) external override returns (ISuperfluidPool pool) {
        return _createPool(token, admin, config, poolERC20Metadata);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function updateMemberUnits(ISuperfluidPool pool, address memberAddress, uint128 newUnits, bytes calldata ctx)
        external
        override
        returns (bytes memory newCtx)
    {
        // Only the admin can update member units here
        if (AgreementLibrary.authorizeTokenAccess(pool.superToken(), ctx).msgSender != pool.admin()) {
            revert GDA_NOT_POOL_ADMIN();
        }
        newCtx = ctx;

        pool.updateMemberUnits(memberAddress, newUnits);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function claimAll(ISuperfluidPool pool, address memberAddress, bytes calldata ctx)
        external
        override
        returns (bytes memory newCtx)
    {
        AgreementLibrary.authorizeTokenAccess(pool.superToken(), ctx);
        newCtx = ctx;

        pool.claimAll(memberAddress);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function connectPool(ISuperfluidPool pool, bytes calldata ctx) external override returns (bytes memory newCtx) {
        return connectPool(pool, true, ctx);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function disconnectPool(ISuperfluidPool pool, bytes calldata ctx) external override returns (bytes memory newCtx) {
        return connectPool(pool, false, ctx);
    }

    // @note setPoolConnection function naming
    function connectPool(ISuperfluidPool pool, bool doConnect, bytes calldata ctx)
        public
        returns (bytes memory newCtx)
    {
        ISuperfluidToken token = pool.superToken();
        ISuperfluid.Context memory currentContext = AgreementLibrary.authorizeTokenAccess(token, ctx);
        address msgSender = currentContext.msgSender;
        newCtx = ctx;
        bool isConnected = _isMemberConnected(token, address(pool), msgSender);
        if (doConnect != isConnected) {
            assert(
                SuperfluidPool(address(pool)).operatorConnectMember(
                    msgSender, doConnect, uint32(currentContext.timestamp)
                )
            );

            if (doConnect) {
                uint32 poolSlotID =
                    _findAndFillPoolConnectionsBitmap(token, msgSender, bytes32(uint256(uint160(address(pool)))));

                // malicious token can reenter here
                // external call to untrusted contract
                // what sort of boundary can we trust
                token.createAgreement(
                    _getPoolMemberHash(msgSender, pool),
                    _encodePoolMemberData(PoolMemberData({ poolID: poolSlotID, pool: address(pool) }))
                );
            } else {
                (, PoolMemberData memory poolMemberData) = _getPoolMemberData(token, msgSender, pool);
                token.terminateAgreement(_getPoolMemberHash(msgSender, pool), 1);

                _clearPoolConnectionsBitmap(token, msgSender, poolMemberData.poolID);
            }

            emit PoolConnectionUpdated(token, pool, msgSender, doConnect, currentContext.userData);
        }
    }

    function _isMemberConnected(ISuperfluidToken token, address pool, address member) internal view returns (bool) {
        (bool exist,) = _getPoolMemberData(token, member, ISuperfluidPool(pool));
        return exist;
    }

    function isMemberConnected(ISuperfluidPool pool, address member) external view override returns (bool) {
        return _isMemberConnected(pool.superToken(), address(pool), member);
    }

    function appendIndexUpdateByPool(ISuperfluidToken token, BasicParticle memory p, Time t) external returns (bool) {
        if (_isPool(token, msg.sender) == false) {
            revert GDA_ONLY_SUPER_TOKEN_POOL();
        }
        bytes memory eff = abi.encode(token);
        _setUIndex(eff, msg.sender, _getUIndex(eff, msg.sender).mappend(p));
        _setPoolAdjustmentFlowRate(eff, msg.sender, true, /* doShift? */ p.flow_rate(), t);
        return true;
    }

    function poolSettleClaim(ISuperfluidToken superToken, address claimRecipient, int256 amount)
        external
        returns (bool)
    {
        if (_isPool(superToken, msg.sender) == false) {
            revert GDA_ONLY_SUPER_TOKEN_POOL();
        }

        // _poolSettleClaim()
        _doShift(abi.encode(superToken), msg.sender, claimRecipient, Value.wrap(amount));
        return true;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function distribute(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool pool,
        uint256 requestedAmount,
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        ISuperfluid.Context memory currentContext = AgreementLibrary.authorizeTokenAccess(token, ctx);

        newCtx = ctx;

        if (_isPool(token, address(pool)) == false ||
            // Note: we do not support multi-tokens pools
            pool.superToken() != token) {
            revert GDA_ONLY_SUPER_TOKEN_POOL();
        }

        // you cannot distribute if admin is not equal to the ctx.msgSender
        if (!pool.distributionFromAnyAddress()) {
            if (pool.admin() != currentContext.msgSender) {
                revert GDA_DISTRIBUTE_FROM_ANY_ADDRESS_NOT_ALLOWED();
            }
        }

        // the from address must be the same as the ctx.msgSender
        // there is no ACL support
        if (from != currentContext.msgSender) {
            revert GDA_DISTRIBUTE_FOR_OTHERS_NOT_ALLOWED();
        }

        (, Value actualAmount) = _doDistributeViaPool(
            abi.encode(token), currentContext.msgSender, address(pool), Value.wrap(requestedAmount.toInt256())
        );

        if (token.isAccountCriticalNow(from)) {
            revert GDA_INSUFFICIENT_BALANCE();
        }

        // TODO: tokens are moving from sender => pool, including a transfer event makes sense here
        // trigger from the supertoken contract - @note this is possible since solc 0.8.21

        emit InstantDistributionUpdated(
            token,
            pool,
            from,
            currentContext.msgSender,
            requestedAmount,
            uint256(Value.unwrap(actualAmount)), // upcast from int256 -> uint256 is safe
            currentContext.userData
        );
    }

    // solhint-disable-next-line contract-name-camelcase
    struct _StackVars_DistributeFlow {
        ISuperfluid.Context currentContext;
        bytes32 distributionFlowHash;
        FlowRate oldFlowRate;
    }

    // solhint-disable-next-line contract-name-camelcase
    struct _StackVars_Liquidation {
        ISuperfluidToken token;
        int256 availableBalance;
        address sender;
        bytes32 distributionFlowHash;
        int256 signedTotalGDADeposit;
        address liquidator;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function distributeFlow(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool pool,
        int96 requestedFlowRate,
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        if (_isPool(token, address(pool)) == false ||
            // Note: we do not support multi-tokens pools
            pool.superToken() != token) {
            revert GDA_ONLY_SUPER_TOKEN_POOL();
        }
        if (requestedFlowRate < 0) {
            revert GDA_NO_NEGATIVE_FLOW_RATE();
        }

        _StackVars_DistributeFlow memory flowVars;
        {
            flowVars.currentContext = AgreementLibrary.authorizeTokenAccess(token, ctx);
            flowVars.distributionFlowHash = _getFlowDistributionHash(from, pool);
            flowVars.oldFlowRate = _getFlowRate(abi.encode(token), flowVars.distributionFlowHash);
        }

        newCtx = ctx;

        // we must check if the requestedFlowRate is greater than 0 here
        // otherwise we will block liquidators from closing streams in pools
        // where the pool config has distributionFromAnyAddress set to false
        if (requestedFlowRate > 0 && !pool.distributionFromAnyAddress()) {
            if (pool.admin() != flowVars.currentContext.msgSender) {
                revert GDA_DISTRIBUTE_FROM_ANY_ADDRESS_NOT_ALLOWED();
            }
        }

        (, FlowRate actualFlowRate, FlowRate newDistributionFlowRate) = _doDistributeFlowViaPool(
            abi.encode(token),
            from,
            address(pool),
            flowVars.distributionFlowHash,
            FlowRate.wrap(requestedFlowRate),
            Time.wrap(uint32(flowVars.currentContext.timestamp))
        );

        // handle distribute flow on behalf of someone else
        // @note move to internal maybe
        {
            if (from != flowVars.currentContext.msgSender) {
                if (requestedFlowRate > 0) {
                    // @note no ACL support for now
                    // revert if trying to distribute on behalf of others
                    revert GDA_DISTRIBUTE_FOR_OTHERS_NOT_ALLOWED();
                } else {
                    // liquidation case, requestedFlowRate == 0
                    (int256 availableBalance,,) = token.realtimeBalanceOf(from, flowVars.currentContext.timestamp);
                    // StackVarsLiquidation used to handle good ol' stack too deep
                    _StackVars_Liquidation memory liquidationData;
                    {
                        liquidationData.token = token;
                        liquidationData.sender = from;
                        liquidationData.liquidator = flowVars.currentContext.msgSender;
                        liquidationData.distributionFlowHash = flowVars.distributionFlowHash;
                        liquidationData.signedTotalGDADeposit =
                            _getUIndexData(abi.encode(token), from).totalBuffer.toInt256();
                        liquidationData.availableBalance = availableBalance;
                    }
                    // closing stream on behalf of someone else: liquidation case
                    if (availableBalance < 0) {
                        _makeLiquidationPayouts(liquidationData);
                    } else {
                        revert GDA_NON_CRITICAL_SENDER();
                    }
                }
            }
        }

        {
            _adjustBuffer(token, address(pool), from, flowVars.distributionFlowHash, actualFlowRate);
        }

        // ensure sender has enough balance to execute transaction
        if (from == flowVars.currentContext.msgSender) {
            (int256 availableBalance,,) = token.realtimeBalanceOf(from, flowVars.currentContext.timestamp);
            // if from == msg.sender
            if (requestedFlowRate > 0 && availableBalance < 0) {
                revert GDA_INSUFFICIENT_BALANCE();
            }
        }

        {
            (address adjustmentFlowRecipient,, int96 adjustmentFlowRate) =
                _getPoolAdjustmentFlowInfo(abi.encode(token), address(pool));

            emit FlowDistributionUpdated(
                token,
                pool,
                from,
                flowVars.currentContext.msgSender,
                int256(FlowRate.unwrap(flowVars.oldFlowRate)).toInt96(),
                int256(FlowRate.unwrap(actualFlowRate)).toInt96(),
                int256(FlowRate.unwrap(newDistributionFlowRate)).toInt96(),
                adjustmentFlowRecipient,
                adjustmentFlowRate,
                flowVars.currentContext.userData
            );
        }
    }

    function _getPoolAdminNFTAddress(ISuperfluidToken token) internal view returns (address poolAdminNFTAddress) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) =
            address(token).staticcall(abi.encodeWithSelector(ISuperToken.POOL_ADMIN_NFT.selector));

        if (success) {
            // @note We are aware this may revert if a Custom SuperToken's
            // POOL_ADMIN_NFT does not return data that can be
            // decoded to an address. This would mean it was intentionally
            // done by the creator of the Custom SuperToken logic and is
            // fully expected to revert in that case as the author desired.
            poolAdminNFTAddress = abi.decode(data, (address));
        }
    }

    function _makeLiquidationPayouts(_StackVars_Liquidation memory data) internal {
        (, FlowDistributionData memory flowDistributionData) =
            _getFlowDistributionData(ISuperfluidToken(data.token), data.distributionFlowHash);
        int256 signedSingleDeposit = flowDistributionData.buffer.toInt256();

        bool isCurrentlyPatricianPeriod;

        {
            (uint256 liquidationPeriod, uint256 patricianPeriod) =
                SolvencyHelperLibrary.decode3PsData(ISuperfluid(_host), data.token);
            isCurrentlyPatricianPeriod = SolvencyHelperLibrary.isPatricianPeriod(
                data.availableBalance, data.signedTotalGDADeposit, liquidationPeriod, patricianPeriod
            );
        }

        int256 totalRewardLeft = data.availableBalance + data.signedTotalGDADeposit;

        // critical case
        if (totalRewardLeft >= 0) {
            int256 rewardAmount = (signedSingleDeposit * totalRewardLeft) / data.signedTotalGDADeposit;
            data.token.makeLiquidationPayoutsV2(
                data.distributionFlowHash,
                abi.encode(2, isCurrentlyPatricianPeriod ? 0 : 1),
                data.liquidator,
                isCurrentlyPatricianPeriod,
                data.sender,
                rewardAmount.toUint256(),
                rewardAmount * -1
            );
        } else {
            int256 rewardAmount = signedSingleDeposit;
            // bailout case
            data.token.makeLiquidationPayoutsV2(
                data.distributionFlowHash,
                abi.encode(2, 2),
                data.liquidator,
                false,
                data.sender,
                rewardAmount.toUint256(),
                totalRewardLeft * -1
            );
        }
    }

    function _adjustBuffer(ISuperfluidToken token, address pool, address from, bytes32 flowHash, FlowRate newFlowRate)
        internal
    {
        // not using oldFlowRate in this model
        // surprising effect: reducing flow rate may require more buffer when liquidation_period adjusted upward
        ISuperfluidGovernance gov = ISuperfluidGovernance(ISuperfluid(_host).getGovernance());
        uint256 minimumDeposit =
            gov.getConfigAsUint256(ISuperfluid(msg.sender), ISuperfluidToken(token), SUPERTOKEN_MINIMUM_DEPOSIT_KEY);

        (uint256 liquidationPeriod,) = SolvencyHelperLibrary.decode3PsData(ISuperfluid(_host), ISuperfluidToken(token));

        (, FlowDistributionData memory flowDistributionData) =
            _getFlowDistributionData(ISuperfluidToken(token), flowHash);

        // @note downcasting from uint256 -> uint32 for liquidation period
        Value newBufferAmount = newFlowRate.mul(Time.wrap(uint32(liquidationPeriod)));

        if (Value.unwrap(newBufferAmount).toUint256() < minimumDeposit && FlowRate.unwrap(newFlowRate) > 0) {
            newBufferAmount = Value.wrap(minimumDeposit.toInt256());
        }

        Value bufferDelta = newBufferAmount - Value.wrap(uint256(flowDistributionData.buffer).toInt256());

        {
            bytes32[] memory data = _encodeFlowDistributionData(
                FlowDistributionData({
                    lastUpdated: uint32(block.timestamp),
                    flowRate: int256(FlowRate.unwrap(newFlowRate)).toInt96(),
                    buffer: uint256(Value.unwrap(newBufferAmount)) // upcast to uint256 is safe
                 })
            );

            ISuperfluidToken(token).updateAgreementData(flowHash, data);
        }

        UniversalIndexData memory universalIndexData = _getUIndexData(abi.encode(token), from);
        universalIndexData.totalBuffer =
        // new buffer
         (universalIndexData.totalBuffer.toInt256() + Value.unwrap(bufferDelta)).toUint256();
        ISuperfluidToken(token).updateAgreementStateSlot(
            from, _UNIVERSAL_INDEX_STATE_SLOT_ID, _encodeUniversalIndexData(universalIndexData)
        );

        {
            emit BufferAdjusted(
                ISuperfluidToken(token),
                ISuperfluidPool(pool),
                from,
                Value.unwrap(bufferDelta),
                Value.unwrap(newBufferAmount).toUint256(),
                universalIndexData.totalBuffer
            );
        }
    }

    // Solvency Related Getters
    function isPatricianPeriodNow(ISuperfluidToken token, address account)
        external
        view
        override
        returns (bool isCurrentlyPatricianPeriod, uint256 timestamp)
    {
        timestamp = ISuperfluid(_host).getNow();
        isCurrentlyPatricianPeriod = isPatricianPeriod(token, account, timestamp);
    }

    function isPatricianPeriod(ISuperfluidToken token, address account, uint256 timestamp)
        public
        view
        override
        returns (bool)
    {
        (int256 availableBalance,,) = token.realtimeBalanceOf(account, timestamp);
        if (availableBalance >= 0) {
            return true;
        }

        (uint256 liquidationPeriod, uint256 patricianPeriod) =
            SolvencyHelperLibrary.decode3PsData(ISuperfluid(_host), token);

        return SolvencyHelperLibrary.isPatricianPeriod(
            availableBalance,
            _getUIndexData(abi.encode(token), account).totalBuffer.toInt256(),
            liquidationPeriod,
            patricianPeriod
        );
    }

    // Hash Getters

    function _getPoolMemberHash(address poolMember, ISuperfluidPool pool) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, "poolMember", poolMember, address(pool)));
    }

    function _getFlowDistributionHash(address from, ISuperfluidPool to) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, "distributionFlow", from, to));
    }

    function _getPoolAdjustmentFlowHash(address from, address to) internal view returns (bytes32) {
        // this will never be in conflict with other flow has types
        return keccak256(abi.encode(block.chainid, "poolAdjustmentFlow", from, to));
    }

    // # Universal Index operations
    //
    // Universal Index packing:
    // store buffer (96) and one bit to specify is pool in free
    // -------- ------------------ ------------------ ------------------ ------------------
    // WORD 1: |     flowRate     |     settledAt    |    totalBuffer   |      isPool      |
    // -------- ------------------ ------------------ ------------------ ------------------
    //         |        96b       |       32b        |       96b        |        32b       |
    // -------- ------------------ ------------------ ------------------ ------------------
    // WORD 2: |                                settledValue                               |
    // -------- ------------------ ------------------ ------------------ ------------------
    //         |                                    256b                                   |
    // -------- ------------------ ------------------ ------------------ ------------------

    function _encodeUniversalIndexData(BasicParticle memory p, uint256 buffer, bool isPool_)
        internal
        pure
        returns (bytes32[] memory data)
    {
        data = new bytes32[](2);
        data[0] = bytes32(
            (uint256(int256(FlowRate.unwrap(p.flow_rate()))) << 160) | (uint256(Time.unwrap(p.settled_at())) << 128)
                | (uint256(buffer.toUint96()) << 32) | (isPool_ ? 1 : 0)
        );
        data[1] = bytes32(uint256(Value.unwrap(p._settled_value)));
    }

    function _encodeUniversalIndexData(UniversalIndexData memory uIndexData)
        internal
        pure
        returns (bytes32[] memory data)
    {
        data = new bytes32[](2);
        data[0] = bytes32(
            (uint256(int256(uIndexData.flowRate)) << 160) | (uint256(uIndexData.settledAt) << 128)
                | (uint256(uIndexData.totalBuffer.toUint96()) << 32) | (uIndexData.isPool ? 1 : 0)
        );
        data[1] = bytes32(uint256(uIndexData.settledValue));
    }

    function _decodeUniversalIndexData(bytes32[] memory data)
        internal
        pure
        returns (bool exists, UniversalIndexData memory universalIndexData)
    {
        uint256 a = uint256(data[0]);
        uint256 b = uint256(data[1]);

        exists = a > 0 || b > 0;

        if (exists) {
            universalIndexData.flowRate = int96(int256(a >> 160) & int256(uint256(type(uint96).max)));
            universalIndexData.settledAt = uint32(uint256(a >> 128) & uint256(type(uint32).max));
            universalIndexData.totalBuffer = uint256(a >> 32) & uint256(type(uint96).max);
            universalIndexData.isPool = ((a << 224) >> 224) & 1 == 1;
            universalIndexData.settledValue = int256(b);
        }
    }

    function _getUIndexData(bytes memory eff, address owner)
        internal
        view
        returns (UniversalIndexData memory universalIndexData)
    {
        (, universalIndexData) = _decodeUniversalIndexData(
            ISuperfluidToken(abi.decode(eff, (address))).getAgreementStateSlot(
                address(this), owner, _UNIVERSAL_INDEX_STATE_SLOT_ID, 2
            )
        );
    }

    function _getBasicParticleFromUIndex(UniversalIndexData memory universalIndexData)
        internal
        pure
        returns (BasicParticle memory particle)
    {
        particle._flow_rate = FlowRate.wrap(universalIndexData.flowRate);
        particle._settled_at = Time.wrap(universalIndexData.settledAt);
        particle._settled_value = Value.wrap(universalIndexData.settledValue);
    }

    // TokenMonad virtual functions
    function _getUIndex(bytes memory eff, address owner) internal view override returns (BasicParticle memory uIndex) {
        (, UniversalIndexData memory universalIndexData) = _decodeUniversalIndexData(
            ISuperfluidToken(abi.decode(eff, (address))).getAgreementStateSlot(
                address(this), owner, _UNIVERSAL_INDEX_STATE_SLOT_ID, 2
            )
        );
        uIndex = _getBasicParticleFromUIndex(universalIndexData);
    }

    function _setUIndex(bytes memory eff, address owner, BasicParticle memory p)
        internal
        override
        returns (bytes memory)
    {
        UniversalIndexData memory universalIndexData = _getUIndexData(eff, owner);

        ISuperfluidToken(abi.decode(eff, (address))).updateAgreementStateSlot(
            owner,
            _UNIVERSAL_INDEX_STATE_SLOT_ID,
            _encodeUniversalIndexData(p, universalIndexData.totalBuffer, universalIndexData.isPool)
        );

        return eff;
    }

    function _getPDPIndex(
        bytes memory, // eff,
        address pool
    ) internal view override returns (PDPoolIndex memory) {
        SuperfluidPool.PoolIndexData memory data = SuperfluidPool(pool).poolOperatorGetIndex();
        return poolIndexDataToPDPoolIndex(data);
    }

    function _setPDPIndex(bytes memory eff, address pool, PDPoolIndex memory p)
        internal
        override
        returns (bytes memory)
    {
        assert(SuperfluidPool(pool).operatorSetIndex(p));

        return eff;
    }

    function _getFlowRate(bytes memory eff, bytes32 distributionFlowHash) internal view override returns (FlowRate) {
        (, FlowDistributionData memory data) =
            _getFlowDistributionData(ISuperfluidToken(abi.decode(eff, (address))), distributionFlowHash);
        return FlowRate.wrap(data.flowRate);
    }

    function _setFlowInfo(
        bytes memory eff,
        bytes32 flowHash,
        address, // from,
        address, // to,
        FlowRate newFlowRate,
        FlowRate // flowRateDelta
    ) internal override returns (bytes memory) {
        address token = abi.decode(eff, (address));
        (, FlowDistributionData memory flowDistributionData) =
            _getFlowDistributionData(ISuperfluidToken(token), flowHash);

        ISuperfluidToken(token).updateAgreementData(
            flowHash,
            _encodeFlowDistributionData(
                FlowDistributionData({
                    lastUpdated: uint32(block.timestamp),
                    flowRate: int256(FlowRate.unwrap(newFlowRate)).toInt96(),
                    buffer: flowDistributionData.buffer
                })
            )
        );

        return eff;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function getPoolAdjustmentFlowInfo(ISuperfluidPool pool)
        external
        view
        override
        returns (address recipient, bytes32 flowHash, int96 flowRate)
    {
        return _getPoolAdjustmentFlowInfo(abi.encode(pool.superToken()), address(pool));
    }

    function _getPoolAdjustmentFlowInfo(bytes memory eff, address pool)
        internal
        view
        returns (address adjustmentRecipient, bytes32 flowHash, int96 flowRate)
    {
        // pool admin is always the adjustment recipient
        adjustmentRecipient = ISuperfluidPool(pool).admin();
        flowHash = _getPoolAdjustmentFlowHash(pool, adjustmentRecipient);
        return (adjustmentRecipient, flowHash, int256(FlowRate.unwrap(_getFlowRate(eff, flowHash))).toInt96());
    }

    function _getPoolAdjustmentFlowRate(bytes memory eff, address pool)
        internal
        view
        override
        returns (FlowRate flowRate)
    {
        (,, int96 rawFlowRate) = _getPoolAdjustmentFlowInfo(eff, pool);
        flowRate = FlowRate.wrap(int128(rawFlowRate)); // upcasting to int128 is safe
    }

    function getPoolAdjustmentFlowRate(address pool) external view override returns (int96) {
        ISuperfluidToken token = ISuperfluidPool(pool).superToken();
        return int256(FlowRate.unwrap(_getPoolAdjustmentFlowRate(abi.encode(token), pool))).toInt96();
    }

    function _setPoolAdjustmentFlowRate(bytes memory eff, address pool, FlowRate flowRate, Time t)
        internal
        override
        returns (bytes memory)
    {
        return _setPoolAdjustmentFlowRate(eff, pool, false, /* doShift? */ flowRate, t);
    }

    function _setPoolAdjustmentFlowRate(bytes memory eff, address pool, bool doShiftFlow, FlowRate flowRate, Time t)
        internal
        returns (bytes memory)
    {
        // @note should this also always be
        address adjustmentRecipient = ISuperfluidPool(pool).admin();
        bytes32 adjustmentFlowHash = _getPoolAdjustmentFlowHash(pool, adjustmentRecipient);

        if (doShiftFlow) {
            flowRate = flowRate + _getFlowRate(eff, adjustmentFlowHash);
        }
        eff = _doFlow(eff, pool, adjustmentRecipient, adjustmentFlowHash, flowRate, t);
        return eff;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function isPool(ISuperfluidToken token, address account) external view override returns (bool) {
        return _isPool(token, account);
    }

    function _isPool(ISuperfluidToken token, address account) internal view returns (bool exists) {
        // @note see createPool, we retrieve the isPool bit from
        // UniversalIndex for this pool to determine whether the account
        // is a pool
        exists = (
            (uint256(token.getAgreementStateSlot(address(this), account, _UNIVERSAL_INDEX_STATE_SLOT_ID, 1)[0]) << 224)
                >> 224
        ) & 1 == 1;
    }

    // FlowDistributionData data packing:
    // -------- ---------- ------------- ---------- --------
    // WORD A: | reserved | lastUpdated | flowRate | buffer |
    // -------- ---------- ------------- ---------- --------
    //         |    32    |      32     |    96    |   96   |
    // -------- ---------- ------------- ---------- --------

    function _encodeFlowDistributionData(FlowDistributionData memory flowDistributionData)
        internal
        pure
        returns (bytes32[] memory data)
    {
        data = new bytes32[](1);
        data[0] = bytes32(
            (uint256(uint32(flowDistributionData.lastUpdated)) << 192)
                | (uint256(uint96(flowDistributionData.flowRate)) << 96) | uint256(flowDistributionData.buffer)
        );
    }

    function _decodeFlowDistributionData(uint256 data)
        internal
        pure
        returns (bool exist, FlowDistributionData memory flowDistributionData)
    {
        exist = data > 0;
        if (exist) {
            flowDistributionData.lastUpdated = uint32((data >> 192) & uint256(type(uint32).max));
            flowDistributionData.flowRate = int96(int256(data >> 96));
            flowDistributionData.buffer = uint96(data & uint256(type(uint96).max));
        }
    }

    function _getFlowDistributionData(ISuperfluidToken token, bytes32 distributionFlowHash)
        internal
        view
        returns (bool exist, FlowDistributionData memory flowDistributionData)
    {
        (exist, flowDistributionData) =
            _decodeFlowDistributionData(uint256(token.getAgreementData(address(this), distributionFlowHash, 1)[0]));
    }

    // PoolMemberData data packing:
    // -------- ---------- -------- -------------
    // WORD A: | reserved | poolID | poolAddress |
    // -------- ---------- -------- -------------
    //         |    64    |   32   |     160     |
    // -------- ---------- -------- -------------

    function _encodePoolMemberData(PoolMemberData memory poolMemberData)
        internal
        pure
        returns (bytes32[] memory data)
    {
        data = new bytes32[](1);
        data[0] = bytes32((uint256(uint32(poolMemberData.poolID)) << 160) | uint256(uint160(poolMemberData.pool)));
    }

    function _decodePoolMemberData(uint256 data)
        internal
        pure
        returns (bool exist, PoolMemberData memory poolMemberData)
    {
        exist = data > 0;
        if (exist) {
            poolMemberData.pool = address(uint160(data & uint256(type(uint160).max)));
            poolMemberData.poolID = uint32(data >> 160);
        }
    }

    function _getPoolMemberData(ISuperfluidToken token, address poolMember, ISuperfluidPool pool)
        internal
        view
        returns (bool exist, PoolMemberData memory poolMemberData)
    {
        (exist, poolMemberData) = _decodePoolMemberData(
            uint256(token.getAgreementData(address(this), _getPoolMemberHash(poolMember, pool), 1)[0])
        );
    }

    // SlotsBitmap Pool Data:
    function _findAndFillPoolConnectionsBitmap(ISuperfluidToken token, address poolMember, bytes32 poolID)
        private
        returns (uint32 slotId)
    {
        return SlotsBitmapLibrary.findEmptySlotAndFill(
            token, poolMember, _POOL_SUBS_BITMAP_STATE_SLOT_ID, _POOL_CONNECTIONS_DATA_STATE_SLOT_ID_START, poolID
        );
    }

    function _clearPoolConnectionsBitmap(ISuperfluidToken token, address poolMember, uint32 slotId) private {
        SlotsBitmapLibrary.clearSlot(token, poolMember, _POOL_SUBS_BITMAP_STATE_SLOT_ID, slotId);
    }

    function _listPoolConnectionIds(ISuperfluidToken token, address subscriber)
        private
        view
        returns (uint32[] memory slotIds, bytes32[] memory pidList)
    {
        (slotIds, pidList) = SlotsBitmapLibrary.listData(
            token, subscriber, _POOL_SUBS_BITMAP_STATE_SLOT_ID, _POOL_CONNECTIONS_DATA_STATE_SLOT_ID_START
        );
    }
}
