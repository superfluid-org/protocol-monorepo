// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@superfluid-finance/solidity-semantic-money/src/SemanticMoney.sol";

import { ERC1820RegistryCompiled } from "../../../../contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer} from "../../../../contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import { TestToken } from "../../../../contracts/utils/TestToken.sol";
import { SuperfluidUpgradeableBeacon } from "../../../../contracts/upgradability/SuperfluidUpgradeableBeacon.sol";
import { ISuperToken, SuperToken } from "../../../../contracts/superfluid/SuperToken.sol";
import { ISuperAgreement } from "../../../../contracts/interfaces/superfluid/ISuperAgreement.sol";
import {
    GeneralDistributionAgreementV1,
    PoolConfig,
    ISuperfluid, ISuperfluidPool, ISuperToken
} from "../../../../contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol";
import {
    GDAv1StorageLib, GDAv1StorageReader, GDAv1StorageWriter
} from "../../../../contracts/agreements/gdav1/GDAv1StorageLayout.sol";
import { ISuperfluidPool, SuperfluidPool } from "../../../../contracts/agreements/gdav1/SuperfluidPool.sol";
import { SuperTokenV1Library } from "../../../../contracts/apps/SuperTokenV1Library.sol";


/// @title GeneralDistributionAgreementV1 Property Tests
/// @author Superfluid
/// @notice This is a contract that runs property tests for the GDAv1
/// It involves testing the pure functions of the GDAv1 to ensure that we get
/// the expected output for a range of inputs.
contract GeneralDistributionAgreementV1Properties is GeneralDistributionAgreementV1, Test {
    using SuperTokenV1Library for ISuperToken;
    using GDAv1StorageReader for ISuperToken;
    using GDAv1StorageWriter for ISuperToken;

    SuperfluidFrameworkDeployer internal immutable sfDeployer;
    SuperfluidFrameworkDeployer.Framework internal sf;

    SuperfluidPool public currentPool;
    uint256 public liquidationPeriod;

    /// @dev The current underlying token being tested (applies only to wrapper super tokens)
    TestToken internal token;

    /// @dev The current super token being tested
    ISuperToken internal superToken;

    address public constant alice = address(0x420);

    constructor() GeneralDistributionAgreementV1(ISuperfluid(address(0)), SuperfluidUpgradeableBeacon(address(0))) {
        // deploy ERC1820 registry
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        sfDeployer = new SuperfluidFrameworkDeployer();
        sfDeployer.deployTestFramework();
        sf = sfDeployer.getFramework();

        (token, superToken) = sfDeployer.deployWrapperSuperToken("FTT", "FTT", 18, type(uint256).max, address(0));

        PoolConfig memory poolConfig =
            PoolConfig({ transferabilityForUnitsOwner: true, distributionFromAnyAddress: true });

        vm.startPrank(alice);
        currentPool = SuperfluidPool(address(sf.gda.createPool(superToken, alice, poolConfig)));
        vm.stopPrank();

        (liquidationPeriod,) = sf.governance.getPPPConfig(sf.host, superToken);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                GDA Setters/Getters Tests
    //////////////////////////////////////////////////////////////////////////*/
    // Universal Index Setters/Getters
    function testSetGetUIndex(address owner, uint32 settledAt, int96 flowRate, int256 settledValue) public {
        bytes memory eff = abi.encode(superToken);
        BasicParticle memory p = BasicParticle({
            _settled_at: Time.wrap(settledAt),
            _flow_rate: FlowRate.wrap(flowRate),
            _settled_value: Value.wrap(settledValue)
        });
        _setUIndex(eff, owner, p);
        BasicParticle memory setP = _getUIndex(eff, owner);

        assertEq(Time.unwrap(p._settled_at), Time.unwrap(setP._settled_at), "settledAt not equal");
        assertEq(FlowRate.unwrap(p._flow_rate), FlowRate.unwrap(setP._flow_rate), "flowRate not equal");
        assertEq(Value.unwrap(p._settled_value), Value.unwrap(setP._settled_value), "settledValue not equal");
    }

    function testSetGetUIndexData(address owner, uint32 settledAt, int96 flowRate, int256 settledValue) public {
        vm.assume(owner != address(currentPool));

        bytes memory eff = abi.encode(superToken);
        BasicParticle memory p = BasicParticle({
            _settled_at: Time.wrap(settledAt),
            _flow_rate: FlowRate.wrap(flowRate),
            _settled_value: Value.wrap(settledValue)
        });
        _setUIndex(eff, owner, p);
        GDAv1StorageLib.AccountData memory accountData = superToken.getAccountData(this, owner);

        assertEq(settledAt, accountData.settledAt, "settledAt not equal");
        assertEq(flowRate, accountData.flowRate, "flowRate not equal");
        assertEq(settledValue, accountData.settledValue, "settledValue not equal");
        assertEq(0, accountData.totalBuffer, "totalBuffer not equal");
        assertEq(false, accountData.isPool, "isPool not equal");
    }

    // Flow Distribution Data Setters/Getters
    function testSetGetFlowInfo(
        address from,
        ISuperfluidPool to,
        uint32 newFlowRate,
        uint96 newFlowRateDelta
    ) public {
        uint256 lastUpdated = block.timestamp;

        bytes32 flowHash = GDAv1StorageLib.getFlowDistributionHash(from, to);

        _setFlowInfo(
            abi.encode(superToken),
            flowHash,
            from,
            address(to),
            FlowRate.wrap(int128(uint128(newFlowRate))),
            FlowRate.wrap(int128(uint128(newFlowRateDelta)))
        );

        vm.warp(1000);
        GDAv1StorageLib.FlowInfo memory setFlowInfo = superToken.getFlowInfoByFlowHash(this, flowHash);

        assertEq(int96(uint96(newFlowRate)), setFlowInfo.flowRate, "flowRate not equal");

        assertEq(lastUpdated, setFlowInfo.lastUpdated, "lastUpdated not equal");

        assertEq(0, setFlowInfo.buffer, "buffer not equal");
        assertEq(
            int96(FlowRate.unwrap(_getFlowRate(abi.encode(superToken), flowHash))),
            int96(uint96(newFlowRate)),
            "_getFlowRate: flow rate not equal"
        );
        assertEq(
            int96(FlowRate.unwrap(_getFlowRate(abi.encode(superToken), flowHash))),
            int96(uint96(newFlowRate)),
            "getFlowRate: flow rate not equal"
        );
    }

    // Pool Connectivity Data Setters/Getters
    function testSetGetPoolConnectivity(address poolMember, ISuperfluidPool _pool, uint32 slotId) public {
        vm.assume(slotId > 0);
        vm.assume(address(_pool) != address(0));
        vm.assume(address(poolMember) != address(0));

        vm.startPrank(address(this));
        superToken.createPoolConnectivity
            (poolMember,
             GDAv1StorageLib.PoolConnectivity ({
                 slotId: slotId,
                 pool: _pool
                 })
            );
        vm.stopPrank();

        (bool exist, GDAv1StorageLib.PoolConnectivity memory setPoolConnectivity) =
            superToken.getPoolConnectivity(this, poolMember, _pool);

        assertEq(true, exist, "pool connectivity does not exist");
        assertEq(slotId, setPoolConnectivity.slotId, "slotId not equal");
        assertEq(address(_pool), address(setPoolConnectivity.pool), "pool not equal");
    }

    // Proportional Distribution Pool Index Setters/Getters
    function testSetGetPDPIndex(
        address owner,
        uint128 totalUnits,
        uint32 wrappedSettledAt,
        int96 wrappedFlowRate,
        int256 wrappedSettledValue
    ) public {
        vm.assume(owner != address(0));
        vm.assume(totalUnits < uint128(type(int128).max));
        bytes memory eff = abi.encode(superToken);
        PDPoolIndex memory pdpIndex = PDPoolIndex({
            total_units: Unit.wrap(int128(totalUnits)),
            _wrapped_particle: BasicParticle({
                _settled_at: Time.wrap(wrappedSettledAt),
                _flow_rate: FlowRate.wrap(wrappedFlowRate),
                _settled_value: Value.wrap(wrappedSettledValue)
            })
        });

        // we have to pretend to be the registered gda, not this testing contract
        vm.startPrank(address(sf.gda));
        _setPDPIndex(eff, address(currentPool), pdpIndex);
        vm.stopPrank();

        (PDPoolIndex memory setPdpIndex) = _getPDPIndex(new bytes(0), address(currentPool));

        assertEq(Unit.unwrap(pdpIndex.total_units), Unit.unwrap(setPdpIndex.total_units), "total units not equal");
        assertEq(
            Time.unwrap(pdpIndex._wrapped_particle._settled_at),
            Time.unwrap(setPdpIndex._wrapped_particle._settled_at),
            "settled at not equal"
        );
        assertEq(
            FlowRate.unwrap(pdpIndex._wrapped_particle._flow_rate),
            FlowRate.unwrap(setPdpIndex._wrapped_particle._flow_rate),
            "flow rate not equal"
        );
        assertEq(
            Value.unwrap(pdpIndex._wrapped_particle._settled_value),
            Value.unwrap(setPdpIndex._wrapped_particle._settled_value),
            "settled value not equal"
        );
    }

    function testEncodeUpdatedUniversalIndex(
        int96 flowRate,
        uint32 settledAt,
        int256 settledValue,
        uint96 totalBuffer,
        bool isPool
    ) pure public
    {
        GDAv1StorageLib.AccountData memory accountData =
            GDAv1StorageLib.AccountData({
                flowRate: 0,
                settledAt: 0,
                settledValue: 0,
                totalBuffer: totalBuffer,
                isPool: isPool
            });
        BasicParticle memory uIndex =
            BasicParticle({
                _flow_rate: FlowRate.wrap(flowRate),
                _settled_at: Time.wrap(settledAt),
                _settled_value: Value.wrap(settledValue)
            });

        bytes32[] memory encoded = GDAv1StorageLib.encodeUpdatedUniversalIndex(accountData, uIndex);
        GDAv1StorageLib.AccountData memory decoded = GDAv1StorageLib.decodeAccountData(encoded);

        assertEq(flowRate, decoded.flowRate, "flowRate not equal");
        assertEq(settledAt, decoded.settledAt, "settledAt not equal");
        assertEq(settledValue, decoded.settledValue, "settledValue not equal");
        assertEq(totalBuffer, decoded.totalBuffer, "totalBuffer not equal");
        assertEq(isPool, decoded.isPool, "isPool not equal");
    }

    function testEncodeUpdatedTotalBuffer(
        int96 flowRate,
        uint32 settledAt,
        uint96 totalBuffer,
        bool isPool
    ) public pure
    {
        GDAv1StorageLib.AccountData memory accountData =
            GDAv1StorageLib.AccountData({
                flowRate: flowRate,
                settledAt: settledAt,
                settledValue: 0,
                totalBuffer: 0,
                isPool: isPool
            });
        bytes32[] memory encoded = GDAv1StorageLib.encodeUpdatedTotalBuffer(accountData, totalBuffer);
        GDAv1StorageLib.AccountData memory decoded = GDAv1StorageLib.decodeAccountData(encoded);

        assertEq(flowRate, decoded.flowRate, "flowRate not equal");
        assertEq(settledAt, decoded.settledAt, "settledAt not equal");
        assertEq(totalBuffer, decoded.totalBuffer, "totalBuffer not equal");
        assertEq(isPool, decoded.isPool, "isPool not equal");
    }

    function testDecodeAccountData(GDAv1StorageLib.AccountData memory data)
        pure
        public
    {
        BasicParticle memory particle = GDAv1StorageLib.getUniversalIndexFromAccountData(data);
        assertEq(data.flowRate, int96(FlowRate.unwrap(particle._flow_rate)), "flowRate not equal");
        assertEq(data.settledAt, Time.unwrap(particle._settled_at), "settledAt not equal");
        assertEq(data.settledValue, Value.unwrap(particle._settled_value), "settledValue not equal");
    }

    function testEncodeDecodeFlowInfo(int96 flowRate, uint96 buffer) public view {
        vm.assume(flowRate >= 0);
        vm.assume(buffer >= 0);
        GDAv1StorageLib.FlowInfo memory original =
            GDAv1StorageLib.FlowInfo({
                flowRate: flowRate,
                lastUpdated: uint32(block.timestamp),
                buffer: buffer
            });
        bytes32[] memory encoded = GDAv1StorageLib.encodeFlowInfo(original);
        GDAv1StorageLib.FlowInfo memory decoded = GDAv1StorageLib.decodeFlowInfo(uint256(encoded[0]));

        assertEq(original.flowRate, decoded.flowRate, "flowRate not equal");
        assertEq(original.buffer, decoded.buffer, "buffer not equal");
        assertEq(original.lastUpdated, decoded.lastUpdated, "lastUpdated not equal");
    }

    function testEncodeDecodePoolConnectivity(address pool, uint32 slotId) public pure {
        vm.assume(pool != address(0));
        GDAv1StorageLib.PoolConnectivity memory original =
            GDAv1StorageLib.PoolConnectivity({ slotId: slotId, pool: ISuperfluidPool(pool) });
        bytes32[] memory encoded = GDAv1StorageLib.encodePoolConnectivity(original);
        (, GDAv1StorageLib.PoolConnectivity memory decoded) =
            GDAv1StorageLib.decodePoolConnectivity(uint256(encoded[0]));

        assertEq(original.slotId, decoded.slotId, "slotId not equal");
        assertEq(address(original.pool), address(decoded.pool), "pool not equal");
    }
}
