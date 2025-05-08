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
    GeneralDistributionAgreementV1, ISuperfluid, ISuperfluidPool
} from "../../../../contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol";
import {
    IGeneralDistributionAgreementV1,
    PoolConfig
} from "../../../../contracts/interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import { ISuperfluidPool, SuperfluidPool } from "../../../../contracts/agreements/gdav1/SuperfluidPool.sol";
import { SuperTokenV1Library } from "../../../../contracts/apps/SuperTokenV1Library.sol";

/// @title GeneralDistributionAgreementV1 Property Tests
/// @author Superfluid
/// @notice This is a contract that runs property tests for the GDAv1
/// It involves testing the pure functions of the GDAv1 to ensure that we get
/// the expected output for a range of inputs.
contract GeneralDistributionAgreementV1Properties is GeneralDistributionAgreementV1, Test {
    using SuperTokenV1Library for ISuperToken;

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
        GeneralDistributionAgreementV1.UniversalIndexData memory setUIndexData = _getUIndexData(eff, owner);

        assertEq(settledAt, setUIndexData.settledAt, "settledAt not equal");
        assertEq(flowRate, setUIndexData.flowRate, "flowRate not equal");
        assertEq(settledValue, setUIndexData.settledValue, "settledValue not equal");
        assertEq(0, setUIndexData.totalBuffer, "totalBuffer not equal");
        assertEq(false, setUIndexData.isPool, "isPool not equal");
    }

    // Flow Distribution Data Setters/Getters
    function testSetGetFlowDistributionData(
        address from,
        ISuperfluidPool to,
        uint32 newFlowRate,
        uint96 newFlowRateDelta
    ) public {
        uint256 lastUpdated = block.timestamp;

        bytes32 flowHash = _getFlowDistributionHash(from, to);

        _setFlowInfo(
            abi.encode(superToken),
            flowHash,
            from,
            address(to),
            FlowRate.wrap(int128(uint128(newFlowRate))),
            FlowRate.wrap(int128(uint128(newFlowRateDelta)))
        );

        vm.warp(1000);

        (bool exist, FlowDistributionData memory setFlowDistributionData) =
            _getFlowDistributionData(superToken, flowHash);

        assertEq(true, exist, "flow distribution data does not exist");

        assertEq(int96(uint96(newFlowRate)), setFlowDistributionData.flowRate, "flowRate not equal");

        assertEq(lastUpdated, setFlowDistributionData.lastUpdated, "lastUpdated not equal");

        assertEq(0, setFlowDistributionData.buffer, "buffer not equal");
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

    // Pool Member Data Setters/Getters
    function testSetGetPoolMemberData(address poolMember, ISuperfluidPool _pool, uint32 poolID) public {
        vm.assume(poolID > 0);
        vm.assume(address(_pool) != address(0));
        vm.assume(address(poolMember) != address(0));
        bytes32 poolMemberId = _getPoolMemberHash(poolMember, _pool);

        vm.startPrank(address(this));
        superToken.updateAgreementData(
            poolMemberId,
            _encodePoolMemberData(PoolMemberData({ poolID: poolID, pool: address(_pool) }))
        );
        vm.stopPrank();

        (bool exist, PoolMemberData memory setPoolMemberData) = _getPoolMemberData(superToken, poolMember, _pool);

        assertEq(true, exist, "pool member data does not exist");
        assertEq(poolID, setPoolMemberData.poolID, "poolID not equal");
        assertEq(address(_pool), setPoolMemberData.pool, "pool not equal");
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

    // // Adjust Buffer => FlowDistributionData modified
    // function testAdjustBufferUpdatesFlowDistributionData(address from, int32 oldFlowRate, int32 newFlowRate) public {
    //     vm.assume(newFlowRate >= 0);

    //     bytes32 flowHash = _getFlowDistributionHash(from, currentPool);

    //     uint256 expectedBuffer = uint256(int256(newFlowRate)) * liquidationPeriod;
    //     _adjustBuffer(
    //         abi.encode(superToken),
    //         address(currentPool),
    //         from,
    //         flowHash,
    //         FlowRate.wrap(int128(oldFlowRate)),
    //         FlowRate.wrap(int128(newFlowRate))
    //     );

    //     (bool exist, IGeneralDistributionAgreementV1.FlowDistributionData memory flowDistributionData) =
    //         _getFlowDistributionData(superToken, flowHash);
    //     assertEq(exist, true, "flow distribution data does not exist");
    //     assertEq(flowDistributionData.buffer, expectedBuffer, "buffer not equal");
    //     assertEq(flowDistributionData.flowRate, int96(newFlowRate), "buffer not equal");
    //     assertEq(
    //         int96(FlowRate.unwrap(_getFlowRate(abi.encode(superToken), flowHash))),
    //         int96(newFlowRate),
    //         "_getFlowRate: flow rate not equal"
    //     );
    //     assertEq(
    //         sf.gda.getFlowRate(superToken, from, ISuperfluidPool(currentPool)),
    //         int96(newFlowRate),
    //         "getFlowRate: flow rate not equal"
    //     );
    // }

    // // Adjust Buffer => UniversalIndexData modified
    // function testAdjustBufferUpdatesUniversalIndexData(address from, int32 oldFlowRate, int32 newFlowRate) public {
    //     vm.assume(newFlowRate >= 0);

    //     uint256 bufferDelta = uint256(int256(newFlowRate)) * liquidationPeriod; // expected buffer == buffer delta
    //         // because of fresh state
    //     bytes32 flowHash = _getFlowDistributionHash(from, currentPool);
    //     GeneralDistributionAgreementV1.UniversalIndexData memory fromUindexDataBefore =
    //         _getUIndexData(abi.encode(superToken), from);
    //     _adjustBuffer(
    //         abi.encode(superToken),
    //         address(currentPool),
    //         from,
    //         flowHash,
    //         FlowRate.wrap(int128(oldFlowRate)),
    //         FlowRate.wrap(int128(newFlowRate))
    //     );

    //     GeneralDistributionAgreementV1.UniversalIndexData memory fromUindexDataAfter =
    //         _getUIndexData(abi.encode(superToken), from);

    //     assertEq(
    //         fromUindexDataBefore.totalBuffer + bufferDelta,
    //         fromUindexDataAfter.totalBuffer,
    //         "from total buffer not equal"
    //     );
    // }

    function testEncodeDecodeParticleInputUniversalIndexData(
        int96 flowRate,
        uint32 settledAt,
        int256 settledValue,
        uint96 totalBuffer,
        bool isPool_
    ) public pure {
        BasicParticle memory particle = BasicParticle({
            _flow_rate: FlowRate.wrap(flowRate),
            _settled_at: Time.wrap(settledAt),
            _settled_value: Value.wrap(settledValue)
        });
        bytes32[] memory encoded = _encodeUniversalIndexData(particle, totalBuffer, isPool_);
        (, UniversalIndexData memory decoded) = _decodeUniversalIndexData(encoded);

        assertEq(flowRate, decoded.flowRate, "flowRate not equal");
        assertEq(settledAt, decoded.settledAt, "settledAt not equal");
        assertEq(settledValue, decoded.settledValue, "settledValue not equal");
        assertEq(totalBuffer, decoded.totalBuffer, "totalBuffer not equal");
        assertEq(isPool_, decoded.isPool, "isPool not equal");
    }

    function testEncodeDecodeUIDataInputeUniversalIndexData(
        int96 flowRate,
        uint32 settledAt,
        int256 settledValue,
        uint96 totalBuffer,
        bool isPool_
    ) public pure {
        UniversalIndexData memory data = UniversalIndexData({
            flowRate: flowRate,
            settledAt: settledAt,
            settledValue: settledValue,
            totalBuffer: totalBuffer,
            isPool: isPool_
        });

        bytes32[] memory encoded = _encodeUniversalIndexData(data);
        (, UniversalIndexData memory decoded) = _decodeUniversalIndexData(encoded);

        assertEq(flowRate, decoded.flowRate, "flowRate not equal");
        assertEq(settledAt, decoded.settledAt, "settledAt not equal");
        assertEq(settledValue, decoded.settledValue, "settledValue not equal");
        assertEq(totalBuffer, decoded.totalBuffer, "totalBuffer not equal");
        assertEq(isPool_, decoded.isPool, "isPool not equal");
    }

    function testGetBasicParticleFromUIndex(UniversalIndexData memory data) public pure {
        BasicParticle memory particle = _getBasicParticleFromUIndex(data);
        assertEq(data.flowRate, int96(FlowRate.unwrap(particle._flow_rate)), "flowRate not equal");
        assertEq(data.settledAt, Time.unwrap(particle._settled_at), "settledAt not equal");
        assertEq(data.settledValue, Value.unwrap(particle._settled_value), "settledValue not equal");
    }

    function testEncodeDecodeFlowDistributionData(int96 flowRate, uint96 buffer) public view {
        vm.assume(flowRate >= 0);
        vm.assume(buffer >= 0);
        FlowDistributionData memory original =
            FlowDistributionData({ flowRate: flowRate, lastUpdated: uint32(block.timestamp), buffer: buffer });
        bytes32[] memory encoded = _encodeFlowDistributionData(original);
        (, FlowDistributionData memory decoded) = _decodeFlowDistributionData(uint256(encoded[0]));

        assertEq(original.flowRate, decoded.flowRate, "flowRate not equal");
        assertEq(original.buffer, decoded.buffer, "buffer not equal");
        assertEq(original.lastUpdated, decoded.lastUpdated, "lastUpdated not equal");
    }

    function testEncodeDecodePoolMemberData(address pool, uint32 poolID) public pure {
        vm.assume(pool != address(0));
        PoolMemberData memory original = PoolMemberData({ pool: pool, poolID: poolID });
        bytes32[] memory encoded = _encodePoolMemberData(original);
        (, PoolMemberData memory decoded) = _decodePoolMemberData(uint256(encoded[0]));

        assertEq(original.pool, decoded.pool, "pool not equal");
        assertEq(original.poolID, decoded.poolID, "poolID not equal");
    }
}
