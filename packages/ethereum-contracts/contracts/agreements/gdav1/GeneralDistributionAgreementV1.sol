// SPDX-License-Identifier: AGPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.23;

import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";

import { ISuperfluid, ISuperfluidGovernance, IAccessControl } from "../../interfaces/superfluid/ISuperfluid.sol";
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
import { ISuperfluidPool } from "../../interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { SlotsBitmapLibrary } from "../../libs/SlotsBitmapLibrary.sol";
import { SolvencyHelperLibrary } from "../../libs/SolvencyHelperLibrary.sol";
import { AgreementBase, ISuperAgreement } from "../AgreementBase.sol";
import { AgreementLibrary } from "../AgreementLibrary.sol";
import { GDAv1StorageLib, GDAv1StorageReader, GDAv1StorageWriter } from "./GDAv1StorageLayout.sol";


/**
 * @title General Distribution Agreement
 * @author Superfluid
 */
contract GeneralDistributionAgreementV1 is AgreementBase, TokenMonad, IGeneralDistributionAgreementV1 {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SemanticMoney for BasicParticle;
    using GDAv1StorageReader for ISuperfluidToken;
    using GDAv1StorageWriter for ISuperfluidToken;

    address public constant SLOTS_BITMAP_LIBRARY_ADDRESS = address(SlotsBitmapLibrary);

    address public constant SUPERFLUID_POOL_DEPLOYER_ADDRESS = address(SuperfluidPoolDeployerLibrary);

    // @dev The max number of slots which can be used for connecting pools on behalf of a member (per token)
    uint32 public constant MAX_POOL_AUTO_CONNECT_SLOTS = 4;

    // @dev The ACL role owned by this contract, used to persist autoconnect permissions for accounts
    bytes32 constant public ACL_POOL_CONNECT_EXCLUSIVE_ROLE = keccak256("ACL_POOL_CONNECT_EXCLUSIVE_ROLE");

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

    //////////////////////////////////////////////////////////////////////////////////////////////////////
    // ISuperAgreement interface
    //////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ISuperAgreement
    function realtimeBalanceOf(ISuperfluidToken token, address account, uint256 time)
        public
        view
        override
        returns (int256 rtb, uint256 buf, uint256 owedBuffer)
    {
        GDAv1StorageLib.AccountData memory accountData = token.getAccountData(this, account);

        if (token.isPool(this, account)) {
            rtb = ISuperfluidPool(account).getDisconnectedBalance(uint32(time));
        } else {
            rtb = Value.unwrap(GDAv1StorageLib
                               .getUniversalIndexFromAccountData(accountData)
                               .rtb(Time.wrap(uint32(time))));
        }

        int256 totalConnectedFromPools;
        {
            (uint32[] memory slotIds, bytes32[] memory pidList) = _listPoolConnectionIds(token, account);
            for (uint256 i = 0; i < slotIds.length; ++i) {
                address pool = address(uint160(uint256(pidList[i])));
                _assertPoolConnectivity(token, account, ISuperfluidPool(pool));
                totalConnectedFromPools += SuperfluidPool(pool).getUnsettledValue(account, uint32(time));
            }
        }
        rtb += totalConnectedFromPools;

        buf = uint256(accountData.totalBuffer.toInt256()); // upcasting to uint256 is safe
        owedBuffer = 0;
    }

    function _assertPoolConnectivity(ISuperfluidToken token, address account, ISuperfluidPool pool) internal view
    {
        (bool exist, GDAv1StorageLib.PoolConnectivity memory poolConnectivity) =
            token.getPoolConnectivity(this, account, pool);
        assert(exist);
        assert(poolConnectivity.pool == pool);
    }

    /// @dev Use block.timestamp for realtimeBalanceOf
    function realtimeBalanceOfNow(ISuperfluidToken token, address account)
        external
        view
        returns (int256 availableBalance, uint256 buffer, uint256 owedBuffer, uint256 timestamp)
    {
        (availableBalance, buffer, owedBuffer) = realtimeBalanceOf(token, account, block.timestamp);
        timestamp = block.timestamp;
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////////
    // IGeneralDistributionAgreementV1 interface
    //////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IGeneralDistributionAgreementV1
    function getNetFlow(ISuperfluidToken token, address account) external view override returns (int96 netFlowRate) {
        netFlowRate = int256(FlowRate.unwrap(_getUIndex(abi.encode(token), account).flow_rate())).toInt96();

        if (token.isPool(this, account)) {
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
        GDAv1StorageLib.FlowInfo memory data = token.getDistributionFlowInfo(this, from, to);
        return data.flowRate;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function getFlow(ISuperfluidToken token, address from, ISuperfluidPool to)
        external
        view
        override
        returns (uint256 lastUpdated, int96 flowRate, uint256 deposit)
    {
        GDAv1StorageLib.FlowInfo memory data = token.getDistributionFlowInfo(this, from, to);
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
        GDAv1StorageLib.AccountData memory accountData = token.getAccountData(this, account);
        timestamp = accountData.settledAt;
        flowRate = accountData.flowRate;
        deposit = accountData.totalBuffer;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function estimateFlowDistributionActualFlowRate(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool to,
        int96 requestedFlowRate
    ) external view override returns (int96 actualFlowRate, int96 totalDistributionFlowRate) {
        bytes memory eff = abi.encode(token);
        bytes32 distributionFlowHash = GDAv1StorageLib.getFlowDistributionHash(from, to);

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
        PoolConfig calldata config,
        PoolERC20Metadata memory poolERC20Metadata
    ) internal returns (ISuperfluidPool pool) {
        // @note ensure if token and admin are the same that nothing funky happens with echidna
        if (admin == address(0)) revert GDA_NO_ZERO_ADDRESS_ADMIN();
        if (token.isPool(this, admin)) revert GDA_ADMIN_CANNOT_BE_POOL();

        pool = ISuperfluidPool(
            address(
                SuperfluidPoolDeployerLibrary.deploy(
                    address(superfluidPoolBeacon), admin, token, config, poolERC20Metadata
                )
            )
        );

        token.setIsPoolFlag(pool);

        SuperfluidPoolDeployerLibrary.mintPoolAdminNFT(token, pool);

        emit PoolCreated(token, admin, pool);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function createPool(ISuperfluidToken token, address admin, PoolConfig calldata config)
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
        PoolConfig calldata config,
        PoolERC20Metadata memory poolERC20Metadata
    ) external override returns (ISuperfluidPool pool) {
        return _createPool(token, admin, config, poolERC20Metadata);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function updateMemberUnits(
        ISuperfluidPool untrustedPool,
        address memberAddress,
        uint128 newUnits,
        bytes calldata ctx
    )
        external
        override
        returns (bytes memory newCtx)
    {
        ISuperfluidToken token = untrustedPool.superToken();
        address msgSender = AgreementLibrary.authorizeTokenAccess(token, ctx).msgSender;

        // Only the admin can update member units here
        if (msgSender != untrustedPool.admin()) {
            revert GDA_NOT_POOL_ADMIN();
        }
        newCtx = ctx;

        // NOTE: In GDA.appendIndexUpdateByPool, it checks whether pool is created by the token.
        untrustedPool.updateMemberUnits(memberAddress, newUnits);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function claimAll(ISuperfluidPool untrustedPool, address memberAddress, bytes calldata ctx)
        external
        override
        returns (bytes memory newCtx)
    {
        ISuperfluidToken token = untrustedPool.superToken();
        AgreementLibrary.authorizeTokenAccess(token, ctx);
        newCtx = ctx;

        // NOTE: In GDA.poolSettleClaim, it checks whether pool is created by the token.
        untrustedPool.claimAll(memberAddress);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function connectPool(ISuperfluidPool pool, bytes calldata ctx)
        external
        override
        returns (bytes memory newCtx)
    {
        newCtx = ctx;
        _setPoolConnectionFor(pool, address(0), true /* doConnect */, ctx);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function tryConnectPoolFor(ISuperfluidPool pool, address memberAddr, bytes calldata ctx)
        external
        override
        returns (bool success, bytes memory newCtx)
    {
        newCtx = ctx;

        // NOTE: We do not allow a pool to connect to another pool.
        if (memberAddr == address(0) || pool.superToken().isPool(this, memberAddr)) {
            revert GDA_CANNOT_CONNECT_POOL();
        }

        // check if the member has opted out of autoconnect
        IAccessControl simpleACL = ISuperfluid(_host).getSimpleACL();
        if (simpleACL.hasRole(ACL_POOL_CONNECT_EXCLUSIVE_ROLE, memberAddr)) {
            success = false;
        } else {
            success = _setPoolConnectionFor(pool, memberAddr, true /* doConnect */, ctx);
        }
    }

    function setConnectPermission(bool allow) external override {
        IAccessControl simpleACL = ISuperfluid(_host).getSimpleACL();
        if (!allow) {
            simpleACL.grantRole(ACL_POOL_CONNECT_EXCLUSIVE_ROLE, msg.sender);
        } else {
            simpleACL.revokeRole(ACL_POOL_CONNECT_EXCLUSIVE_ROLE, msg.sender);
        }
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function disconnectPool(ISuperfluidPool pool, bytes calldata ctx) external override returns (bytes memory newCtx) {
        newCtx = ctx;
        _setPoolConnectionFor(pool, address(0), false /* doConnect */, ctx);
    }

    // @note memberAddr has override semantics - if set to address(0), it will be set to the msgSender
    function _setPoolConnectionFor(
        ISuperfluidPool pool,
        address memberAddr,
        bool doConnect,
        bytes memory ctx
    )
        internal
        returns (bool success)
    {
        ISuperfluidToken token = pool.superToken();
        // TODO: convert to modifier `poolIsTrustedByItsSuperToken(pool)`
        if (!token.isPool(this, address(pool))) {
            revert GDA_ONLY_SUPER_TOKEN_POOL();
        }
        ISuperfluid.Context memory currentContext = AgreementLibrary.authorizeTokenAccess(token, ctx);

        bool autoConnectForOtherMember = false;
        if (memberAddr == address(0)) {
            memberAddr = currentContext.msgSender;
        } else {
            autoConnectForOtherMember = true;
        }

        bool isConnected = token.isPoolMemberConnected(this, pool, memberAddr);

        if (doConnect != isConnected) {
            if (doConnect) {
                if (autoConnectForOtherMember) {
                    // check if we're below the slot limit for autoconnect
                   uint256 nUsedSlots = SlotsBitmapLibrary.countUsedSlots(
                        token, memberAddr, _POOL_SUBS_BITMAP_STATE_SLOT_ID
                    );
                    if (nUsedSlots >= MAX_POOL_AUTO_CONNECT_SLOTS) {
                        return false;
                    }
                }

                uint32 poolSlotId = _findAndFillPoolConnectionsBitmap(
                    token, memberAddr, bytes32(uint256(uint160(address(pool))))
                );

                token.createPoolConnectivity
                    (memberAddr, GDAv1StorageLib.PoolConnectivity({ slotId: poolSlotId, pool: pool }));
            } else {
                (, GDAv1StorageLib.PoolConnectivity memory poolConnectivity) =
                    token.getPoolConnectivity(this, memberAddr, pool);
                token.deletePoolConnectivity(memberAddr, pool);

                _clearPoolConnectionsBitmap(token, memberAddr, poolConnectivity.slotId);
            }

            assert(
                SuperfluidPool(address(pool)).operatorConnectMember(
                    memberAddr, doConnect, uint32(currentContext.timestamp)
                )
            );

            // NOTE: similar to Transfer, we cannot tell if it is done through tryConnect or regular connect.
            emit PoolConnectionUpdated(token, pool, memberAddr, doConnect, currentContext.userData);
        }

        return true;
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function isMemberConnected(ISuperfluidPool pool, address member)
        external view override
        returns (bool)
    {
        // NOTE: this function is complete, in that even for invalid pools, it will always return false.
        //
        // Retrospectively, it may be more helpful to the developers if this function is non-complete, and always revert
        // on invalid pool.
        return pool.superToken().isPoolMemberConnected(this, pool, member);
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

        // TODO: convert to modifier `poolIsTrustedByItsSuperToken(pool)`
        if (
            token.isPool(this, address(pool)) == false ||
            // Note: we do not support multi-tokens pools
            pool.superToken() != token)
        {
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
        // TODO: convert to modifier `poolIsTrustedByItsSuperToken(pool)`
        if (
            token.isPool(this, address(pool)) == false ||
            // Note: we do not support multi-tokens pools
            pool.superToken() != token)
        {
            revert GDA_ONLY_SUPER_TOKEN_POOL();
        }
        if (requestedFlowRate < 0) {
            revert GDA_NO_NEGATIVE_FLOW_RATE();
        }

        _StackVars_DistributeFlow memory flowVars;
        {
            flowVars.currentContext = AgreementLibrary.authorizeTokenAccess(token, ctx);
            flowVars.distributionFlowHash = GDAv1StorageLib.getFlowDistributionHash(from, pool);
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
                        // TODO: GeneralDistributionAgreementV1Storage may offer an function that reads only 1 word.
                        liquidationData.signedTotalGDADeposit = token.getAccountData(this, from).totalBuffer.toInt256();
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

    function _adjustBuffer
        (ISuperfluidToken token,
         address pool,
         address from,
         bytes32 flowHash, // cached result of: GDAv1StorageLib.getFlowDistributionHash(from, pool)
         FlowRate newFlowRate
        )
        internal
    {
        // NOTE: the caller to guarantee that the token and pool are mutually trusted.

        // not using oldFlowRate in this model
        // surprising effect: reducing flow rate may require more buffer when liquidation_period adjusted upward
        ISuperfluidGovernance gov = ISuperfluidGovernance(ISuperfluid(_host).getGovernance());
        uint256 minimumDeposit =
            gov.getConfigAsUint256(ISuperfluid(msg.sender), ISuperfluidToken(token), SUPERTOKEN_MINIMUM_DEPOSIT_KEY);

        (uint256 liquidationPeriod,) = SolvencyHelperLibrary.decode3PsData(ISuperfluid(_host), ISuperfluidToken(token));

        GDAv1StorageLib.FlowInfo memory flowDistributionData = token.getFlowInfoByFlowHash(this, flowHash);

        // @note downcasting from uint256 -> uint32 for liquidation period
        Value newBufferAmount = newFlowRate.mul(Time.wrap(uint32(liquidationPeriod)));

        if (Value.unwrap(newBufferAmount).toUint256() < minimumDeposit && FlowRate.unwrap(newFlowRate) > 0) {
            newBufferAmount = Value.wrap(minimumDeposit.toInt256());
        }

        Value bufferDelta = newBufferAmount - Value.wrap(uint256(flowDistributionData.buffer).toInt256());

        token.setFlowInfoByFlowHash(flowHash,
                                    GDAv1StorageLib.FlowInfo({
                                        lastUpdated: uint32(block.timestamp),
                                        flowRate: int256(FlowRate.unwrap(newFlowRate)).toInt96(),
                                        buffer: uint256(Value.unwrap(newBufferAmount)) // upcast to uint256 is safe
                                        })
                                   );

        GDAv1StorageLib.AccountData memory accountData = token.getAccountData(this, from);
        // new buffer
        accountData.totalBuffer = (accountData.totalBuffer.toInt256() + Value.unwrap(bufferDelta)).toUint256();
        token.setTotalBuffer(from, accountData.totalBuffer);

        emit BufferAdjusted(
            ISuperfluidToken(token),
            ISuperfluidPool(pool),
            from,
            Value.unwrap(bufferDelta),
            Value.unwrap(newBufferAmount).toUint256(),
            accountData.totalBuffer
        );
    }

    //
    // Solvency
    //

    /// @inheritdoc IGeneralDistributionAgreementV1
    function isPatricianPeriodNow(ISuperfluidToken token, address account)
        external
        view
        override
        returns (bool isCurrentlyPatricianPeriod, uint256 timestamp)
    {
        timestamp = ISuperfluid(_host).getNow();
        isCurrentlyPatricianPeriod = isPatricianPeriod(token, account, timestamp);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
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
            token.getAccountData(this, account).totalBuffer.toInt256(),
            liquidationPeriod,
            patricianPeriod
        );
    }

    function _makeLiquidationPayouts(_StackVars_Liquidation memory data) internal {
        GDAv1StorageLib.FlowInfo memory flowDistributionData =
            data.token.getFlowInfoByFlowHash(this, data.distributionFlowHash);
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

    //
    // pool info and operators
    //

    /// @inheritdoc IGeneralDistributionAgreementV1
    function getPoolAdjustmentFlowInfo(ISuperfluidPool pool)
        external
        view
        override
        returns (address recipient, bytes32 flowHash, int96 flowRate)
    {
        return _getPoolAdjustmentFlowInfo(abi.encode(pool.superToken()), address(pool));
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function isPool(ISuperfluidToken token, address account) external view override returns (bool) {
        return token.isPool(this, account);
    }

    /// @inheritdoc IGeneralDistributionAgreementV1
    function getPoolAdjustmentFlowRate(address pool) external view override returns (int96) {
        ISuperfluidToken token = ISuperfluidPool(pool).superToken();
        return int256(FlowRate.unwrap(_getPoolAdjustmentFlowRate(abi.encode(token), pool))).toInt96();
    }

    function _getPoolAdjustmentFlowInfo(bytes memory eff, address pool)
        internal view
        returns (address adjustmentRecipient, bytes32 flowHash, int96 flowRate)
    {
        // pool admin is always the adjustment recipient
        adjustmentRecipient = ISuperfluidPool(pool).admin();
        flowHash = GDAv1StorageLib.getPoolAdjustmentFlowHash(pool, adjustmentRecipient);
        return (adjustmentRecipient, flowHash, int256(FlowRate.unwrap(_getFlowRate(eff, flowHash))).toInt96());
    }

    function _setPoolAdjustmentFlowRate(bytes memory eff, address pool, bool doShiftFlow, FlowRate flowRate, Time t)
        internal
        returns (bytes memory)
    {
        // @note should this also always be
        address adjustmentRecipient = ISuperfluidPool(pool).admin();
        bytes32 adjustmentFlowHash = GDAv1StorageLib.getPoolAdjustmentFlowHash(pool, adjustmentRecipient);

        if (doShiftFlow) {
            flowRate = flowRate + _getFlowRate(eff, adjustmentFlowHash);
        }
        return _doFlow(eff, pool, adjustmentRecipient, adjustmentFlowHash, flowRate, t);
    }

    //
    // Pool-only operations
    // Can only be called (`msg.sender`) by legitimate pool contracts.
    // If `token` is legitimate, `token.isPool()` can return true only if the pool was created by this agreement.
    // "false positives" (does not revert for illegitimate caller) could occur if `token`:
    // 1. is lying (claims the pool was registered by this agreement when it was not)
    // or
    // 2. is not associated to the same host (and agreements).
    // In both cases, pre-conditions are not met and no state this agreement is responsible for can be manipulated.

    function appendIndexUpdateByPool(ISuperfluidToken token, BasicParticle memory p, Time t)
        external
        returns (bool)
    {
        address poolAddress = msg.sender;

        // TODO: convert to modifier `poolIsTrustedByItsSuperToken(pool)`
        if (
            token.isPool(this, msg.sender) == false ||
            ISuperfluidPool(poolAddress).superToken() != token
        ) {
            revert GDA_ONLY_SUPER_TOKEN_POOL();
        }

        bytes memory eff = abi.encode(token);
        _setUIndex(eff, msg.sender, _getUIndex(eff, poolAddress).mappend(p));
        _setPoolAdjustmentFlowRate(eff, poolAddress, true, /* doShift? */ p.flow_rate(), t);
        return true;
    }

    // succeeds only if `msg.sender` is a pool trusted by `token`
    function poolSettleClaim(ISuperfluidToken token, address claimRecipient, int256 amount)
        external
        returns (bool)
    {
        address poolAddress = msg.sender;

        // TODO: convert to modifier `poolIsTrustedByItsSuperToken(pool)`
        if (
            token.isPool(this, msg.sender) == false ||
            ISuperfluidPool(poolAddress).superToken() != token
        ) {
            revert GDA_ONLY_SUPER_TOKEN_POOL();
        }

        _doShift(abi.encode(token), poolAddress, claimRecipient, Value.wrap(amount));
        return true;
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////////
    // TokenMonad interface
    //////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc TokenMonad
    function _getUIndex(bytes memory eff, address owner)
        internal view
        override
        returns (BasicParticle memory uIndex)
    {
        ISuperfluidToken token = ISuperfluidToken(abi.decode(eff, (address)));
        GDAv1StorageLib.AccountData memory accountData = token.getAccountData(this, owner);
        uIndex = GDAv1StorageLib.getUniversalIndexFromAccountData(accountData);
    }

    /// @inheritdoc TokenMonad
    function _setUIndex(bytes memory eff, address owner, BasicParticle memory uIndex)
        internal
        override
        returns (bytes memory)
    {
        ISuperfluidToken token = ISuperfluidToken(abi.decode(eff, (address)));
        token.setUniversalIndex(owner, uIndex);
        return eff;
    }

    /// @inheritdoc TokenMonad
    function _getPDPIndex(
        bytes memory, // eff,
        address pool
    )
        internal view
        override
        returns (PDPoolIndex memory)
    {
        SuperfluidPool.PoolIndexData memory data = SuperfluidPool(pool).poolOperatorGetIndex();
        return poolIndexDataToPDPoolIndex(data);
    }

    /// @inheritdoc TokenMonad
    function _setPDPIndex(bytes memory eff, address pool, PDPoolIndex memory p)
        internal
        override
        returns (bytes memory)
    {
        assert(SuperfluidPool(pool).operatorSetIndex(p));
        return eff;
    }

    /// @inheritdoc TokenMonad
    function _getFlowRate(bytes memory eff, bytes32 flowHash)
        internal view
        override
        returns (FlowRate)
    {
        ISuperfluidToken token = ISuperfluidToken(abi.decode(eff, (address)));
        GDAv1StorageLib.FlowInfo memory data = token.getFlowInfoByFlowHash(this, flowHash);
        return FlowRate.wrap(data.flowRate);
    }

    /// @inheritdoc TokenMonad
    function _setFlowInfo(
        bytes memory eff,
        bytes32 flowHash,
        address, // from,
        address, // to,
        FlowRate newFlowRate,
        FlowRate // flowRateDelta
    )
        internal
        override
        returns (bytes memory)
    {
        ISuperfluidToken token = ISuperfluidToken(abi.decode(eff, (address)));
        GDAv1StorageLib.FlowInfo memory flowInfo = token.getFlowInfoByFlowHash(this, flowHash);

        token.setFlowInfoByFlowHash(flowHash,
                                    GDAv1StorageLib.FlowInfo({
                                        lastUpdated: uint32(block.timestamp),
                                        flowRate: int256(FlowRate.unwrap(newFlowRate)).toInt96(),
                                        buffer: flowInfo.buffer
                                        })
                                   );

        return eff;
    }

    /// @inheritdoc TokenMonad
    function _getPoolAdjustmentFlowRate(bytes memory eff, address pool)
        internal view
        override
        returns (FlowRate flowRate)
    {
        (,, int96 rawFlowRate) = _getPoolAdjustmentFlowInfo(eff, pool);
        flowRate = FlowRate.wrap(int128(rawFlowRate)); // upcasting to int128 is safe
    }

    /// @inheritdoc TokenMonad
    function _setPoolAdjustmentFlowRate(bytes memory eff, address pool, FlowRate flowRate, Time t)
        internal
        override
        returns (bytes memory)
    {
        return _setPoolAdjustmentFlowRate(eff, pool, false, /* doShift? */ flowRate, t);
    }


    //////////////////////////////////////////////////////////////////////////////////////////////////////
    // Pool Subscription SlotsBitmap
    //////////////////////////////////////////////////////////////////////////////////////////////////////

    /*
     *
     * ### SlotsBitmap Data
     *
     * slotId           = _POOL_SUBS_BITMAP_STATE_SLOT_ID or 1
     * msg.sender       = address of GDAv1
     * account          = context.msgSender
     * Slots Bitmap Data Slot stores a bitmap of the slots that are "enabled" for a pool member.
     *
     * ### Pool Connections Data Slot Id Start
     *
     * slotId (start)   = _POOL_CONNECTIONS_DATA_STATE_SLOT_ID_START or 1 << 128
     * msg.sender       = address of GDAv1
     * account          = context.msgSender
     * Pool Connections Data Slot Id Start indicates the starting slot for where we begin to store the pools that a
     * pool member is a part of.
     */

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
