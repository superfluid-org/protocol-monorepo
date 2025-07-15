// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;
// open-zeppelin
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
// semantic-money
import {
    BasicParticle,
    Value,
    Time,
    FlowRate
} from "@superfluid-finance/solidity-semantic-money/src/SemanticMoney.sol";
// superfluid
import { ISuperfluidToken } from "../../interfaces/superfluid/ISuperfluidToken.sol";
import {
    IGeneralDistributionAgreementV1
} from "../../interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import { ISuperfluidPool } from "../../interfaces/agreements/gdav1/ISuperfluidPool.sol";


/* @title Storage layout library for the GDAv1.
 * @author Superfluid
 *
 * @notice Storage Layout Notes
 *
 * ## Agreement State
 *
 * ### Universal Index Data
 *
 * slotId           = 0 (ACCOUNT_DATA_STATE_SLOT_ID)
 * msg.sender       = address of GDAv1
 * account          = context.msgSender
 * Universal Index Data stores a Basic Particle for an account as well as the total buffer and
 * whether the account is a pool or not.
 *
 * ## Agreement Data
 *
 * NOTE The Agreement Data slot is calculated with the following function:
 * keccak256(abi.encode("AgreementData", agreementClass, agreementId))
 * agreementClass       = address of GDAv1
 * agreementId          = DistributionFlowId | PoolMemberId
 *
 * DistributionFlowId   =
 * keccak256(abi.encode(block.chainid, "distributionFlow", from, pool))
 * DistributionFlowId stores FlowInfo between a sender (from) and pool.
 *
 * PoolMemberId         =
 * keccak256(abi.encode(block.chainid, "poolMember", member, pool))
 * PoolMemberId stores PoolMemberData for a member at a pool.
 */
