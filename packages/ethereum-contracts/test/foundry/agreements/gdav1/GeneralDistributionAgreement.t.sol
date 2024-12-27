// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@superfluid-finance/solidity-semantic-money/src/SemanticMoney.sol";
import "../../FoundrySuperfluidTester.t.sol";
import {
    GeneralDistributionAgreementV1,
    IGeneralDistributionAgreementV1
} from "../../../../contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol";
import { SuperTokenV1Library } from "../../../../contracts/apps/SuperTokenV1Library.sol";
import { SuperfluidUpgradeableBeacon } from "../../../../contracts/upgradability/SuperfluidUpgradeableBeacon.sol";
import { ISuperToken, SuperToken } from "../../../../contracts/superfluid/SuperToken.sol";
import { ISuperfluidToken } from "../../../../contracts/interfaces/superfluid/ISuperfluidToken.sol";
import { ISuperfluidPool, SuperfluidPool } from "../../../../contracts/agreements/gdav1/SuperfluidPool.sol";
import { IPoolNFTBase } from "../../../../contracts/interfaces/agreements/gdav1/IPoolNFTBase.sol";
import { IPoolAdminNFT } from "../../../../contracts/interfaces/agreements/gdav1/IPoolAdminNFT.sol";
import { IPoolMemberNFT } from "../../../../contracts/interfaces/agreements/gdav1/IPoolMemberNFT.sol";
import { SuperfluidPoolStorageLayoutMock } from "./SuperfluidPoolUpgradabilityMock.t.sol";