library GDAv1StorageLib {

    // # Account Data
    //
    // ## Data Packing
    //
    // Account data includes:
    // - Semantic universal index (a basic particle)
    // - buffer amount (96b)
    // - isPool flag
    //
    // --------+----------------+-----------------+------------------+----------------+--------------+
    // WORD 1: |    flowRate    |    settledAt    |   totalBuffer    |    (reserved)  |    isPool    |
    // --------+----------------+-----------------+------------------+----------------+--------------+
    //         |      96b       |       32b       |       96b        |       31b      |      1b      |
    // --------+----------------+-----------------+------------------+----------------+--------------+
    // WORD 2: |                              settledValue                                           |
    // -------- ----------------+------------------+------------------+------------------------------+
    //         |                                 256b                                                |
    // --------+----------------+------------------+------------------+------------------------------+

    /// @dev Agreement state slot id for account data.
    uint256 internal constant ACCOUNT_DATA_STATE_SLOT_ID = 0;

    /// @dev Account data struct.
    struct AccountData {
        int96 flowRate;
        uint32 settledAt;
        uint256 totalBuffer; // stored as uint96
        bool isPool;
        int256 settledValue;
    }

    /// @dev Update the universal index of the account data.
    function encodeUpdatedUniversalIndex(AccountData memory accountData, BasicParticle memory uIndex)
        internal
        pure
        returns (bytes32[] memory data)
    {
        data = new bytes32[](2);
        data[0] = bytes32(
            // FIXME: this allows negative flow rate, is it a problem?
            (uint256(int256(SafeCast.toInt96(FlowRate.unwrap(uIndex.flow_rate())))) << 160) |
            (uint256(SafeCast.toUint32(Time.unwrap(uIndex.settled_at()))) << 128) |
            (uint256(SafeCast.toUint96(accountData.totalBuffer)) << 32) |
            (accountData.isPool ? 1 : 0)
        );
        data[1] = bytes32(uint256(Value.unwrap(uIndex._settled_value)));
    }

    /// @dev Update the total buffer of the account data.
    function encodeUpdatedTotalBuffer(AccountData memory accountData, uint256 totalBuffer)
        internal
        pure
        returns (bytes32[] memory data)
    {
        data = new bytes32[](1);
        data[0] = bytes32(
            (uint256(int256(accountData.flowRate)) << 160) |
            (uint256(accountData.settledAt) << 128) |
            (uint256(SafeCast.toUint96(totalBuffer)) << 32) |
            (accountData.isPool ? 1 : 0)
        );
    }

    /// @dev Decode account data.
    function decodeAccountData(bytes32[] memory data)
        internal
        pure
        returns (AccountData memory accountData)
    {
        uint256 a = uint256(data[0]);

        if (a > 0) {
            accountData.flowRate = int96(int256(a >> 160) & int256(uint256(type(uint96).max)));
            accountData.settledAt = uint32(uint256(a >> 128) & uint256(type(uint32).max));
            accountData.totalBuffer = uint256(a >> 32) & uint256(type(uint96).max);
            accountData.isPool = a & 1 == 1;
        }

        // encodeUpdatedTotalBuffer only encodes the first word
        if (data.length >= 2) {
            uint256 b = uint256(data[1]);
            accountData.settledValue = int256(b);
        }
    }

    /// @dev Extract universal index from the decoded account data.
    function getUniversalIndexFromAccountData(AccountData memory accountData)
        internal
        pure
        returns (BasicParticle memory uIndex)
    {
        uIndex._flow_rate = FlowRate.wrap(accountData.flowRate);
        uIndex._settled_at = Time.wrap(accountData.settledAt);
        uIndex._settled_value = Value.wrap(accountData.settledValue);
    }

    // # Flow Info
    //
    // ## Data Packing
    //
    // --------+----------+-------------+----------+--------+
    // WORD A: | reserved | lastUpdated | flowRate | buffer |
    // --------+----------+-------------+----------+--------+
    //         |    32    |      32     |    96    |   96   |
    // --------+----------+-------------+----------+--------+

    /// @dev Flow info struct, for both distribution flow and adjustment flow.
    struct FlowInfo {
        uint32 lastUpdated;
        int96 flowRate;
        uint256 buffer; // stored as uint96
    }

    /// @dev Calculate flow hash for distribution flow.
    function getFlowDistributionHash(address from, ISuperfluidPool to) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, "distributionFlow", from, to));
    }

    /// @dev Calculate flow hash for adjustment flow.
    function getPoolAdjustmentFlowHash(address from, address to) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, "poolAdjustmentFlow", from, to));
    }

    /// @dev Encode flow info.
    function encodeFlowInfo(FlowInfo memory flowInfo)
        internal pure
        returns (bytes32[] memory data)
    {
        data = new bytes32[](1);
        data[0] = bytes32(
            (uint256(uint32(flowInfo.lastUpdated)) << 192) |
            (uint256(uint96(flowInfo.flowRate)) << 96) |
            uint256(flowInfo.buffer)
        );
    }

    /// @dev Decode flow info.
    function decodeFlowInfo(uint256 data)
        internal pure
        returns (FlowInfo memory flowDistributionData)
    {
        if (data > 0) {
            flowDistributionData.lastUpdated = uint32((data >> 192) & uint256(type(uint32).max));
            flowDistributionData.flowRate = int96(int256(data >> 96));
            flowDistributionData.buffer = uint96(data & uint256(type(uint96).max));
        }
    }

    // # Pool Member Data
    //
    // ## Data Packing
    //
    // --------+----------+--------+-------------+
    // WORD A: | reserved | poolId | poolAddress |
    // --------+----------+--------+-------------+
    //         |    64    |   32   |     160     |
    // --------+----------+--------+-------------+

    /// @dev Pool member data struct.
    struct PoolMemberData {
        uint32 poolId; // the slot id in the pool's subs bitmap
        address pool;
    }

    /// @dev Calculate pool member data hash for agreement data.
    function getPoolMemberHash(address poolMember, ISuperfluidPool pool) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, "poolMember", poolMember, address(pool)));
    }

    /// @dev Encode pool member data.
    function encodePoolMemberData(PoolMemberData memory poolMemberData)
        internal
        pure
        returns (bytes32[] memory data)
    {
        data = new bytes32[](1);
        data[0] = bytes32(
           (uint256(uint32(poolMemberData.poolId)) << 160) |
           uint256(uint160(poolMemberData.pool)));
    }

    /// @dev Decode pool member data.
    function decodePoolMemberData(uint256 data)
        internal
        pure
        returns (bool exist, PoolMemberData memory poolMemberData)
    {
        exist = data > 0;
        if (exist) {
            poolMemberData.poolId = uint32(data >> 160);
            poolMemberData.pool = address(uint160(data & uint256(type(uint160).max)));
        }
    }
}

/* @title Storage layout reader for the GDAv1.
 * @author Superfluid
 */
library GDAv1StorageReader {
    // Account Data

    /// @dev Get account data.
    function getAccountData(ISuperfluidToken token, IGeneralDistributionAgreementV1 gda, address owner)
        internal
        view
        returns (GDAv1StorageLib.AccountData memory accountData)
    {
        return GDAv1StorageLib.decodeAccountData(token.getAgreementStateSlot
            (address(gda), owner, GDAv1StorageLib.ACCOUNT_DATA_STATE_SLOT_ID, 2));
    }

    /// @dev returns true if the account is a pool
    function isPool(ISuperfluidToken token, IGeneralDistributionAgreementV1 gda, address account)
        internal
        view
        returns (bool)
    {
        uint256 a = uint256(token.getAgreementStateSlot
                            (address(gda), account, GDAv1StorageLib.ACCOUNT_DATA_STATE_SLOT_ID, 1)[0]);
        return a & 1 == 1;
    }

    // Flow Info

    /// @dev Get flow info by its flow hash.
    function getFlowInfoByFlowHash
        (ISuperfluidToken token,
         IGeneralDistributionAgreementV1 gda,
         bytes32 flowHash
        )
        internal view
        returns (GDAv1StorageLib.FlowInfo memory flowDistributionData)
    {
        uint256 data = uint256(token.getAgreementData(address(gda), flowHash, 1)[0]);
        return GDAv1StorageLib.decodeFlowInfo(data);
    }

    /// @dev Get flow info of a distribution flow.
    function getDistributionFlowInfo
        (ISuperfluidToken token,
         IGeneralDistributionAgreementV1 gda,
         address from,
         ISuperfluidPool to
        )
        internal view
        returns (GDAv1StorageLib.FlowInfo memory flowDistributionData)
    {
        return getFlowInfoByFlowHash(token, gda, GDAv1StorageLib.getFlowDistributionHash(from, to));
    }

    // Pool Member Data

    /// @dev Get pool member data.
    function getPoolMemberData
        (ISuperfluidToken token,
         IGeneralDistributionAgreementV1 gda,
         address poolMember,
         ISuperfluidPool pool
        )
        internal view
        returns (bool exist, GDAv1StorageLib.PoolMemberData memory poolMemberData)
    {
        bytes32 dataId = GDAv1StorageLib.getPoolMemberHash(poolMember, pool);
        uint256 data = uint256(token.getAgreementData(address(gda), dataId, 1)[0]);
        return GDAv1StorageLib.decodePoolMemberData(data);
    }

    /// @dev Check whether a pool member is connected.
    function isPoolMemberConnected
        (ISuperfluidToken token,
         IGeneralDistributionAgreementV1 gda,
         ISuperfluidPool pool,
         address member
        )
        internal view
        returns (bool)
    {
        (bool exist,) = getPoolMemberData(token, gda, member, pool);
        return exist;
    }
}


/* @title Storage layout writer for the GDAv1.
 * @author Superfluid
 * @dev Due to how agreement framework works, `address(this)` must be the GeneralDistributionAgreementV1 itself.
 */
library GDAv1StorageWriter {
    // AccountData

    /// @dev Set unviversal index of an account.
    function setUniversalIndex
        (ISuperfluidToken token,
         address owner,
         BasicParticle memory uIndex
        )
        internal
    {
        GDAv1StorageLib.AccountData memory accountData =
            GDAv1StorageReader.getAccountData(token, IGeneralDistributionAgreementV1(address(this)), owner);

        token.updateAgreementStateSlot(
            owner,
            GDAv1StorageLib.ACCOUNT_DATA_STATE_SLOT_ID,
            GDAv1StorageLib.encodeUpdatedUniversalIndex(accountData, uIndex)
        );
    }

    /// @dev Set is pool flag for a pool.
    function setIsPoolFlag(ISuperfluidToken token, ISuperfluidPool pool)
        internal
    {
        bytes32[] memory data = new bytes32[](1);
        data[0] = bytes32(uint256(1));
        token.updateAgreementStateSlot(address(pool), GDAv1StorageLib.ACCOUNT_DATA_STATE_SLOT_ID, data);
    }

    /// @dev Set total buffer field of an account.
    function setTotalBuffer
        (ISuperfluidToken token,
         address owner,
         uint256 totalBuffer
        )
        internal
    {
        GDAv1StorageLib.AccountData memory accountData =
            GDAv1StorageReader.getAccountData(token, IGeneralDistributionAgreementV1(address(this)), owner);

        token.updateAgreementStateSlot(
            owner,
            GDAv1StorageLib.ACCOUNT_DATA_STATE_SLOT_ID,
            GDAv1StorageLib.encodeUpdatedTotalBuffer(accountData, totalBuffer)
        );
    }

    // Flow Info

    /// @dev Set flow info.
    function setFlowInfoByFlowHash
        (ISuperfluidToken token,
         bytes32 flowHash,
         GDAv1StorageLib.FlowInfo memory flowInfo
        )
        internal
    {
        token.updateAgreementData(flowHash, GDAv1StorageLib.encodeFlowInfo(flowInfo));
    }

    // Pool Member Data

    /// @dev Create a pool membership.
    function createPoolMembership
        (ISuperfluidToken token,
         address poolMember,
         ISuperfluidPool pool,
         GDAv1StorageLib.PoolMemberData memory poolMemberData
        )
        internal
    {
        token.createAgreement
            (GDAv1StorageLib.getPoolMemberHash(poolMember, pool),
             GDAv1StorageLib.encodePoolMemberData(poolMemberData));
    }

    /// @dev Delete a pool membership.
    function deletePoolMembership
        (ISuperfluidToken token,
         address poolMember,
         ISuperfluidPool pool)
        internal
    {
        token.terminateAgreement(GDAv1StorageLib.getPoolMemberHash(poolMember, pool), 1);
    }
}