/// @title GeneralDistributionAgreementV1 Integration Tests
/// @author Superfluid
/// @notice This is a contract that runs integrations tests for the GDAv1
/// It tests interactions between contracts and more complicated interactions
/// with a range of values when applicable and it aims to ensure that the
/// these interactions work as expected.
contract GeneralDistributionAgreementV1IntegrationTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for uint256;
    using SafeCast for int256;

    struct UpdateMemberData {
        address member;
        uint64 newUnits;
    }

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /// @dev The freePool uses `poolConfig` where both transfer and distributeFromAnyAddress is true
    SuperfluidPool public freePool;
    uint256 public liquidationPeriod;

    constructor() FoundrySuperfluidTester(10) { }

    function setUp() public override {
        super.setUp();
        vm.startPrank(alice);
        freePool = SuperfluidPool(address(superToken.createPool(alice, poolConfig)));
        _addAccount(address(freePool));
        vm.stopPrank();
        (liquidationPeriod,) = sf.governance.getPPPConfig(sf.host, superToken);
    }

    function _getMembers(uint8 length) internal view returns (address[] memory) {
        if (length > TEST_ACCOUNTS.length - 2) revert("Too many members");
        address[] memory members = new address[](length);
        for (uint8 i = 0; i < length; ++i) {
            // do not use Admin and Alice
            members[i] = TEST_ACCOUNTS[i + 2];
        }
        return members;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                GDA Integration Tests
    //////////////////////////////////////////////////////////////////////////*/

    function testInitializeGDA(SuperfluidUpgradeableBeacon beacon) public {
        GeneralDistributionAgreementV1 gdaV1 = new GeneralDistributionAgreementV1(sf.host, beacon);
        assertEq(address(gdaV1.superfluidPoolBeacon()), address(beacon), "GDAv1.t: Beacon address not equal");
    }

    function testRevertAppendIndexUpdateByPoolByNonPool(BasicParticle memory p, Time t) public {
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_ONLY_SUPER_TOKEN_POOL.selector);
        sf.gda.appendIndexUpdateByPool(superToken, p, t);
    }

    function testRevertPoolSettleClaimByNonPool(address claimRecipient, int256 amount) public {
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_ONLY_SUPER_TOKEN_POOL.selector);
        sf.gda.poolSettleClaim(superToken, claimRecipient, amount);
    }

    function testProxiableUUIDIsExpectedValue(PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        assertEq(
            SuperfluidPool(address(pool)).proxiableUUID(),
            keccak256("org.superfluid-finance.contracts.SuperfluidPool.implementation")
        );
    }

    function testPositiveBalanceIsPatricianPeriodNow(address account) public view {
        (bool isPatricianPeriod,) = sf.gda.isPatricianPeriodNow(superToken, account);
        assertEq(isPatricianPeriod, true);
    }

    function testNegativeBalanceIsPatricianPeriodNowIsTrue(PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        uint256 balance = superToken.balanceOf(alice);
        int96 flowRate = balance.toInt256().toInt96() / type(int32).max;
        int96 requestedDistributionFlowRate = int96(flowRate);

        _helperConnectPool(bob, superToken, pool);
        _helperUpdateMemberUnits(pool, alice, bob, 1);

        _helperDistributeFlow(superToken, alice, alice, pool, requestedDistributionFlowRate);

        _helperWarpToCritical(superToken, alice, 1);

        (bool isPatricianPeriod,) = sf.gda.isPatricianPeriodNow(superToken, alice);
        assertEq(isPatricianPeriod, true);
    }

    function testNegativeBalanceIsPatricianPeriodNowIsFalse(PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        uint256 balance = superToken.balanceOf(alice);
        int96 flowRate = balance.toInt256().toInt96() / type(int32).max;
        int96 requestedDistributionFlowRate = int96(flowRate);

        _helperConnectPool(bob, superToken, pool);
        _helperUpdateMemberUnits(pool, alice, bob, 1);

        (int96 actualDistributionFlowRate,) =
            sf.gda.estimateFlowDistributionActualFlowRate(superToken, alice, pool, requestedDistributionFlowRate);

        _helperDistributeFlow(superToken, alice, alice, pool, requestedDistributionFlowRate);

        if (actualDistributionFlowRate > 0) {
            _helperWarpToInsolvency(superToken, alice, liquidationPeriod, 1);
        }

        (bool isPatricianPeriod,) = sf.gda.isPatricianPeriodNow(superToken, alice);
        assertEq(isPatricianPeriod, false);
    }

    function testNegativeBalanceIsPatricianPeriodNowIsFalseWithZeroDeposit(PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        uint256 aliceBalance = superToken.balanceOf(alice);
        int96 flowRate = aliceBalance.toInt256().toInt96() / type(int32).max;
        int96 requestedDistributionFlowRate = int96(flowRate);

        vm.startPrank(sf.governance.owner());
        sf.governance.setRewardAddress(sf.host, ISuperfluidToken(address(0)), alice);
        vm.stopPrank();

        _helperConnectPool(bob, superToken, pool);
        _helperUpdateMemberUnits(pool, alice, bob, 1);

        (int256 aliceRTB, uint256 deposit,,) = superToken.realtimeBalanceOfNow(alice);

        _helperDistributeFlow(superToken, alice, alice, pool, requestedDistributionFlowRate);
        int96 fr = sf.gda.getFlowRate(superToken, alice, pool);

        vm.warp(block.timestamp + (INIT_SUPER_TOKEN_BALANCE / uint256(uint96(fr))) + 1);

        (aliceRTB, deposit,,) = superToken.realtimeBalanceOfNow(alice);

        _helperDistributeFlow(superToken, bob, alice, pool, 0);

        (bool isPatricianPeriod,) = sf.gda.isPatricianPeriodNow(superToken, alice);
        assertEq(isPatricianPeriod, false, "false patrician period");
    }

    function testCreatePool(bool useForwarder, PoolConfig memory config) public {
        _helperCreatePool(superToken, alice, alice, useForwarder, config);
    }

    function testCreatePoolWithCustomERC20Metadata(PoolConfig memory config, uint8 decimals) public {
        vm.assume(decimals < 32);
        _helperCreatePoolWithCustomERC20Metadata(
            superToken, alice, alice, config, PoolERC20Metadata("My SuperToken", "MYST", decimals)
        );
    }

    function testRevertConnectPoolByNonHost(address notHost, PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        vm.assume(notHost != address(sf.host));
        vm.startPrank(notHost);
        vm.expectRevert("unauthorized host");
        sf.gda.connectPool(pool, "0x");
        vm.stopPrank();
    }

    function testRevertNonHostDisconnectPool(address notHost, PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        vm.assume(notHost != address(sf.host));
        vm.startPrank(notHost);
        vm.expectRevert("unauthorized host");
        sf.gda.disconnectPool(pool, "0x");
        vm.stopPrank();
    }

    function testConnectPool(address caller, bool useForwarder, PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, caller, alice, useForwarder, config);
        _helperConnectPool(caller, superToken, pool, useForwarder);
    }

    function testDisconnectPool(address caller, bool useForwarder, PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, caller, alice, useForwarder, config);
        _helperConnectPool(caller, superToken, pool, useForwarder);
        _helperDisconnectPool(caller, superToken, pool, useForwarder);
    }

    function testRevertDistributeFlowToNonPool(int96 requestedFlowRate) public {
        vm.assume(requestedFlowRate >= 0);
        vm.assume(requestedFlowRate < int96(type(int64).max));
        vm.startPrank(alice);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_ONLY_SUPER_TOKEN_POOL.selector);
        superToken.distributeFlow(alice, ISuperfluidPool(bob), requestedFlowRate);
        vm.stopPrank();
    }

    function testRevertDistributeFlowToPoolOfWrongToken(int96 requestedFlowRate) public {
        vm.assume(requestedFlowRate >= 0);
        vm.assume(requestedFlowRate < int96(type(int64).max));
        ISuperToken badToken = sfDeployer.deployNativeAssetSuperToken("Super Bad", "BADx");
        vm.startPrank(alice);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_ONLY_SUPER_TOKEN_POOL.selector);
        badToken.distributeFlow(alice, ISuperfluidPool(bob), requestedFlowRate);
        vm.stopPrank();
    }

    function testRevertDistributeFromAnyAddressWhenNotAllowed(bool useForwarder) public {
        PoolConfig memory config = PoolConfig({ transferabilityForUnitsOwner: true, distributionFromAnyAddress: false });
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, useForwarder, config);

        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_DISTRIBUTE_FROM_ANY_ADDRESS_NOT_ALLOWED.selector);
        vm.startPrank(bob);
        superToken.distribute(bob, pool, 1);
        vm.stopPrank();
    }

    function testRevertDistributeFlowFromAnyAddressWhenNotAllowed(bool useForwarder) public {
        PoolConfig memory config = PoolConfig({ transferabilityForUnitsOwner: true, distributionFromAnyAddress: false });
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, useForwarder, config);

        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_DISTRIBUTE_FROM_ANY_ADDRESS_NOT_ALLOWED.selector);
        vm.startPrank(bob);
        superToken.distributeFlow(bob, pool, 1);
        vm.stopPrank();
    }

    function testRevertIfNotAdminUpdatesMemberUnitsViaGDA(bool useForwarder, PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, useForwarder, config);
        vm.startPrank(bob);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_NOT_POOL_ADMIN.selector);
        sf.host.callAgreement(
            sf.gda,
            abi.encodeCall(sf.gda.updateMemberUnits, (pool, bob, 69, new bytes(0))),
            new bytes(0)
        );
        vm.stopPrank();
    }

    function testRevertIfNotAdminOrGDAUpdatesMemberUnitsViaPool() public {
        vm.startPrank(bob);
        vm.expectRevert(ISuperfluidPool.SUPERFLUID_POOL_NOT_POOL_ADMIN_OR_GDA.selector);
        freePool.updateMemberUnits(bob, 69);
        vm.stopPrank();
    }

    function testRevertDistributeFlowWithNegativeFlowRate(int96 requestedFlowRate, PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        vm.assume(requestedFlowRate < 0);

        vm.startPrank(alice);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_NO_NEGATIVE_FLOW_RATE.selector);
        superToken.distributeFlow(alice, pool, requestedFlowRate);
        vm.stopPrank();
    }

    function testRevertDistributeToNonPool(uint256 requestedAmount) public {
        vm.assume(requestedAmount < uint256(type(uint128).max));

        vm.startPrank(alice);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_ONLY_SUPER_TOKEN_POOL.selector);
        superToken.distribute(alice, ISuperfluidPool(bob), requestedAmount);
        vm.stopPrank();
    }

    function testRevertDistributeToPoolOfWrongToken(uint256 requestedAmount) public {
        vm.assume(requestedAmount < uint256(type(uint128).max));
        ISuperToken badToken = sfDeployer.deployNativeAssetSuperToken("Super Bad", "BADx");
        vm.startPrank(alice);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_ONLY_SUPER_TOKEN_POOL.selector);
        badToken.distribute(alice, ISuperfluidPool(bob), requestedAmount);
        vm.stopPrank();
    }

    function testRevertDistributeForOthers(address signer, uint256 requestedAmount) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, poolConfig);
        vm.assume(requestedAmount < uint256(type(uint128).max));
        vm.assume(signer != alice);

        vm.startPrank(signer);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_DISTRIBUTE_FOR_OTHERS_NOT_ALLOWED.selector);
        sf.host.callAgreement(
            sf.gda,
            abi.encodeCall(sf.gda.distribute, (superToken, alice, pool, requestedAmount, new bytes(0))),
            new bytes(0)
        );
        vm.stopPrank();
    }

    function testRevertDistributeFlowForOthers(address signer, int32 requestedFlowRate) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, poolConfig);
        vm.assume(requestedFlowRate > 0);
        vm.assume(signer != alice);

        vm.startPrank(signer);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_DISTRIBUTE_FOR_OTHERS_NOT_ALLOWED.selector);
        sf.host.callAgreement(
            sf.gda,
            abi.encodeCall(sf.gda.distributeFlow, (superToken, alice, pool, requestedFlowRate, new bytes(0))),
            new bytes(0)
        );
        vm.stopPrank();
    }

    function testRevertDistributeFlowInsufficientBalance(PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        uint256 balance = superToken.balanceOf(alice);
        balance /= 4 hours;
        int96 tooBigFlowRate = int96(int256(balance)) + 1;

        _helperConnectPool(bob, superToken, pool);

        _helperUpdateMemberUnits(pool, alice, bob, 1);
        vm.startPrank(alice);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_INSUFFICIENT_BALANCE.selector);
        sf.host.callAgreement(
            sf.gda,
            abi.encodeCall(sf.gda.distributeFlow, (superToken, alice, pool, tooBigFlowRate, new bytes(0))),
            new bytes(0)
        );
        vm.stopPrank();
    }

    function testRevertLiquidateNonCriticalDistributor(int32 flowRate, int96 units, PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        vm.assume(flowRate > 0);
        _helperConnectPool(bob, superToken, pool);

        _helperUpdateMemberUnits(pool, alice, bob, uint96(units));

        _helperDistributeFlow(superToken, alice, alice, pool, flowRate);

        vm.startPrank(bob);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_NON_CRITICAL_SENDER.selector);
        superToken.distributeFlow(alice, pool, 0);
        vm.stopPrank();
    }

    function testRevertDistributeInsufficientBalance(PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        uint256 balance = superToken.balanceOf(alice);

        _helperConnectPool(bob, superToken, pool);

        vm.startPrank(alice);
        sf.gdaV1Forwarder.updateMemberUnits(pool, bob, 1, new bytes(0));
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IGeneralDistributionAgreementV1.GDA_INSUFFICIENT_BALANCE.selector);
        sf.host.callAgreement(
            sf.gda,
            abi.encodeCall(sf.gda.distribute, (superToken, alice, pool, balance + 1, new bytes(0))),
            new bytes(0)
        );
        vm.stopPrank();
    }

    function testRevertPoolOperatorConnectMember(
        address notOperator,
        address member,
        bool doConnect,
        uint32 time,
        PoolConfig memory config
    ) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        vm.assume(notOperator != address(sf.gda));
        vm.startPrank(notOperator);
        vm.expectRevert(ISuperfluidPool.SUPERFLUID_POOL_NOT_GDA.selector);
        SuperfluidPool(address(pool)).operatorConnectMember(member, doConnect, time);
        vm.stopPrank();
    }

    function testRevertPoolUpdateMemberThatIsPool(uint128 units, PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        vm.assume(units < uint128(type(int128).max));

        vm.expectRevert(ISuperfluidPool.SUPERFLUID_POOL_NO_POOL_MEMBERS.selector);
        vm.startPrank(alice);
        pool.updateMemberUnits(address(pool), units);
        vm.stopPrank();
    }

    function testSuperfluidPoolStorageLayout() public {
        SuperfluidPoolStorageLayoutMock mock = new SuperfluidPoolStorageLayoutMock(sf.gda);
        mock.validateStorageLayout();
    }

    function testDistributeFlowUsesMinDepositWhenFlowDepositIsLess(
        uint64 distributionFlowRate,
        uint32 minDepositFlowRate,
        address member,
        FoundrySuperfluidTester._StackVars_UseBools memory useBools_,
        PoolConfig memory config
    ) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        vm.assume(distributionFlowRate < minDepositFlowRate);
        vm.assume(distributionFlowRate > 0);
        vm.assume(member != address(pool));
        vm.assume(member != address(0));

        _addAccount(member);

        vm.startPrank(address(sf.governance.owner()));
        uint256 minimumDeposit = 4 hours * uint256(minDepositFlowRate);
        sf.governance.setSuperTokenMinimumDeposit(sf.host, superToken, minimumDeposit);
        vm.stopPrank();

        _helperConnectPool(member, superToken, pool);
        _helperUpdateMemberUnits(pool, alice, member, 1, useBools_);
        _helperDistributeFlow(superToken, alice, alice, pool, int96(int64(distributionFlowRate)));
        (, uint256 buffer,,) = superToken.realtimeBalanceOfNow(alice);
        assertEq(buffer, minimumDeposit, "GDAv1.t: Min buffer should be used");
    }

    function testDistributeFlowIgnoresMinDepositWhenFlowDepositIsGreater(
        int32 distributionFlowRate,
        uint32 minDepositFlowRate,
        address member,
        FoundrySuperfluidTester._StackVars_UseBools memory useBools_,
        PoolConfig memory config
    ) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);
        vm.assume(uint32(distributionFlowRate) >= minDepositFlowRate);
        vm.assume(distributionFlowRate > 0);
        vm.assume(member != address(0));
        vm.assume(member != address(freePool));

        _addAccount(member);

        vm.startPrank(address(sf.governance.owner()));

        uint256 minimumDeposit = 4 hours * uint256(minDepositFlowRate);
        sf.governance.setSuperTokenMinimumDeposit(sf.host, superToken, minimumDeposit);
        vm.stopPrank();

        _helperConnectPool(member, superToken, pool);
        _helperUpdateMemberUnits(pool, alice, member, 1, useBools_);
        _helperDistributeFlow(superToken, alice, alice, pool, int96(distributionFlowRate));
        (, uint256 buffer,,) = superToken.realtimeBalanceOfNow(alice);
        assertTrue(buffer >= minimumDeposit, "GDAv1.t: Buffer should be >= minDeposit");
    }

    function testDistributeFlowToConnectedMemberSendingToCFA(
        int32 flowRate,
        uint64 units,
        FoundrySuperfluidTester._StackVars_UseBools memory useBools_,
        PoolConfig memory config
    ) public {
        vm.assume(flowRate > 0);

        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        int96 requestedDistributionFlowRate = int96(flowRate);

        uint128 memberUnits = uint128(units);

        _helperUpdateMemberUnits(pool, alice, bob, memberUnits, useBools_);

        _helperDistributeFlow(superToken, alice, alice, pool, requestedDistributionFlowRate);

        _helperConnectPool(bob, superToken, pool);
        // bob sends a flow of 1 to alice
        vm.startPrank(bob);
        superToken.createFlow(alice, requestedDistributionFlowRate * 10);
        vm.stopPrank();

        int96 aliceGDANetFlowRate = sf.gda.getNetFlow(superToken, alice);
        int96 bobGDANetFlowRate = sf.gda.getNetFlow(superToken, bob);
        int96 aliceCFANetFlowRate = sf.cfa.getNetFlow(superToken, alice);
        int96 bobCFANetFlowRate = sf.cfa.getNetFlow(superToken, bob);
        assertEq(
            aliceGDANetFlowRate + bobGDANetFlowRate + aliceCFANetFlowRate + bobCFANetFlowRate,
            0,
            "alice and bob GDA net flow rates !="
        );
    }

    function testDistributeToEmptyPool(uint64 distributionAmount, bool useForwarder, PoolConfig memory config) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, useForwarder, config);
        _helperDistributeViaGDA(superToken, alice, alice, pool, distributionAmount, useForwarder);
    }

    function testDistributeFlowToEmptyPool(int32 flowRate, bool useForwarder, PoolConfig memory config) public {
        vm.assume(flowRate >= 0);
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, useForwarder, config);
        _helperDistributeFlow(superToken, alice, alice, pool, flowRate, useForwarder);
        assertEq(sf.gda.getFlowRate(superToken, alice, pool), 0, "GDAv1.t: distributionFlowRate should be 0");
    }

    function testDistributeFlowCriticalLiquidation(
        uint64 units,
        _StackVars_UseBools memory useBools_,
        PoolConfig memory config
    ) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        uint256 balance = superToken.balanceOf(alice);
        int96 flowRate = balance.toInt256().toInt96() / type(int32).max;
        int96 requestedDistributionFlowRate = int96(flowRate);

        uint128 memberUnits = uint128(units);

        _helperConnectPool(bob, superToken, pool);
        _helperUpdateMemberUnits(pool, alice, bob, memberUnits, useBools_);

        (int96 actualDistributionFlowRate,) =
            sf.gda.estimateFlowDistributionActualFlowRate(superToken, alice, pool, requestedDistributionFlowRate);

        _helperDistributeFlow(superToken, alice, alice, pool, requestedDistributionFlowRate);

        if (actualDistributionFlowRate > 0) {
            _helperWarpToCritical(superToken, alice, 1);
            _helperDistributeFlow(superToken, bob, alice, pool, 0);
        }
    }

    function testDistributeFlowInsolventLiquidation(
        uint64 units,
        _StackVars_UseBools memory useBools_,
        PoolConfig memory config
    ) public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        uint256 balance = superToken.balanceOf(alice);
        int96 flowRate = balance.toInt256().toInt96() / type(int32).max;
        int96 requestedDistributionFlowRate = int96(flowRate);

        uint128 memberUnits = uint128(units);

        _helperConnectPool(bob, superToken, pool);
        _helperUpdateMemberUnits(pool, alice, bob, memberUnits, useBools_);
        _helperDistributeFlow(superToken, alice, alice, pool, requestedDistributionFlowRate);

        (int96 actualDistributionFlowRate,) =
            sf.gda.estimateFlowDistributionActualFlowRate(superToken, alice, pool, requestedDistributionFlowRate);

        _helperDistributeFlow(superToken, alice, alice, pool, requestedDistributionFlowRate);

        if (actualDistributionFlowRate > 0) {
            _helperWarpToInsolvency(superToken, alice, liquidationPeriod, 1);
            _helperDistributeFlow(superToken, bob, alice, pool, 0);
        }
    }

    function testDistributeToDisconnectedMembers(
        uint64[5] memory memberUnits,
        uint256 distributionAmount,
        _StackVars_UseBools memory useBools_,
        PoolConfig memory config
    ) public {
        address distributor = alice;
        uint256 distributorBalance = superToken.balanceOf(distributor);

        vm.assume(distributionAmount < distributorBalance);

        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        address[] memory members = _getMembers(5);

        for (uint256 i = 0; i < members.length; ++i) {
            if (sf.gda.isPool(superToken, members[i]) || members[i] == address(0)) continue;

            _helperUpdateMemberUnits(pool, alice, members[i], memberUnits[i], useBools_);
        }
        uint256 actualAmount = sf.gda.estimateDistributionActualAmount(superToken, alice, pool, distributionAmount);
        _helperDistributeViaGDA(superToken, alice, alice, pool, distributionAmount, useBools_.useForwarder);

        uint128 perUnitDistributionAmount = uint128(actualAmount / pool.getTotalUnits());
        for (uint256 i = 0; i < members.length; ++i) {
            if (sf.gda.isPool(superToken, members[i]) || members[i] == address(0)) continue;

            uint128 memberIUnits = pool.getUnits(members[i]);

            assertEq(perUnitDistributionAmount * memberIUnits, pool.getTotalAmountReceivedByMember(members[i]));
        }
    }

    function testDistributeToConnectedMembers(
        uint64[5] memory memberUnits,
        uint256 distributionAmount,
        _StackVars_UseBools memory useBools_,
        PoolConfig memory config
    ) public {
        address distributor = alice;
        uint256 distributorBalance = superToken.balanceOf(distributor);

        vm.assume(distributionAmount < distributorBalance);

        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        address[] memory members = _getMembers(5);

        for (uint256 i = 0; i < members.length; ++i) {
            if (sf.gda.isPool(superToken, members[i]) || members[i] == address(0)) continue;

            _helperConnectPool(members[i], superToken, pool, useBools_.useForwarder);
            _helperUpdateMemberUnits(pool, alice, members[i], memberUnits[i], useBools_);
            _addAccount(members[i]);
        }
        uint256 actualAmount = sf.gda.estimateDistributionActualAmount(superToken, alice, pool, distributionAmount);
        _helperDistributeViaGDA(superToken, alice, alice, pool, distributionAmount, useBools_.useForwarder);

        uint128 perUnitDistributionAmount = uint128(actualAmount / pool.getTotalUnits());
        for (uint256 i = 0; i < members.length; ++i) {
            if (sf.gda.isPool(superToken, members[i]) || members[i] == address(0)) continue;

            uint128 memberIUnits = pool.getUnits(members[i]);

            assertEq(perUnitDistributionAmount * memberIUnits, pool.getTotalAmountReceivedByMember(members[i]));
        }
    }

    function testDistributeFlowToConnectedMembers(
        uint64[5] memory memberUnits,
        int32 flowRate,
        _StackVars_UseBools memory useBools_,
        PoolConfig memory config
    ) public {
        vm.assume(flowRate > 0);

        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        address[] memory members = _getMembers(5);

        for (uint256 i = 0; i < members.length; ++i) {
            if (sf.gda.isPool(superToken, members[i]) || members[i] == address(0)) continue;

            _helperConnectPool(members[i], superToken, pool, useBools_.useForwarder);
            _helperUpdateMemberUnits(pool, alice, members[i], memberUnits[i], useBools_);
            _addAccount(members[i]);
        }

        _helperDistributeFlow(superToken, alice, alice, pool, 100, useBools_.useForwarder);
        int96 poolAdjustmentFlowRate = useBools_.useForwarder
            ? sf.gdaV1Forwarder.getPoolAdjustmentFlowRate(address(pool))
            : sf.gda.getPoolAdjustmentFlowRate(address(pool));
        assertEq(poolAdjustmentFlowRate, 0, "GDAv1.t: Pool adjustment rate is non-zero");
    }

    function testDistributeFlowToUnconnectedMembers(
        uint64[5] memory memberUnits,
        int32 flowRate,
        uint16 warpTime,
        _StackVars_UseBools memory useBools_,
        PoolConfig memory config
    ) public {
        vm.assume(flowRate > 0);

        ISuperfluidPool pool;
        {
            pool = _helperCreatePool(superToken, alice, alice, false, config);
        }

        address[] memory members = _getMembers(5);

        for (uint256 i = 0; i < members.length; ++i) {
            if (sf.gda.isPool(superToken, members[i]) || members[i] == address(0)) continue;
            _helperUpdateMemberUnits(pool, alice, members[i], memberUnits[i], useBools_);
        }

        int96 actualDistributionFlowRate;
        {
            int96 requestedFlowRate = flowRate;
            _helperDistributeFlow(superToken, alice, alice, pool, requestedFlowRate, useBools_.useForwarder);
            (actualDistributionFlowRate,) =
                sf.gda.estimateFlowDistributionActualFlowRate(superToken, alice, pool, requestedFlowRate);

            vm.warp(block.timestamp + warpTime);
        }
        uint128 totalUnits = pool.getTotalUnits();

        for (uint256 i; i < members.length; ++i) {
            if (members[i] != address(0)) {
                // @note we test realtimeBalanceOfNow here as well
                (int256 memberRTB,,) = sf.gda.realtimeBalanceOf(superToken, members[i], block.timestamp);
                (int256 rtbNow,,,) = sf.gda.realtimeBalanceOfNow(superToken, members[i]);
                assertEq(memberRTB, rtbNow, "testDistributeFlowToUnconnectedMembers: rtb != rtbNow");

                assertEq(
                    pool.getTotalDisconnectedFlowRate(),
                    actualDistributionFlowRate,
                    "testDistributeFlowToUnconnectedMembers: pendingDistributionFlowRate != actualDistributionFlowRate"
                );
                (int256 memberClaimable,) = pool.getClaimableNow(members[i]);

                assertEq(
                    memberClaimable,
                    totalUnits > 0
                        ? (actualDistributionFlowRate * int96(int256(uint256(warpTime)))) * int96(uint96(memberUnits[i]))
                            / uint256(totalUnits).toInt256()
                        : int256(0),
                    "testDistributeFlowToUnconnectedMembers: memberClaimable != (actualDistributionFlowRate * warpTime) / totalUnits"
                );
                assertEq(memberRTB, 0, "testDistributeFlowToUnconnectedMembers: memberRTB != 0");

                vm.startPrank(members[i]);
                if (useBools_.useGDA) {
                    if (useBools_.useForwarder) {
                        sf.gdaV1Forwarder.claimAll(pool, members[i], new bytes(0));
                    } else {
                        superToken.claimAll(pool, members[i]);
                    }
                } else {
                    pool.claimAll();
                }
                vm.stopPrank();

                (memberRTB,,) = sf.gda.realtimeBalanceOf(superToken, members[i], block.timestamp);
                assertEq(
                    memberRTB, memberClaimable, "testDistributeFlowToUnconnectedMembers: memberRTB != memberClaimable"
                );
            }
        }
    }

    // Pool ERC20 functions

    function testApproveOnly(address owner, address spender, uint256 amount, PoolConfig memory config) public {
        vm.assume(owner != address(0));
        vm.assume(spender != address(0));

        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        _helperSuperfluidPoolApprove(pool, owner, spender, amount);
    }

    function testIncreaseAllowance(address owner, address spender, uint256 addedValue, PoolConfig memory config)
        public
    {
        vm.assume(owner != address(0));
        vm.assume(spender != address(0));

        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        _helperSuperfluidPoolIncreaseAllowance(pool, owner, spender, addedValue);
    }

    function testDecreaseAllowance(
        address owner,
        address spender,
        uint256 addedValue,
        uint256 subtractedValue,
        PoolConfig memory config
    ) public {
        vm.assume(owner != address(0));
        vm.assume(spender != address(0));
        vm.assume(addedValue >= subtractedValue);

        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        _helperSuperfluidPoolIncreaseAllowance(pool, owner, spender, addedValue);
        _helperSuperfluidPoolDecreaseAllowance(pool, owner, spender, subtractedValue);
    }

    function testRevertIfUnitsTransferReceiverIsPool(address from, int96 unitsAmount, int128 transferAmount)
        public
    {
        // @note we use int96 because overflow will happen otherwise
        vm.assume(unitsAmount >= 0);
        vm.assume(transferAmount > 0);
        vm.assume(from != address(0));
        vm.assume(transferAmount <= unitsAmount);
        _helperUpdateMemberUnits(freePool, alice, from, uint128(int128(unitsAmount)));

        vm.startPrank(from);
        vm.expectRevert(ISuperfluidPool.SUPERFLUID_POOL_NO_POOL_MEMBERS.selector);
        freePool.transfer(address(freePool), uint256(uint128(transferAmount)));
        vm.stopPrank();
    }

    function testRevertIfTransferNotAllowed(bool useForwarder) public {
        PoolConfig memory config = PoolConfig({ transferabilityForUnitsOwner: false, distributionFromAnyAddress: true });
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, useForwarder, config);

        _helperUpdateMemberUnits(pool, alice, bob, 1000);

        vm.startPrank(bob);
        vm.expectRevert(ISuperfluidPool.SUPERFLUID_POOL_TRANSFER_UNITS_NOT_ALLOWED.selector);
        pool.transfer(alice, 1000);
        vm.stopPrank();
    }

    function testRevertIfTransferFromNotAllowed(bool useForwarder) public {
        PoolConfig memory config = PoolConfig({ transferabilityForUnitsOwner: false, distributionFromAnyAddress: true });
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, useForwarder, config);

        _helperUpdateMemberUnits(freePool, alice, bob, 1000);

        vm.startPrank(bob);
        pool.approve(carol, 1000);
        vm.stopPrank();

        vm.startPrank(carol);
        vm.expectRevert(ISuperfluidPool.SUPERFLUID_POOL_TRANSFER_UNITS_NOT_ALLOWED.selector);
        pool.transferFrom(bob, carol, 1000);
        vm.stopPrank();
    }

    function testBasicTransfer(
        FoundrySuperfluidTester._StackVars_UseBools memory useBools_,
        uint8 a, uint8 b, // One must use small sized data type to find equality cases
        uint128 unitsAmount,
        uint128 transferAmount
    ) public {
        address from = address(uint160(a));
        address to = address(uint160(b));

        transferAmount = uint96(bound(transferAmount, 0, unitsAmount));

        vm.assume(from != address(0));
        _helperUpdateMemberUnits(freePool, alice, from, unitsAmount, useBools_);

        if (from == to) {
            vm.startPrank(from);
            vm.expectRevert(ISuperfluidPool.SUPERFLUID_POOL_SELF_TRANSFER_NOT_ALLOWED.selector);
            freePool.transfer(to, transferAmount);
            vm.stopPrank();
        } else if (to == address(0)) {
            vm.startPrank(from);
            vm.expectRevert(ISuperfluidPool.SUPERFLUID_POOL_NO_ZERO_ADDRESS.selector);
            freePool.transfer(to, transferAmount);
            vm.stopPrank();
        } else {
            _helperSuperfluidPoolUnitsTransfer(freePool, from, to, uint256(uint128(transferAmount)));
        }
    }

    function testApproveAndTransferFrom(
        address owner,
        address spender,
        int128 transferAmount,
        FoundrySuperfluidTester._StackVars_UseBools memory useBools_
    ) public {
        vm.assume(transferAmount > 0);
        vm.assume(spender != address(0));
        vm.assume(owner != address(0));
        vm.assume(spender != owner);
        _helperUpdateMemberUnits(freePool, alice, owner, uint128(int128(transferAmount)), useBools_);
        _helperSuperfluidPoolApprove(freePool, owner, spender, uint256(uint128(transferAmount)));
        _helperSuperfluidPoolUnitsTransferFrom(freePool, spender, owner, spender, uint256(uint128(transferAmount)));
    }

    function testIncreaseAllowanceAndTransferFrom(
        address owner,
        address spender,
        int128 transferAmount,
        FoundrySuperfluidTester._StackVars_UseBools memory useBools_
    ) public {
        vm.assume(transferAmount > 0);
        vm.assume(spender != address(0));
        vm.assume(owner != address(0));
        vm.assume(spender != owner);
        _helperUpdateMemberUnits(freePool, alice, owner, uint128(int128(transferAmount)), useBools_);
        _helperSuperfluidPoolIncreaseAllowance(freePool, owner, spender, uint256(uint128(transferAmount)));
        _helperSuperfluidPoolUnitsTransferFrom(freePool, spender, owner, spender, uint256(uint128(transferAmount)));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Assertion Functions
    //////////////////////////////////////////////////////////////////////////*/

    struct PoolUpdateStep {
        uint8 u; // which user
        uint8 a; // action types: 0 update units, 1 distribute flow, 2 freePool connection, 3 freePool claim for,
            // 4 distribute
        uint32 v; // action param
        uint16 dt; // time delta
    }

    function testPoolRandomSeqs(PoolUpdateStep[20] memory steps, _StackVars_UseBools memory useBools_) external {
        uint256 N_MEMBERS = 5;

        for (uint256 i = 0; i < steps.length; ++i) {
            emit log_named_string("", "");
            emit log_named_uint(">>> STEP", i);
            PoolUpdateStep memory s = steps[i];
            uint256 action = s.a % 5;
            uint256 u = 1 + s.u % N_MEMBERS;
            address user = TEST_ACCOUNTS[u];

            emit log_named_uint("user", u);
            emit log_named_uint("time delta", s.dt);
            emit log_named_uint("> timestamp", block.timestamp);
            emit log_named_address("tester", user);

            if (action == 0) {
                emit log_named_string("action", "updateMember");
                emit log_named_uint("units", s.v);
                _helperUpdateMemberUnits(freePool, freePool.admin(), user, s.v, useBools_);
            } else if (action == 1) {
                emit log_named_string("action", "distributeFlow");
                emit log_named_uint("flow rate", s.v);
                if (sf.gda.getFlowRate(superToken, user, freePool) == 0) {
                    vm.assume(s.v > 0);
                }
                _helperDistributeFlow(superToken, user, user, freePool, int96(uint96(s.v)), useBools_.useForwarder);
            } else if (action == 2) {
                address u4 = TEST_ACCOUNTS[1 + (s.v % N_MEMBERS)];
                emit log_named_string("action", "claimAll");
                emit log_named_address("claim for", u4);
                vm.startPrank(user);
                assert(freePool.claimAll(u4));
                vm.stopPrank();
            } else if (action == 3) {
                bool doConnect = s.v % 2 == 0 ? false : true;
                emit log_named_string("action", "doConnectPool");
                emit log_named_string("doConnect", doConnect ? "true" : "false");
                doConnect
                    ? _helperConnectPool(user, superToken, freePool, useBools_.useForwarder)
                    : _helperDisconnectPool(user, superToken, freePool, useBools_.useForwarder);
            } else if (action == 4) {
                emit log_named_string("action", "distribute");
                emit log_named_uint("distributionAmount", s.v);
                _helperDistributeViaGDA(superToken, user, user, freePool, uint256(s.v), useBools_.useForwarder);
            } else {
                assert(false);
            }

            {
                (int256 rtb, uint256 buffer, uint256 owedBuffer) =
                    sf.gda.realtimeBalanceOf(superToken, address(freePool), block.timestamp);
                int96 nr = useBools_.useForwarder
                    ? sf.gdaV1Forwarder.getNetFlow(superToken, address(freePool))
                    : sf.gda.getNetFlow(superToken, address(freePool));
                emit log_string("> freePool before time warp");
                emit log_named_int("rtb", rtb);
                emit log_named_uint("buffer", buffer);
                emit log_named_uint("owedBuffer", owedBuffer);
                emit log_named_int("freePool net flow rate", nr);
            }

            emit log_named_uint("> dt", s.dt);
            vm.warp(block.timestamp + s.dt);

            {
                (int256 rtb, uint256 buffer, uint256 owedBuffer) =
                    sf.gda.realtimeBalanceOf(superToken, address(freePool), block.timestamp);
                int96 nr = useBools_.useForwarder
                    ? sf.gdaV1Forwarder.getNetFlow(superToken, address(freePool))
                    : sf.gda.getNetFlow(superToken, address(freePool));
                emit log_string("> freePool before time warp");
                emit log_named_int("rtb", rtb);
                emit log_named_uint("buffer", buffer);
                emit log_named_uint("owedBuffer", owedBuffer);
                emit log_named_int("freePool net flow rate", nr);
            }
        }

        int96 flowRatesSum;
        {
            int96 poolNetFlowRate = sf.gda.getNetFlow(superToken, address(freePool));
            flowRatesSum = flowRatesSum + poolNetFlowRate;
        }

        for (uint256 i = 1; i <= N_MEMBERS; ++i) {
            int96 flowRate = sf.gda.getNetFlow(superToken, TEST_ACCOUNTS[i]);
            flowRatesSum = flowRatesSum + flowRate;
        }

        assertEq(flowRatesSum, 0, "GDAv1.t: flowRatesSum != 0");
    }
}
