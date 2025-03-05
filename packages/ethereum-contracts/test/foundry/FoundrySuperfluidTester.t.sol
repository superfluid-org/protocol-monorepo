// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ERC1820RegistryCompiled } from "../../contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "../../contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import { Superfluid } from "../../contracts/superfluid/Superfluid.sol";
import { ISuperfluidPool, SuperfluidPool } from "../../contracts/agreements/gdav1/SuperfluidPool.sol";
import {
    IGeneralDistributionAgreementV1,
    PoolConfig,
    PoolERC20Metadata
} from "../../contracts/interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import { IPoolNFTBase } from "../../contracts/interfaces/agreements/gdav1/IPoolNFTBase.sol";
import { IPoolAdminNFT } from "../../contracts/interfaces/agreements/gdav1/IPoolAdminNFT.sol";
import { IPoolMemberNFT } from "../../contracts/interfaces/agreements/gdav1/IPoolMemberNFT.sol";
import { ISuperfluidToken } from "../../contracts/interfaces/superfluid/ISuperfluidToken.sol";
import { ISETH } from "../../contracts/interfaces/tokens/ISETH.sol";
import { UUPSProxy } from "../../contracts/upgradability/UUPSProxy.sol";
import { ConstantFlowAgreementV1 } from "../../contracts/agreements/ConstantFlowAgreementV1.sol";
import { SuperTokenV1Library } from "../../contracts/apps/SuperTokenV1Library.sol";
import { IERC20, ISuperToken, SuperToken, IConstantOutflowNFT, IConstantInflowNFT }
    from "../../contracts/superfluid/SuperToken.sol";
import { SuperfluidLoader } from "../../contracts/utils/SuperfluidLoader.sol";
import { TestResolver } from "../../contracts/utils/TestResolver.sol";
import { TestToken } from "../../contracts/utils/TestToken.sol";

/// @title FoundrySuperfluidTester
/// @dev A contract that can be inherited from to test Superfluid agreements
///
/// Types of SuperToken to test:
/// - (0) | WRAPPER_SUPER_TOKEN: has underlying ERC20 token (e.g. USDC)
/// - (1) | NATIVE_ASSET_SUPER_TOKEN: underlying asset is the native gas token (e.g. ETH)
/// - (2) | PURE_SUPER_TOKEN: has no underlying AND is purely a SuperToken
/// - (3) | CUSTOM_WRAPPER_SUPER_TOKEN: has underlying ERC20 token (e.g. USDC) AND has custom SuperToken logic
/// - (4) | CUSTOM_PURE_SUPER_TOKEN: has no underlying AND is purely a SuperToken AND has custom SuperToken logic
///
/// Definitions
/// - AUM: Assets Under Management
///     - Wrapper: underlyingToken.balanceOf(address(superToken))
///     - Native: address(superToken).balance
///     - Pure: superToken.totalSupply()
contract FoundrySuperfluidTester is Test {
    using SuperTokenV1Library for ISuperToken;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for uint256;
    using SafeCast for int256;

    enum TestSuperTokenType {
        WRAPPER_SUPER_TOKEN,
        NATIVE_ASSET_SUPER_TOKEN,
        PURE_SUPER_TOKEN,
        CUSTOM_WRAPPER_SUPER_TOKEN,
        CUSTOM_PURE_SUPER_TOKEN,
        UNSUPPORTED_TOKEN_TYPE
    }

    struct _StackVars_UseBools {
        bool useForwarder;
        bool useGDA;
    }

    struct RealtimeBalance {
        int256 availableBalance;
        uint256 deposit;
        uint256 owedDeposit;
        uint256 timestamp;
    }

    struct IDASubscriptionParams {
        ISuperToken superToken;
        address publisher;
        address subscriber;
        uint32 indexId;
    }

    struct ExpectedSuperfluidPoolData {
        int128 totalUnits;
        int128 connectedUnits;
        int128 disconnectedUnits;
        int96 connectedFlowRate;
        int96 disconnectedFlowRate;
        int256 disconnectedBalance;
    }

    struct ExpectedPoolMemberData {
        bool isConnected;
        uint128 ownedUnits;
        int96 flowRate;
        int96 netFlowRate;
    }

    struct PoolUnitData {
        uint128 totalUnits;
        uint128 connectedUnits;
        uint128 disconnectedUnits;
    }

    struct PoolFlowRateData {
        int96 totalFlowRate;
        int96 totalConnectedFlowRate;
        int96 totalDisconnectedFlowRate;
    }

    error INVALID_TEST_SUPER_TOKEN_TYPE();

    SuperfluidFrameworkDeployer internal immutable sfDeployer;
    TestSuperTokenType internal immutable testSuperTokenType;

    uint256 internal constant DEFAULT_WARP_TIME = 1 days;
    uint256 internal constant INIT_TOKEN_BALANCE = type(uint128).max;
    uint256 internal constant INIT_SUPER_TOKEN_BALANCE = type(uint88).max;
    string internal constant DEFAULT_TEST_TOKEN_TYPE = "WRAPPER_SUPER_TOKEN";
    string internal constant TOKEN_TYPE_ENV_KEY = "TOKEN_TYPE";

    address internal constant admin = address(0x420);
    address internal constant alice = address(0x421);
    address internal constant bob = address(0x422);
    address internal constant carol = address(0x423);
    address internal constant dan = address(0x424);
    address internal constant eve = address(0x425);
    address internal constant frank = address(0x426);
    address internal constant grace = address(0x427);
    address internal constant heidi = address(0x428);
    address internal constant ivan = address(0x429);
    address[] internal TEST_ACCOUNTS = [admin, alice, bob, carol, dan, eve, frank, grace, heidi, ivan];

    /// @dev Other account addresses added that aren't testers (pools, super apps, smart contracts)
    EnumerableSet.AddressSet internal OTHER_ACCOUNTS;

    uint256 internal immutable N_TESTERS;

    SuperfluidFrameworkDeployer.Framework internal sf;

    /// @dev The current underlying token being tested (applies only to wrapper super tokens)
    TestToken internal token;

    /// @dev The current super token being tested
    ISuperToken internal superToken;

    /// @dev The expected total supply of the current super token being tested
    uint256 private _expectedTotalSupply;

    /// @notice A mapping from super token to account to realtime balance data snapshot
    /// @dev Used for validating that balances are correct
    mapping(ISuperToken => mapping(address account => RealtimeBalance balanceSnapshot)) internal _balanceSnapshots;

    /// @notice A mapping from super token to account to flowIDs of outflows from the account for the CFA
    mapping(ISuperToken => mapping(address account => EnumerableSet.Bytes32Set flowIDs)) internal _outflows;

    /// @notice A mapping from super token to account to flowIDs of inflows to the account for the CFA
    mapping(ISuperToken => mapping(address account => EnumerableSet.Bytes32Set flowIDs)) internal _inflows;

    /// @notice A mapping from super token to account to indexIDs of indexes of the account for the IDA
    mapping(ISuperToken => mapping(address account => EnumerableSet.Bytes32Set indexIDs)) internal _indexIDs;

    /// @notice A mapping from super token to subId to sub.indexValue for the IDA
    mapping(ISuperToken => mapping(bytes32 subId => uint128 indexValue)) internal _lastUpdatedSubIndexValues;

    /// @notice A mapping from pool to
    mapping(address pool => EnumerableSet.AddressSet members) internal _poolMembers;
    mapping(address pool => mapping(address member => ExpectedPoolMemberData expectedData)) internal
        _poolToExpectedMemberData;

    /// @notice The default poolConfig (true, true)
    PoolConfig public poolConfig;

    constructor(uint8 nTesters) {
        // deploy ERC1820 registry
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        // deploy SuperfluidFrameworkDeployer
        // which deploys in its constructor:
        // - TestGovernance
        // - Host
        // - CFA
        // - IDA
        // - SuperToken logic
        // - SuperTokenFactory
        // - Resolver
        // - SuperfluidLoader
        // - CFAv1Forwarder
        sfDeployer = new SuperfluidFrameworkDeployer();
        sfDeployer.deployTestFramework();
        sf = sfDeployer.getFramework();

        require(nTesters <= TEST_ACCOUNTS.length, "too many testers");
        N_TESTERS = nTesters;

        _addAccount(address(sf.gda));

        // Set the token type being tested
        string memory tokenType = vm.envOr(TOKEN_TYPE_ENV_KEY, DEFAULT_TEST_TOKEN_TYPE);
        bytes32 hashedTokenType = keccak256(abi.encode(tokenType));

        _addAccount(address(sf.toga));

        poolConfig = PoolConfig({ transferabilityForUnitsOwner: true, distributionFromAnyAddress: true });

        // @note we must use a ternary expression because immutable variables cannot be initialized
        // in an if statement
        testSuperTokenType = hashedTokenType == keccak256(abi.encode("WRAPPER_SUPER_TOKEN"))
            ? TestSuperTokenType.WRAPPER_SUPER_TOKEN
            : hashedTokenType == keccak256(abi.encode("NATIVE_ASSET_SUPER_TOKEN"))
                ? TestSuperTokenType.NATIVE_ASSET_SUPER_TOKEN
                : hashedTokenType == keccak256(abi.encode("PURE_SUPER_TOKEN"))
                    ? TestSuperTokenType.PURE_SUPER_TOKEN
                    : hashedTokenType == keccak256(abi.encode("CUSTOM_WRAPPER_SUPER_TOKEN"))
                        ? TestSuperTokenType.CUSTOM_WRAPPER_SUPER_TOKEN
                        : hashedTokenType == keccak256(abi.encode("CUSTOM_PURE_SUPER_TOKEN"))
                            ? TestSuperTokenType.CUSTOM_PURE_SUPER_TOKEN
                            : TestSuperTokenType.UNSUPPORTED_TOKEN_TYPE;

        if (testSuperTokenType == TestSuperTokenType.UNSUPPORTED_TOKEN_TYPE) revert INVALID_TEST_SUPER_TOKEN_TYPE();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Test Setup/Harness
    //////////////////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        _setUpSuperToken();
    }

    /// @notice Deploys a Wrapper SuperToken with an underlying test token and gives tokens to the test accounts
    function _setUpWrapperSuperToken() internal {
        (token, superToken) = sfDeployer.deployWrapperSuperToken("FTT", "FTT", 18, type(uint256).max, address(0));

        address[] memory accounts = _listAccounts();
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            token.mint(account, INIT_TOKEN_BALANCE);

            vm.startPrank(account);
            token.approve(address(superToken), INIT_SUPER_TOKEN_BALANCE);
            superToken.upgrade(INIT_SUPER_TOKEN_BALANCE);
            _expectedTotalSupply += INIT_SUPER_TOKEN_BALANCE;
            vm.stopPrank();
            _helperTakeBalanceSnapshot(superToken, account);
        }
    }

    /// @notice Deploys a Native Asset SuperToken and gives tokens to the test accounts
    /// @dev We use vm.deal to give each account a starting amount of ether
    function _setUpNativeAssetSuperToken() internal {
        (superToken) = sfDeployer.deployNativeAssetSuperToken("Super ETH", "ETHx");

        address[] memory accounts = _listAccounts();
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            vm.startPrank(account);
            vm.deal(account, INIT_TOKEN_BALANCE);
            ISETH(address(superToken)).upgradeByETH{ value: INIT_SUPER_TOKEN_BALANCE }();
            _expectedTotalSupply += INIT_SUPER_TOKEN_BALANCE;
            vm.stopPrank();
            _helperTakeBalanceSnapshot(superToken, account);
        }
    }

    /// @notice Deploys a Pure SuperToken and gives tokens to the test accounts
    /// @dev This contract receives the total supply then doles it out to the test accounts
    function _setUpPureSuperToken() internal {
        address[] memory accounts = _listAccounts();

        uint256 initialSupply = INIT_SUPER_TOKEN_BALANCE * accounts.length;
        (superToken) = sfDeployer.deployPureSuperToken("Super MR", "MRx", initialSupply);
        _expectedTotalSupply = initialSupply;

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            superToken.transfer(account, INIT_SUPER_TOKEN_BALANCE);
            _helperTakeBalanceSnapshot(superToken, account);
        }
    }

    /// @notice Deploys a SuperToken based on the testSuperTokenType selected
    function _setUpSuperToken() internal {
        if (testSuperTokenType == TestSuperTokenType.WRAPPER_SUPER_TOKEN) {
            _setUpWrapperSuperToken();
        } else if (testSuperTokenType == TestSuperTokenType.NATIVE_ASSET_SUPER_TOKEN) {
            _setUpNativeAssetSuperToken();
        } else if (testSuperTokenType == TestSuperTokenType.PURE_SUPER_TOKEN) {
            _setUpPureSuperToken();

            // @note TODO these still have to be implemented
        } else if (testSuperTokenType == TestSuperTokenType.CUSTOM_WRAPPER_SUPER_TOKEN) {
            // _setUpCustomWrapperSuperToken();
        } else if (testSuperTokenType == TestSuperTokenType.CUSTOM_PURE_SUPER_TOKEN) {
            // _setUpCustomPureSuperToken();
        } else {
            revert("invalid test token type");
        }
    }

    /// @notice Adds an account to the testing mix
    function _addAccount(address account) internal {
        if (OTHER_ACCOUNTS.contains(account)) return;

        for (uint i = 0; i < TEST_ACCOUNTS.length; ++i) {
            if (TEST_ACCOUNTS[i] == account) return;
        }

        OTHER_ACCOUNTS.add(account);
    }

    function _listAccounts() internal view returns (address[] memory accounts) {
        accounts = new address[](N_TESTERS + OTHER_ACCOUNTS.values().length);
        for (uint i = 0; i < N_TESTERS; ++i) {
            accounts[i] = address(TEST_ACCOUNTS[i]);
        }
        for (uint i = 0; i < OTHER_ACCOUNTS.values().length; ++i) {
            accounts[i + N_TESTERS] = OTHER_ACCOUNTS.values()[i];
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Invariant Definitions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Liquidity Sum Invariant definition
    /// @dev Liquidity Sum Invariant: Expected Total Supply === Liquidity Sum
    /// Liquidity Sum = sum of available balance, deposit and owed deposit for all users
    /// @return bool Liquidity Sum Invariant holds true
    function _definitionLiquiditySumInvariant() internal view returns (bool) {
        int256 liquiditySum = _helperGetSuperTokenLiquiditySum(superToken);

        return int256(_expectedTotalSupply) == liquiditySum;
    }

    /// @notice AUM-RTB Accounting Invariant
    /// @dev AUM-RTB Accounting Invariant: AUM >= RTB Sum
    /// This invariant ensures that the RTB accounting is correct.
    /// @return bool AUM-RTB Accounting Invariant holds true
    function _definitionAumGtEqRtbSumInvariant() internal view returns (bool) {
        uint256 aum = _helperGetSuperTokenAum(superToken);
        int256 rtbSum = _helperGetSuperTokenLiquiditySum(superToken);

        return aum >= uint256(rtbSum);
    }

    /// @notice Protocol Solvency Invariant definition
    /// @dev Protocol Solvency Invariant: AUM >= Total Supply
    /// This invariant ensures that if all users want to downgrade their SuperToken, they can
    /// @return bool Protocol Solvency Invariant holds true
    function _defintionAumGtEqSuperTokenTotalSupplyInvariant() internal view returns (bool) {
        uint256 aum = _helperGetSuperTokenAum(superToken);
        uint256 totalSupply = superToken.totalSupply();

        return aum >= totalSupply;
    }

    /// @notice Net Flow Rate Sum Invariant definition
    /// @dev Net Flow Rate Sum Invariant: Sum of all net flow rates === 0
    /// @return bool Net Flow Rate Sum Invariant holds true
    function _definitionNetFlowRateSumInvariant() internal view returns (bool) {
        int96 netFlowRateSum = _helperGetNetFlowRateSum(superToken);
        return netFlowRateSum == 0;
    }

    /// @notice Asserts that the global invariants hold true
    function _assertGlobalInvariants() internal virtual {
        _assertInvariantLiquiditySum();
        _assertInvariantNetFlowRateSum();
        _assertInvariantAumGtEqRtbSum();
        _assertInvariantAumGtEqSuperTokenTotalSupply();
    }

    function _assertInvariantLiquiditySum() internal view {
        assertTrue(_definitionLiquiditySumInvariant(), "Invariant: Liquidity Sum Invariant");
    }

    function _assertInvariantNetFlowRateSum() internal view {
        assertTrue(_definitionNetFlowRateSumInvariant(), "Invariant: Net Flow Rate Sum Invariant");
    }

    function _assertInvariantAumGtEqRtbSum() internal view {
        assertTrue(_definitionAumGtEqRtbSumInvariant(), "Invariant: AUM > RTB Sum");
    }

    function _assertInvariantAumGtEqSuperTokenTotalSupply() internal view {
        assertTrue(_defintionAumGtEqSuperTokenTotalSupplyInvariant(), "Invariant: AUM > SuperToken Total Supply");
    }

    /// @notice Asserts that the real time balances for all active test accounts are expected
    /// @dev We also take a balance snapshot after each assertion
    /// @param superToken_ The SuperToken to check
    function _assertRealTimeBalances(ISuperToken superToken_) internal {
        address[] memory accounts = _listAccounts();
        for (uint i; i < accounts.length; ++i) {
            address account = accounts[i];
            RealtimeBalance memory balanceSnapshot = _balanceSnapshots[superToken_][account];
            (int256 avb, uint256 deposit, uint256 owedDeposit, uint256 currentTime) =
                superToken_.realtimeBalanceOfNow(account);
            int96 cfaNetFlowRate = superToken_.getCFANetFlowRate(account);

            // GDA Net Flow Rate is 0 for pools because this is not accounted for in the pools' RTB
            // however it is the disconnected flow rate for that pool
            int96 gdaNetFlowRate =
                sf.gda.isPool(superToken_, account) ? int96(0) : superToken_.getGDANetFlowRate(account);
            int96 netFlowRate = cfaNetFlowRate + gdaNetFlowRate;
            int256 amountFlowedSinceSnapshot = (currentTime - balanceSnapshot.timestamp).toInt256() * netFlowRate;
            int256 expectedAvb = balanceSnapshot.availableBalance + amountFlowedSinceSnapshot;

            assertEq(balanceSnapshot.deposit, deposit, "Real Time Balances: deposit");
            assertEq(balanceSnapshot.owedDeposit, owedDeposit, "Real Time Balances: owed deposit");
            assertEq(avb, expectedAvb, "Real Time Balances: available balance");

            _helperTakeBalanceSnapshot(superToken_, account);
        }
    }


    /// @notice Warps forwards 1 day and asserts balances of all testers and global invariants
    function _warpAndAssertAll(ISuperToken superToken_) internal virtual {
        vm.warp(block.timestamp + DEFAULT_WARP_TIME);
        _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    /// @notice Warps forwards `time` seconds and asserts balances of all testers and global invariants
    function _warpAndAssertAll(ISuperToken superToken_, uint256 time) internal virtual {
        vm.warp(block.timestamp + time);
        _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Assume Helpers
    //////////////////////////////////////////////////////////////////////////*/
    /// @notice Assume a valid flow rate
    /// @dev Flow rate must be greater than 0 and less than or equal to int32.max
    function _assumeValidFlowRate(int96 desiredFlowRate) internal pure returns (int96 flowRate) {
        vm.assume(desiredFlowRate > 0);
        vm.assume(desiredFlowRate <= int96(uint96(uint256(type(uint64).max))));
        flowRate = desiredFlowRate;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Helper Functions
    //////////////////////////////////////////////////////////////////////////*/

    // Getter Helpers

    /// @notice Gets the AUM for a SuperToken
    /// @dev This is dependent on the testSuperTokenType selected
    /// @param superToken_ The SuperToken to get the AUM for
    /// @return uint256 The AUM for the SuperToken
    function _helperGetSuperTokenAum(ISuperToken superToken_) internal view returns (uint256) {
        if (testSuperTokenType == TestSuperTokenType.WRAPPER_SUPER_TOKEN) {
            return _helperGetWrapperSuperTokenAUM(superToken_);
        } else if (testSuperTokenType == TestSuperTokenType.NATIVE_ASSET_SUPER_TOKEN) {
            return _helperGetNativeAssetSuperTokenAUM(superToken_);
        } else if (testSuperTokenType == TestSuperTokenType.PURE_SUPER_TOKEN) {
            return _helperGetPureSuperTokenAUM(superToken_);
        } else {
            return 0;
        }
    }

    /// @notice Gets the AUM for Wrapper SuperToken's
    /// @param superToken_ The SuperToken to get the AUM for
    /// @return uint256 The AUM for the SuperToken
    function _helperGetWrapperSuperTokenAUM(ISuperToken superToken_) internal view returns (uint256) {
        return ISuperToken(superToken_.getUnderlyingToken()).balanceOf(address(superToken_));
    }

    /// @notice Gets the AUM for Native Asset SuperToken's
    /// @param superToken_ The SuperToken to get the AUM for
    /// @return uint256 The AUM for the SuperToken
    function _helperGetNativeAssetSuperTokenAUM(ISuperToken superToken_) internal view returns (uint256) {
        return address(superToken_).balance;
    }

    /// @notice Gets the AUM for Pure SuperToken's
    /// @param superToken_ The SuperToken to get the AUM for
    /// @return uint256 The AUM for the SuperToken
    function _helperGetPureSuperTokenAUM(ISuperToken superToken_) internal view returns (uint256) {
        return superToken_.totalSupply();
    }

    /// @notice Gets the liquidity sum for a SuperToken
    /// @param superToken_ The SuperToken to get the liquidity sum for
    /// @return liquiditySum The liquidity sum for the SuperToken
    function _helperGetSuperTokenLiquiditySum(ISuperToken superToken_) internal view returns (int256 liquiditySum) {
        address[] memory accounts = _listAccounts();
        for (uint256 i = 0; i < accounts.length; ++i) {
            (int256 availableBalance, uint256 deposit, uint256 owedDeposit,) =
                superToken_.realtimeBalanceOfNow(accounts[i]);

            // FIXME: correct formula
            // liquiditySum += availableBalance + int256(deposit) - int256(owedDeposit);
            // current faulty one
            liquiditySum +=
                availableBalance + (deposit > owedDeposit ? int256(deposit) - int256(owedDeposit) : int256(0));
        }
    }

    /// @notice Gets the net flow rate sum for a SuperToken
    /// @dev This is the sum of net flow rates of the test accounts
    /// @param superToken_ The SuperToken to get the net flow rate sum for
    /// @return netFlowRateSum The net flow rate sum for the SuperToken
    function _helperGetNetFlowRateSum(ISuperToken superToken_) internal view returns (int96 netFlowRateSum) {
        address[] memory accounts = _listAccounts();
        for (uint256 i = 0; i < accounts.length; ++i) {
            netFlowRateSum += superToken_.getNetFlowRate(accounts[i]);
        }
    }

    /// @notice Tries to get an IDA subscription
    /// @dev This is needed in tests because it reverts if the subscriptio does not exist
    /// @param superToken_ The SuperToken to get the subscription for
    /// @param subId The ID of the subscription to get
    /// @return approved Whether the subscription exists
    /// @return units The units of the subscription
    /// @return pendingDistribution The pending distribution of the subscription
    function _helperTryGetSubscription(ISuperToken superToken_, bytes32 subId)
        internal
        view
        returns (bool approved, uint128 units, uint256 pendingDistribution)
    {
        try sf.ida.getSubscriptionByID(superToken_, subId) returns (
            address, uint32, bool isApproved, uint128 subUnits, uint256 pending
        ) {
            approved = isApproved;
            units = subUnits;
            pendingDistribution = pending;
        } catch { }
    }

    /// @notice Gets flow info and account flow info for a sender and receiver
    /// @param superToken_ The SuperToken to get the flow info for
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    /// @return flowInfo The flow info between a sender-receiver
    /// @return senderFlowInfo The account flow info for a sender
    /// @return receiverFlowInfo The account flow info for a receiver
    function _helperGetAllFlowInfo(ISuperToken superToken_, address sender, address receiver)
        internal
        view
        returns (
            ConstantFlowAgreementV1.FlowData memory flowInfo,
            ConstantFlowAgreementV1.FlowData memory senderFlowInfo,
            ConstantFlowAgreementV1.FlowData memory receiverFlowInfo
        )
    {
        flowInfo = _helperGetFlowInfo(superToken_, sender, receiver);
        senderFlowInfo = _helperGetAccountFlowInfo(superToken_, sender);
        receiverFlowInfo = _helperGetAccountFlowInfo(superToken_, receiver);
    }

    /// @notice Gets flow info for a sender and receiver
    /// @param superToken_ The SuperToken to get the flow info for
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    /// @return flowInfo The flow info between a sender-receiver
    function _helperGetFlowInfo(ISuperToken superToken_, address sender, address receiver)
        internal
        view
        returns (ConstantFlowAgreementV1.FlowData memory flowInfo)
    {
        (uint256 timestamp, int96 flowRate, uint256 deposit, uint256 owedDeposit) =
            superToken_.getFlowInfo(sender, receiver);
        flowInfo = ConstantFlowAgreementV1.FlowData(timestamp, flowRate, deposit, owedDeposit);
    }

    /// @notice Gets account flow info for an account
    /// @param superToken_ The SuperToken to get the account flow info for
    /// @param account The account to get the account flow info for
    /// @return flowInfo The account flow info for an account
    function _helperGetAccountFlowInfo(ISuperToken superToken_, address account)
        internal
        view
        returns (ConstantFlowAgreementV1.FlowData memory flowInfo)
    {
        (uint256 timestamp, int96 flowRate, uint256 deposit, uint256 owedDeposit) =
            sf.cfa.getAccountFlowInfo(superToken_, account);
        flowInfo = ConstantFlowAgreementV1.FlowData(timestamp, flowRate, deposit, owedDeposit);
    }

    // Time Warp Helpers
    /// @notice Warps to a timestamp where account is critical
    /// @param superToken_ The SuperToken
    /// @param account The account whose balance we want to "drain"
    /// @param secondsCritical The number of seconds to warp to after the account is critical
    function _helperWarpToCritical(ISuperToken superToken_, address account, uint256 secondsCritical) internal {
        int96 netFlowRate = superToken_.getNetFlowRate(account);
        assertTrue(netFlowRate < 0, "_helperWarpToCritical: netFlowRate must be less than 0 to reach critical");
        assertTrue(secondsCritical > 0, "_helperWarpToCritical: secondsCritical must be > 0 to reach critical");
        (int256 ab,,) = superToken_.realtimeBalanceOf(account, block.timestamp);
        int256 timeToZero = ab / netFlowRate < 0 ? (ab / netFlowRate) * -1 : ab / netFlowRate;
        uint256 amountToWarp = timeToZero.toUint256() + secondsCritical;
        vm.warp(block.timestamp + amountToWarp);
        assertTrue(superToken_.isAccountCriticalNow(account), "_helperWarpToCritical: account is not critical");
    }

    /// @notice Warps to a timestamp where account is insolvent
    /// @param superToken_ The SuperToken
    /// @param account The account whose balance we want to "drain"
    /// @param liquidationPeriod The liquidation period of the SuperToken
    /// @param secondsInsolvent The number of seconds to warp to after the account is insolvent
    function _helperWarpToInsolvency(
        ISuperToken superToken_,
        address account,
        uint256 liquidationPeriod,
        uint256 secondsInsolvent
    ) internal {
        int96 netFlowRate = superToken_.getNetFlowRate(account);
        assertTrue(netFlowRate < 0, "_helperWarpToCritical: netFlowRate must be less than 0 to reach critical");
        assertTrue(secondsInsolvent > 0, "_helperWarpToInsolvency: secondsInsolvent must be > 0 to reach insolvency");
        (int256 ab,,) = superToken_.realtimeBalanceOf(account, block.timestamp);
        int256 timeToZero = ab / netFlowRate < 0 ? (ab / netFlowRate) * -1 : ab / netFlowRate;
        uint256 amountToWarp = timeToZero.toUint256() + liquidationPeriod + secondsInsolvent;
        vm.warp(block.timestamp + amountToWarp);
        assertFalse(superToken_.isAccountSolventNow(account), "_helperWarpToInsolvency: account is still solvent");
    }

    // ID generator helpers
    /// @notice Generates a flow ID for a sender-receiver
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    /// @return id The flow ID for a sender-receiver
    function _generateFlowId(address sender, address receiver) private pure returns (bytes32 id) {
        return keccak256(abi.encode(sender, receiver));
    }

    /// @notice Generates a flowOperator ID for a sender-flowOperator
    /// @param sender The sender of the flow
    /// @param flowOperator The flowOperator of the flow
    /// @return id The flowOperator ID for a sender-flowOperator
    function _generateFlowOperatorId(address sender, address flowOperator) private pure returns (bytes32 id) {
        return keccak256(abi.encode("flowOperator", sender, flowOperator));
    }

    /// @notice Generates a publisher ID for a publisher-indexId
    /// @param publisher The publisher of the index
    /// @param indexId The indexId of the index
    /// @return iId The publisher ID for a publisher-indexId
    function _generatePublisherId(address publisher, uint32 indexId) private pure returns (bytes32 iId) {
        return keccak256(abi.encodePacked("publisher", publisher, indexId));
    }

    /// @notice Generates a subscription ID for a subscriber-publisherId
    /// @param subscriber The subscriber of the index
    /// @param iId The publisherId of the index
    /// @return sId The subscription ID for a subscriber-publisherId
    function _generateSubscriptionId(address subscriber, bytes32 iId) private pure returns (bytes32 sId) {
        return keccak256(abi.encodePacked("subscription", subscriber, iId));
    }

    // Write Helpers
    // Write Helpers - Testing State Changes
    /// @notice Takes a RTB snapshot of a SuperToken for an account
    /// @dev This must be called in the tests where a function is caled which settles balances in the protocol
    /// @param superToken_ The SuperToken to take the RTB snapshot for
    /// @param account The account to take the RTB snapshot for
    function _helperTakeBalanceSnapshot(ISuperToken superToken_, address account) internal {
        (int256 avb, uint256 deposit, uint256 owedDeposit, uint256 time) = superToken_.realtimeBalanceOfNow(account);
        RealtimeBalance memory balanceSnapshot = RealtimeBalance(avb, deposit, owedDeposit, time);
        _balanceSnapshots[superToken_][account] = balanceSnapshot;
    }

    /// @notice Adds inflows and outflows to the test state
    /// @dev This must be called whenever a flow is created
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    function _helperAddInflowsAndOutflowsToTestState(address sender, address receiver) internal {
        bytes32 flowId = _generateFlowId(sender, receiver);

        EnumerableSet.Bytes32Set storage outflows = _outflows[superToken][sender];
        if (!outflows.contains(flowId)) {
            outflows.add(flowId);
        }

        EnumerableSet.Bytes32Set storage inflows = _inflows[superToken][receiver];
        if (!inflows.contains(flowId)) {
            inflows.add(flowId);
        }
    }

    /// @notice Removes inflows and outflows from the test state
    /// @dev This must be called whenever a flow is deleted
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    function _helperRemoveInflowsAndOutflowsFromTestState(address sender, address receiver) internal {
        bytes32 flowId = _generateFlowId(sender, receiver);

        EnumerableSet.Bytes32Set storage outflows = _outflows[superToken][sender];
        if (outflows.contains(flowId)) {
            outflows.remove(flowId);
        }

        EnumerableSet.Bytes32Set storage inflows = _inflows[superToken][receiver];
        if (inflows.contains(flowId)) {
            inflows.remove(flowId);
        }
    }

    // Write Helpers - SuperToken
    function _helperTransferAll(ISuperToken superToken_, address sender, address receiver) internal {
        vm.startPrank(sender);
        superToken_.transferAll(receiver);
        vm.stopPrank();

        _helperTakeBalanceSnapshot(superToken_, sender);
        _helperTakeBalanceSnapshot(superToken_, receiver);
    }

    function _helperDeploySuperTokenAndInitialize(
        ISuperToken previousSuperToken,
        IERC20 underlyingToken,
        uint8 underlyingDecimals,
        string memory name,
        string memory symbol,
        address _admin
    ) internal returns (SuperToken localSuperToken) {
        localSuperToken = new SuperToken(
            sf.host,
            IConstantOutflowNFT(address(0)),
            IConstantInflowNFT(address(0)),
            previousSuperToken.POOL_ADMIN_NFT(),
            previousSuperToken.POOL_MEMBER_NFT()
        );
        localSuperToken.initializeWithAdmin(underlyingToken, underlyingDecimals, name, symbol, _admin);
    }

    // Write Helpers - ConstantFlowAgreementV1
    /// @notice Creates a flow between a sender and receiver at a given flow rate
    /// @dev This helper assumes a valid flow rate with vm.assume and asserts that state has updated as expected.
    /// We assert:
    /// - The flow info is properly set (flow rate, updated, deposit and owedDeposit are set as expected)
    /// - The account flow info has been updated as expected for sender and receiver (delta applied to net flow rates +
    /// deposit for sender)
    /// - The balance of all test accounts has been updated as expected (balanceSnapshot + streamedAmountSince)
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    /// @param flowRate The desired flow rate
    function _helperCreateFlow(ISuperToken superToken_, address sender, address receiver, int96 flowRate) internal {
        flowRate = _assumeValidFlowRate(flowRate);

        // Get Flow Data Before
        (
            ConstantFlowAgreementV1.FlowData memory flowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory senderFlowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory receiverFlowInfoBefore
        ) = _helperGetAllFlowInfo(superToken_, sender, receiver);

        // Execute Create Flow
        vm.startPrank(sender);
        superToken_.createFlow(receiver, flowRate);
        vm.stopPrank();

        // Update Test State
        {
            _helperAddInflowsAndOutflowsToTestState(sender, receiver);

            _helperTakeBalanceSnapshot(superToken_, sender);
            _helperTakeBalanceSnapshot(superToken_, receiver);
        }

        // Assert Flow Data + Account Flow Info for sender/receiver
        {
            int96 flowRateDelta = flowRate - flowInfoBefore.flowRate;
            _assertFlowData(superToken_, sender, receiver, flowRate, block.timestamp, 0);
            _assertAccountFlowInfo(sender, flowRateDelta, senderFlowInfoBefore, true);
            _assertAccountFlowInfo(receiver, flowRateDelta, receiverFlowInfoBefore, false);
        }

        // Assert RTB for all users
        _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    /// @notice Updates a flow between a sender and receiver at a given flow rate
    /// @dev This helper assumes a valid flow rate with vm.assume and asserts that state has updated as expected.
    /// We assert:
    /// - The flow info is properly set (flow rate, updated, deposit and owedDeposit are set as expected)
    /// - The account flow info has been updated as expected for sender and receiver (delta applied to net flow rates +
    /// deposit for sender)
    /// - The balance of all test accounts has been updated as expected (balanceSnapshot + streamedAmountSince)
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    /// @param flowRate The desired flow rate
    function _helperUpdateFlow(ISuperToken superToken_, address sender, address receiver, int96 flowRate) internal {
        flowRate = _assumeValidFlowRate(flowRate);

        // Get Flow Data Before
        (
            ConstantFlowAgreementV1.FlowData memory flowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory senderFlowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory receiverFlowInfoBefore
        ) = _helperGetAllFlowInfo(superToken_, sender, receiver);

        // Execute Update Flow
        vm.startPrank(sender);
        superToken_.updateFlow(receiver, flowRate);
        vm.stopPrank();

        // Update Test State
        {
            _helperTakeBalanceSnapshot(superToken_, sender);
            _helperTakeBalanceSnapshot(superToken_, receiver);
        }

        // Assert Flow Data + Account Flow Info for sender/receiver
        {
            int96 flowRateDelta = flowRate - flowInfoBefore.flowRate;
            _assertFlowData(superToken_, sender, receiver, flowRate, block.timestamp, 0);
            _assertAccountFlowInfo(sender, flowRateDelta, senderFlowInfoBefore, true);
            _assertAccountFlowInfo(receiver, flowRateDelta, receiverFlowInfoBefore, false);
        }

        // Assert RTB for all users
        _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    /// @notice Deletes a flow between a sender and receiver
    /// @dev This helper assumes a valid flow rate with vm.assume and asserts that state has updated as expected.
    /// We assert:
    /// - The flow info is properly set (flow rate, updated, deposit and owedDeposit are set as expected)
    /// - The account flow info has been updated as expected for sender and receiver (delta applied to net flow rates +
    /// deposit for sender)
    /// - The balance of all test accounts has been updated as expected (balanceSnapshot + streamedAmountSince)
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    function _helperDeleteFlow(ISuperToken superToken_, address caller, address sender, address receiver) internal {
        // Get Flow Data Before
        (
            ConstantFlowAgreementV1.FlowData memory flowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory senderFlowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory receiverFlowInfoBefore
        ) = _helperGetAllFlowInfo(superToken_, sender, receiver);

        // Execute Delete Flow
        vm.startPrank(caller);
        superToken_.deleteFlow(sender, receiver);
        vm.stopPrank();

        // Update Test State
        {
            _helperRemoveInflowsAndOutflowsFromTestState(sender, receiver);

            _helperTakeBalanceSnapshot(superToken_, sender);
            _helperTakeBalanceSnapshot(superToken_, receiver);

            if (caller != sender && caller != receiver) {
                _helperTakeBalanceSnapshot(superToken_, caller);
            }

            // Get the default reward address for the token and update their snapshot too in the
            // liquidation case
            address rewardAddress = sf.governance.getRewardAddress(sf.host, superToken_);
            _helperTakeBalanceSnapshot(superToken_, rewardAddress);
        }

        // Assert Flow Data + Account Flow Info for sender/receiver
        {
            int96 flowRateDelta = -flowInfoBefore.flowRate;
            _assertFlowDataIsEmpty(superToken_, sender, receiver);
            _assertAccountFlowInfo(sender, flowRateDelta, senderFlowInfoBefore, true);
            _assertAccountFlowInfo(receiver, flowRateDelta, receiverFlowInfoBefore, false);
        }

        // Assert RTB for all users
        _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    /// @notice Creates an ACL flow by the opeartor between a sender and receiver at a given flow rate
    /// @dev This helper assumes a valid flow rate with vm.assume and asserts that state has updated as expected.
    /// We assert:
    /// - The flow info is properly set (flow rate, updated, deposit and owedDeposit are set as expected)
    /// - The account flow info has been updated as expected for sender and receiver (delta applied to net flow rates +
    /// deposit for sender)
    /// - The balance of all test accounts has been updated as expected (balanceSnapshot + streamedAmountSince)
    /// - The flow rate allowance has been deducted accordingly (only if not max allowancea)
    /// @param operator The flow operator
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    /// @param flowRate The desired flow rate
    function _helperCreateFlowFrom(
        ISuperToken superToken_,
        address operator,
        address sender,
        address receiver,
        int96 flowRate
    ) internal {
        flowRate = _assumeValidFlowRate(flowRate);

        // Get Flow Data Before
        (
            ConstantFlowAgreementV1.FlowData memory flowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory senderFlowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory receiverFlowInfoBefore
        ) = _helperGetAllFlowInfo(superToken, sender, receiver);

        // Get Flow Operator Data Before
        (,,, int96 flowRateAllowanceBefore) = superToken_.getFlowPermissions(sender, operator);

        // Execute Create Flow as FlowOperator
        vm.startPrank(operator);
        superToken_.createFlowFrom(sender, receiver, flowRate);
        vm.stopPrank();

        // Update Test State
        {
            _helperAddInflowsAndOutflowsToTestState(sender, receiver);

            _helperTakeBalanceSnapshot(superToken, sender);
            _helperTakeBalanceSnapshot(superToken, receiver);
        }

        // Assert Flow Data + Account Flow Info for sender/receiver
        int96 flowRateDelta = flowRate - flowInfoBefore.flowRate;
        {
            _assertFlowData(superToken_, sender, receiver, flowRate, block.timestamp, 0);
            _assertAccountFlowInfo(sender, flowRateDelta, senderFlowInfoBefore, true);
            _assertAccountFlowInfo(receiver, flowRateDelta, receiverFlowInfoBefore, false);
        }

        // Assert FlowOperator Data
        {
            (,,, int96 flowRateAllowanceAfter) = superToken_.getFlowPermissions(sender, operator);
            if (flowRateAllowanceBefore == type(int96).max) {
                assertEq(flowRateAllowanceAfter, flowRateAllowanceBefore, "CreateFlowFrom: Max flow allowance deducted");
            } else {
                assertEq(
                    flowRateAllowanceAfter,
                    flowRateAllowanceBefore - flowRateDelta,
                    "CreateFlowFrom: Flow allowance not deducted"
                );
            }
        }

        // Assert RTB for all users
        _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    /// @notice Updates an ACL flow by the opeartor between a sender and receiver at a given flow rate
    /// @dev This helper assumes a valid flow rate with vm.assume and asserts that state has updated as expected.
    /// We assert:
    /// - The flow info is properly set (flow rate, updated, deposit and owedDeposit are set as expected)
    /// - The account flow info has been updated as expected for sender and receiver (delta applied to net flow rates +
    /// deposit for sender)
    /// - The balance of all test accounts has been updated as expected (balanceSnapshot + streamedAmountSince)
    /// - The flow rate allowance has been deducted accordingly (only if flow rate > current flow rate)
    /// @param operator The flow operator
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    /// @param flowRate The desired flow rate
    function _helperUpdateFlowFrom(
        ISuperToken superToken_,
        address operator,
        address sender,
        address receiver,
        int96 flowRate
    ) internal {
        flowRate = _assumeValidFlowRate(flowRate);

        // Get Flow Data Before
        (
            ConstantFlowAgreementV1.FlowData memory flowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory senderFlowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory receiverFlowInfoBefore
        ) = _helperGetAllFlowInfo(superToken, sender, receiver);

        // Get Flow Operator Data Before
        (,,, int96 flowRateAllowanceBefore) = superToken_.getFlowPermissions(sender, operator);

        // Execute Update Flow as FlowOperator
        vm.startPrank(operator);
        superToken_.updateFlowFrom(sender, receiver, flowRate);
        vm.stopPrank();

        // Update Test State
        {
            _helperTakeBalanceSnapshot(superToken, sender);
            _helperTakeBalanceSnapshot(superToken, receiver);
        }

        // Assert Flow Data + Account Flow Info for sender/receiver
        int96 flowRateDelta = flowRate - flowInfoBefore.flowRate;
        {
            _assertFlowData(superToken_, sender, receiver, flowRate, block.timestamp, 0);
            _assertAccountFlowInfo(sender, flowRateDelta, senderFlowInfoBefore, true);
            _assertAccountFlowInfo(receiver, flowRateDelta, receiverFlowInfoBefore, false);
        }

        // Assert FlowOperator Data
        {
            (,,, int96 flowRateAllowanceAfter) = superToken_.getFlowPermissions(sender, operator);
            if (flowRateAllowanceBefore == type(int96).max) {
                assertEq(flowRateAllowanceAfter, flowRateAllowanceBefore, "UpdateFlowFrom: Max flow allowance deducted");
            } else {
                assertEq(
                    flowRateAllowanceAfter,
                    flowRateAllowanceBefore - flowRateDelta,
                    "UpdateFlowFrom: Flow allowance not deducted"
                );
            }
        }

        // Assert RTB for all users
        _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();

        // Assert Global Invariants
        _assertGlobalInvariants();

        // TODO
        // Assert that flow rate allowance has been deducted accordingly (if flow rate is increased by delta amount)
    }

    /// @notice Deletes an ACL flow by the opeartor between a sender and receiver
    /// @dev This helper assumes a valid flow rate with vm.assume and asserts that state has updated as expected.
    /// We assert:
    /// - The flow info is properly set (flow rate, updated, deposit and owedDeposit are set as expected)
    /// - The account flow info has been updated as expected for sender and receiver (delta applied to net flow rates +
    /// deposit for sender)
    /// - The balance of all test accounts has been updated as expected (balanceSnapshot + streamedAmountSince)
    /// - The flow rate allowance has been deducted accordingly (no deduction)
    /// @param operator The flow operator
    /// @param sender The sender of the flow
    /// @param receiver The receiver of the flow
    function _helperDeleteFlowFrom(ISuperToken superToken_, address operator, address sender, address receiver)
        internal
    {
        // Get Flow Data Before
        (
            ConstantFlowAgreementV1.FlowData memory flowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory senderFlowInfoBefore,
            ConstantFlowAgreementV1.FlowData memory receiverFlowInfoBefore
        ) = _helperGetAllFlowInfo(superToken, sender, receiver);

        // Get Flow Operator Data Before
        (,,, int96 flowRateAllowanceBefore) = superToken_.getFlowPermissions(sender, operator);

        // Execute Delete Flow as FlowOperator
        vm.startPrank(operator);
        superToken_.deleteFlowFrom(sender, receiver);
        vm.stopPrank();

        // Update Test State
        {
            _helperRemoveInflowsAndOutflowsFromTestState(sender, receiver);

            _helperTakeBalanceSnapshot(superToken, sender);
            _helperTakeBalanceSnapshot(superToken, receiver);
        }

        // Assert Flow Data + Account Flow Info for sender/receiver
        int96 flowRateDelta = -flowInfoBefore.flowRate;
        {
            _assertFlowDataIsEmpty(superToken_, sender, receiver);
            _assertAccountFlowInfo(sender, flowRateDelta, senderFlowInfoBefore, true);
            _assertAccountFlowInfo(receiver, flowRateDelta, receiverFlowInfoBefore, false);
        }

        // Assert FlowOperator Data
        {
            (,,, int96 flowRateAllowanceAfter) = superToken_.getFlowPermissions(sender, operator);
            assertEq(flowRateAllowanceAfter, flowRateAllowanceBefore, "DeleteFlowFrom: Flow allowance deducted");
        }

        // Assert RTB for all users
        _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    // Write Helpers - GeneralDistributionAgreementV1/SuperfluidPool

    function _helperCreatePool(
        ISuperToken _superToken,
        address _caller,
        address _poolAdmin,
        bool _useForwarder,
        PoolConfig memory _poolConfig
    ) internal returns (ISuperfluidPool localPool) {
        vm.startPrank(_caller);
        if (!_useForwarder) {
            localPool = SuperfluidPool(address(sf.gda.createPool(_superToken, _poolAdmin, _poolConfig)));
        } else {
            (, localPool) = sf.gdaV1Forwarder.createPool(_superToken, _poolAdmin, _poolConfig);
        }
        vm.stopPrank();
        _assertPoolCreation(localPool, _useForwarder, _superToken, _poolAdmin, false, PoolERC20Metadata("", "", 0));
    }

    function _helperCreatePoolWithCustomERC20Metadata(
        ISuperToken _superToken,
        address _caller,
        address _poolAdmin,
        PoolConfig memory _poolConfig,
        PoolERC20Metadata memory _poolERC20Metadata
    ) internal returns (ISuperfluidPool localPool) {
        vm.startPrank(_caller);
        localPool = SuperfluidPool(address(sf.gda.createPoolWithCustomERC20Metadata(
            _superToken, _poolAdmin, _poolConfig, _poolERC20Metadata)));
        vm.stopPrank();
        _assertPoolCreation(localPool, false, _superToken, _poolAdmin, true, _poolERC20Metadata);
    }

    // Assert Pool Creation was properly handled
    function _assertPoolCreation(
        ISuperfluidPool localPool,
        bool _useForwarder,
        ISuperToken _superToken,
        address _poolAdmin,
        bool _useCustomERC20Metadata,
        PoolERC20Metadata memory _poolERC20Metadata
    ) private {
        _addAccount(address(localPool));
        address poolAdmin = localPool.admin();
        {
            bool isPool = _useForwarder
                ? sf.gdaV1Forwarder.isPool(_superToken, address(localPool))
                : sf.gda.isPool(_superToken, address(localPool));
            assertTrue(isPool, "GDAv1.t: Created pool is not pool");
            assertEq(poolAdmin, _poolAdmin, "GDAv1.t: Pool admin is incorrect");
            assertEq(address(localPool.superToken()), address(_superToken), "GDAv1.t: Pool super token is incorrect");
        }

        IPoolAdminNFT poolAdminNft = SuperToken(address(_superToken)).POOL_ADMIN_NFT();
        uint256 tokenId = poolAdminNft.getTokenId(address(localPool), _poolAdmin);

        // Assert PoolAdminNFT Owner is expected
        assertEq(
            poolAdminNft.ownerOf(tokenId), _poolAdmin, "_helperCreatePool: Pool Admin NFT is not owned by pool admin"
        );

        // Assert PoolAdminNFTData is expected
        {
            IPoolAdminNFT.PoolAdminNFTData memory poolAdminData = poolAdminNft.poolAdminDataByTokenId(tokenId);
            assertEq(poolAdminData.pool, address(localPool), "_helperCreatePool: Pool Admin NFT pool mismatch");
            assertEq(poolAdminData.admin, _poolAdmin, "_helperCreatePool: Pool Admin NFT admin mismatch");
        }

        // Assert Admin is PoolAdjustment Flow receiver
        {
            (address adjustmentFlowRecipient,,) = _useForwarder
                ? sf.gdaV1Forwarder.getPoolAdjustmentFlowInfo(localPool)
                : sf.gda.getPoolAdjustmentFlowInfo(localPool);
            assertEq(poolAdmin, adjustmentFlowRecipient, "_helperCreatePool: Incorrect pool adjustment flow receiver");
        }

        // Assert ERC20 Metadata as expected
        {
            if (_useCustomERC20Metadata) {
                assertEq(localPool.name(), _poolERC20Metadata.name, "_helperCreatePool: Pool ERC20 Metadata name mismatch");
                assertEq(localPool.symbol(), _poolERC20Metadata.symbol, "_helperCreatePool: Pool ERC20 Metadata symbol mismatch");
                assertEq(localPool.decimals(), _poolERC20Metadata.decimals, "_helperCreatePool: Pool ERC20 Metadata decimals mismatch");
            } else {
                // expect the default/fallback values hardcoded in the pool contract
                assertEq(localPool.name(), "Superfluid Pool", "_helperCreatePool: Pool ERC20 Metadata name mismatch");
                assertEq(localPool.symbol(), "POOL", "_helperCreatePool: Pool ERC20 Metadata symbol mismatch");
                assertEq(localPool.decimals(), 0, "_helperCreatePool: Pool ERC20 Metadata decimals mismatch");
            }
        }
    }

    function _helperCreatePool(ISuperToken _superToken, address _caller, address _poolAdmin)
        internal
        returns (ISuperfluidPool)
    {
        return _helperCreatePool(_superToken, _caller, _poolAdmin, false, poolConfig);
    }

    function _helperUpdateMemberUnits(ISuperfluidPool pool_, address caller_, address member_, uint128 newUnits_)
        internal
    {
        _StackVars_UseBools memory useBools_;
        _helperUpdateMemberUnits(pool_, caller_, member_, newUnits_, useBools_);
    }

    function _updateMemberUnits(
        ISuperfluidPool pool_,
        ISuperToken /*poolSuperToken*/,
        address caller_,
        address member_,
        uint128 newUnits_,
        _StackVars_UseBools memory useBools_
    ) internal {
        vm.startPrank(caller_);
        if (useBools_.useGDA) {
            if (useBools_.useForwarder) {
                sf.gdaV1Forwarder.updateMemberUnits(pool_, member_, newUnits_, new bytes(0));
            } else {
                pool_.updateMemberUnits(member_, newUnits_);
            }
        } else {
            pool_.updateMemberUnits(member_, newUnits_);
        }
        vm.stopPrank();
    }

    function _helperUpdateMemberUnits(
        ISuperfluidPool pool_,
        address caller_,
        address member_,
        uint128 newUnits_,
        _StackVars_UseBools memory useBools_
    ) internal {
        // there is a hard restriction in which total units must never exceed type(int96).max
        vm.assume(newUnits_ < type(uint72).max);
        ISuperToken poolSuperToken = ISuperToken(address(pool_.superToken()));

        (bool isConnected, int256 oldUnits,) = _helperGetMemberPoolState(pool_, member_);

        PoolUnitData memory poolUnitDataBefore = _helperGetPoolUnitsData(pool_);

        (int256 balanceBefore,,,) = poolSuperToken.realtimeBalanceOfNow(member_);
        {
            _updateMemberUnits(pool_, poolSuperToken, caller_, member_, newUnits_, useBools_);
        }
        PoolUnitData memory poolUnitDataAfter = _helperGetPoolUnitsData(pool_);

        {
            _helperTakeBalanceSnapshot(ISuperToken(address(poolSuperToken)), member_);
        }

        assertEq(pool_.getUnits(member_), newUnits_, "GDAv1.t: Members' units incorrectly set");

        // Assert that pending balance didn't change if user is disconnected
        if (!isConnected) {
            (int256 balanceAfter,,,) = poolSuperToken.realtimeBalanceOfNow(member_);
            assertEq(
                balanceAfter, balanceBefore, "_helperUpdateMemberUnits: Pending balance changed"
            );
        }

        // Assert that the flow rate for a member is updated accordingly
        {
            uint128 totalUnits = pool_.getTotalUnits();
            uint128 flowRatePerUnit = totalUnits == 0 ? 0 : uint128(uint96(pool_.getTotalFlowRate())) / totalUnits;
            assertEq(
                flowRatePerUnit * newUnits_,
                uint128(uint96(pool_.getMemberFlowRate(member_))),
                "_helperUpdateMemberUnits: Member flow rate incorrect"
            );
        }

        // Update Expected Member Data
        if (newUnits_ > 0) {
            // @note You are only considered a member if you are given units
            _poolMembers[address(pool_)].add(member_);
        }

        // Assert Pool Total, Connected and Disconnect Units are correct
        {
            int256 unitsDelta = uint256(newUnits_).toInt256() - oldUnits;
            assertEq(
                uint256(uint256(poolUnitDataBefore.totalUnits).toInt256() + unitsDelta),
                poolUnitDataAfter.totalUnits,
                "_helperUpdateMemberUnits: Pool total units incorrect"
            );
            assertEq(
                uint256(uint256(poolUnitDataBefore.connectedUnits).toInt256() + (isConnected ? unitsDelta : int128(0))),
                poolUnitDataAfter.connectedUnits,
                "_helperUpdateMemberUnits: Pool connected units incorrect"
            );
            assertEq(
                uint256(
                    uint256(poolUnitDataBefore.disconnectedUnits).toInt256() + (isConnected ? int128(0) : unitsDelta)
                ),
                poolUnitDataAfter.disconnectedUnits,
                "_helperUpdateMemberUnits: Pool disconnected units incorrect"
            );
        }

        // Assert Pool Member NFT is minted/burned
        _assertPoolMemberNFT(poolSuperToken, pool_, member_, newUnits_);

        // Assert RTB for all users
        // _assertRealTimeBalances(ISuperToken(address(poolSuperToken)));
    }

    function _helperConnectPool(address caller_, ISuperToken superToken_, ISuperfluidPool pool_, bool useForwarder_)
        internal
    {
        (bool isConnectedBefore, int256 oldUnits, int96 oldFlowRate) = _helperGetMemberPoolState(pool_, caller_);

        PoolUnitData memory poolUnitDataBefore = _helperGetPoolUnitsData(pool_);
        PoolFlowRateData memory poolFlowRateDataBefore = _helperGetPoolFlowRatesData(pool_);

        vm.startPrank(caller_);
        if (useForwarder_) {
            sf.gdaV1Forwarder.connectPool(pool_, "");
        } else {
            sf.host.callAgreement(
                sf.gda,
                abi.encodeWithSelector(IGeneralDistributionAgreementV1.connectPool.selector, pool_, ""),
                new bytes(0)
            );
        }
        vm.stopPrank();

        PoolUnitData memory poolUnitDataAfter = _helperGetPoolUnitsData(pool_);
        PoolFlowRateData memory poolFlowRateDataAfter = _helperGetPoolFlowRatesData(pool_);

        {
            _helperTakeBalanceSnapshot(superToken_, caller_);
        }

        bool isMemberConnected = useForwarder_
            ? sf.gdaV1Forwarder.isMemberConnected(pool_, caller_)
            : sf.gda.isMemberConnected(pool_, caller_);
        assertEq(isMemberConnected, true, "GDAv1.t: Member not connected");

        // Assert connected units delta for the pool
        {
            assertEq(
                isConnectedBefore ? 0 : uint256(oldUnits),
                poolUnitDataAfter.connectedUnits - poolUnitDataBefore.connectedUnits,
                "_helperConnectPool: Pool connected units incorrect"
            );
        }

        // Assert connected and disconnected flow rate for the pool
        {
            assertEq(
                poolFlowRateDataBefore.totalConnectedFlowRate + (isConnectedBefore ? int96(0) : oldFlowRate),
                poolFlowRateDataAfter.totalConnectedFlowRate,
                "_helperConnectPool: Pool connected flow rate incorrect"
            );
            assertEq(
                poolFlowRateDataBefore.totalDisconnectedFlowRate - (isConnectedBefore ? int96(0) : oldFlowRate),
                poolFlowRateDataAfter.totalDisconnectedFlowRate,
                "_helperConnectPool: Pool disconnected flow rate incorrect"
            );
        }
        // Assert RTB for all users
        // _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    function _helperConnectPool(address caller_, ISuperToken superToken_, ISuperfluidPool pool_) internal {
        _helperConnectPool(caller_, superToken_, pool_, false);
    }

    function _helperDisconnectPool(address caller_, ISuperToken superToken_, ISuperfluidPool pool_, bool useForwarder_)
        internal
    {
        (bool isConnectedBefore, int256 oldUnits, int96 oldFlowRate) = _helperGetMemberPoolState(pool_, caller_);

        PoolUnitData memory poolUnitDataBefore = _helperGetPoolUnitsData(pool_);
        PoolFlowRateData memory poolFlowRateDataBefore = _helperGetPoolFlowRatesData(pool_);

        vm.startPrank(caller_);
        if (useForwarder_) {
            sf.gdaV1Forwarder.disconnectPool(pool_, "");
        } else {
            sf.host.callAgreement(sf.gda, abi.encodeCall(sf.gda.disconnectPool, (pool_, new bytes(0))), new bytes(0));
        }
        vm.stopPrank();

        PoolUnitData memory poolUnitDataAfter = _helperGetPoolUnitsData(pool_);
        PoolFlowRateData memory poolFlowRateDataAfter = _helperGetPoolFlowRatesData(pool_);

        {
            _helperTakeBalanceSnapshot(superToken_, caller_);
        }

        assertEq(
            sf.gda.isMemberConnected(pool_, caller_),
            false,
            "GDAv1.t D/C: Member not disconnected"
        );

        // Assert disconnected units delta for the pool
        {
            assertEq(
                isConnectedBefore ? uint256(oldUnits) : 0,
                poolUnitDataAfter.disconnectedUnits - poolUnitDataBefore.disconnectedUnits,
                "_helperDisconnectPool: Pool disconnected units incorrect"
            );
        }
        {
            assertEq(
                poolFlowRateDataBefore.totalConnectedFlowRate - (isConnectedBefore ? oldFlowRate : int96(0)),
                poolFlowRateDataAfter.totalConnectedFlowRate,
                "_helperDisconnectPool: Pool connected flow rate incorrect"
            );
            assertEq(
                poolFlowRateDataBefore.totalDisconnectedFlowRate + (isConnectedBefore ? oldFlowRate : int96(0)),
                poolFlowRateDataAfter.totalDisconnectedFlowRate,
                "_helperDisconnectPool: Pool disconnected flow rate incorrect"
            );
        }

        // Assert RTB for all users
        // _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    function _helperDisconnectPool(address caller_, ISuperToken superToken_, ISuperfluidPool pool_) internal {
        _helperDisconnectPool(caller_, superToken_, pool_, false);
    }

    function _helperDistributeViaGDA(
        ISuperToken superToken_,
        address caller_,
        address from_,
        ISuperfluidPool pool_,
        uint256 requestedAmount,
        bool useForwarder
    ) internal {
        (int256 fromRTBBefore,,,) = superToken.realtimeBalanceOfNow(from_);

        uint256 actualAmountDistributed = useForwarder
            ? sf.gdaV1Forwarder.estimateDistributionActualAmount(superToken, from_, pool_, requestedAmount)
            : sf.gda.estimateDistributionActualAmount(superToken, from_, pool_, requestedAmount);

        address[] memory members = _poolMembers[address(pool_)].values();
        uint256[] memory memberBalancesBefore = new uint256[](members.length);
        uint256[] memory memberClaimableBefore = new uint256[](members.length);

        for (uint256 i = 0; i < members.length; ++i) {
            (int256 memberRTB,,,) = superToken.realtimeBalanceOfNow(members[i]);
            memberBalancesBefore[i] = uint256(memberRTB);
            (int256 claimable,) = pool_.getClaimableNow(members[i]);
            memberClaimableBefore[i] = uint256(claimable);
        }

        {
            vm.startPrank(caller_);
            if (useForwarder) {
                sf.gdaV1Forwarder.distribute(superToken_, from_, pool_, requestedAmount, new bytes(0));
            } else {
                superToken_.distribute(from_, pool_, requestedAmount);
            }
            vm.stopPrank();
        }

        {
            _helperTakeBalanceSnapshot(superToken_, from_);
        }

        uint256 amountPerUnit = pool_.getTotalUnits() > 0 ? actualAmountDistributed / pool_.getTotalUnits() : 0;

        // Assert Distributor RTB
        {
            (int256 fromRTBAfter,,,) = superToken.realtimeBalanceOfNow(from_);
            // If the distributor is a connected member themselves, they will receive the units
            // they have just distributed
            uint256 amountReceivedInitial = sf.gda.isMemberConnected(pool_, from_)
                ? uint256(pool_.getUnits(from_)) * amountPerUnit
                : 0;
            assertEq(
                fromRTBAfter,
                fromRTBBefore - int256(actualAmountDistributed) + int256(amountReceivedInitial),
                "GDAv1.t D: Distributor RTB incorrect"
            );
        }

        if (members.length == 0) return;

        // Assert Members RTB
        for (uint256 i; i < members.length; ++i) {
            (int256 memberRTB,,,) = superToken.realtimeBalanceOfNow(members[i]);
            bool memberConnected = sf.gda.isMemberConnected(pool_, members[i]);

            uint256 amountReceived = uint256(pool_.getUnits(members[i])) * amountPerUnit;
            if (memberConnected) {
                if (members[i] == from_) {
                    assertEq(
                        memberRTB,
                        int256(memberBalancesBefore[i]) - int256(actualAmountDistributed) + int256(amountReceived),
                        "GDAv1.t D: Distributor who is Member RTB incorrect"
                    );
                } else {
                    assertEq(
                        uint256(memberRTB), memberBalancesBefore[i] + amountReceived, "GDAv1.t D: Member RTB incorrect"
                    );
                }
            } else {
                (int256 claimable,) = pool_.getClaimableNow(members[i]);
                assertEq(
                    uint256(claimable),
                    amountReceived + uint256(memberClaimableBefore[i]),
                    "GDAv1.t D: Member claimable incorrect"
                );
            }
        }

        // Assert RTB for all users
        // _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    function _helperDistributeViaGDA(
        ISuperToken superToken_,
        address caller_,
        address from_,
        ISuperfluidPool pool_,
        uint256 requestedAmount
    ) internal {
        _helperDistributeViaGDA(superToken_, caller_, from_, pool_, requestedAmount, false);
    }

    function _helperDistributeFlow(
        ISuperToken superToken_,
        address caller,
        address from,
        ISuperfluidPool pool_,
        int96 requestedFlowRate,
        bool useForwarder
    ) internal {
        (int96 actualFlowRate, int96 totalDistributionFlowRate) = useForwarder
            ? sf.gdaV1Forwarder.estimateFlowDistributionActualFlowRate(superToken_, from, pool_, requestedFlowRate)
            : sf.gda.estimateFlowDistributionActualFlowRate(superToken_, from, pool_, requestedFlowRate);

        address[] memory members = _poolMembers[address(pool_)].values();
        int96[] memory memberFlowRatesBefore = new int96[](members.length);

        for (uint256 i = 0; i < members.length; ++i) {
            int96 memberFlowRate = pool_.getMemberFlowRate(members[i]);
            memberFlowRatesBefore[i] = memberFlowRate;
        }

        vm.startPrank(caller);
        if (useForwarder) {
            sf.gdaV1Forwarder.distributeFlow(superToken_, from, pool_, requestedFlowRate, new bytes(0));
        } else {
            superToken_.distributeFlow(from, pool_, requestedFlowRate);
        }
        vm.stopPrank();

        {
            _helperTakeBalanceSnapshot(superToken_, from);
        }

        int96 poolTotalFlowRateAfter = pool_.getTotalFlowRate();
        {
            // Assert distributor flow rate
            int96 fromToPoolFlowRateAfter = useForwarder
                ? sf.gdaV1Forwarder.getFlowDistributionFlowRate(superToken_, from, pool_)
                : sf.gda.getFlowRate(superToken_, from, pool_);
            assertEq(
                fromToPoolFlowRateAfter,
                actualFlowRate,
                "_helperDistributeFlow: from flow rate should be actual flow rate"
            );

            // Assert pool total flow rate
            assertEq(
                poolTotalFlowRateAfter,
                totalDistributionFlowRate,
                "_helperDistributeFlow: pool total flow rate != total distribution flow rate"
            );
        }

        {
            if (members.length == 0) return;
            uint128 poolTotalUnitsAfter = pool_.getTotalUnits();
            int96 flowRatePerUnit = poolTotalUnitsAfter == 0
                ? int96(0)
                : poolTotalFlowRateAfter / uint256(poolTotalUnitsAfter).toInt256().toInt96();

            for (uint256 i; i < members.length; ++i) {
                int96 memberFlowRate = pool_.getMemberFlowRate(members[i]);
                uint128 memberUnits = pool_.getUnits(members[i]);
                int96 expectedMemberFlowRate = flowRatePerUnit * uint256(memberUnits).toInt256().toInt96();
                assertEq(
                    expectedMemberFlowRate,
                    memberFlowRate,
                    "_helperDistributeFlow: member flow rate != expected member flow rate"
                );
            }
        }
        // Assert RTB for all users
        // _assertRealTimeBalances(superToken_);
        _assertGlobalInvariants();
    }

    function _helperDistributeFlow(
        ISuperToken superToken_,
        address caller,
        address from,
        ISuperfluidPool pool_,
        int96 requestedFlowRate
    ) internal {
        _helperDistributeFlow(superToken_, caller, from, pool_, requestedFlowRate, false);
    }

    // Write Helpers - SuperfluidPool ERC20 Functionality

    function _helperSuperfluidPoolApprove(ISuperfluidPool _pool, address owner, address spender, uint256 amount)
        internal
    {
        vm.startPrank(owner);
        _pool.approve(spender, amount);
        vm.stopPrank();

        _assertPoolAllowance(_pool, owner, spender, amount);
    }

    function _helperSuperfluidPoolIncreaseAllowance(
        ISuperfluidPool _pool,
        address owner,
        address spender,
        uint256 addedValue
    ) internal {
        uint256 allowanceBefore = _pool.allowance(owner, spender);

        vm.startPrank(owner);
        _pool.increaseAllowance(spender, addedValue);
        vm.stopPrank();

        _assertPoolAllowance(_pool, owner, spender, allowanceBefore + addedValue);
    }

    function _helperSuperfluidPoolDecreaseAllowance(
        ISuperfluidPool _pool,
        address owner,
        address spender,
        uint256 subtractedValue
    ) internal {
        uint256 allowanceBefore = _pool.allowance(owner, spender);

        vm.startPrank(owner);
        _pool.decreaseAllowance(spender, subtractedValue);
        vm.stopPrank();

        _assertPoolAllowance(_pool, owner, spender, allowanceBefore - subtractedValue);
    }

    function _helperSuperfluidPoolUnitsTransfer(ISuperfluidPool _pool, address from, address to, uint256 amount)
        internal
    {
        uint256 fromBalanceOfBefore = _pool.balanceOf(from);
        uint256 toBalanceOfBefore = _pool.balanceOf(to);

        vm.startPrank(from);
        _pool.transfer(to, amount);
        vm.stopPrank();

        uint256 fromBalanceOfAfter = _pool.balanceOf(from);
        uint256 toBalanceOfAfter = _pool.balanceOf(to);
        assertEq(
            fromBalanceOfBefore - amount,
            fromBalanceOfAfter,
            "_helperSuperfluidPoolUnitsTransfer: from balance mismatch"
        );
        assertEq(
            toBalanceOfBefore + amount, toBalanceOfAfter, "_helperSuperfluidPoolUnitsTransfer: to balance mismatch"
        );
    }

    function _helperSuperfluidPoolUnitsTransferFrom(
        ISuperfluidPool _pool,
        address caller,
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 fromBalanceOfBefore = _pool.balanceOf(from);
        uint256 toBalanceOfBefore = _pool.balanceOf(to);
        uint256 allowanceBefore = _pool.allowance(from, caller);

        vm.startPrank(caller);
        _pool.transferFrom(from, to, amount);
        vm.stopPrank();

        uint256 fromBalanceOfAfter = _pool.balanceOf(from);
        uint256 toBalanceOfAfter = _pool.balanceOf(to);
        uint256 allowanceAfter = _pool.allowance(from, caller);
        assertEq(
            fromBalanceOfBefore - amount,
            fromBalanceOfAfter,
            "_helperSuperfluidPoolUnitsTransferFrom: from balance mismatch"
        );
        assertEq(
            toBalanceOfBefore + amount, toBalanceOfAfter, "_helperSuperfluidPoolUnitsTransferFrom: to balance mismatch"
        );
        assertEq(allowanceBefore - amount, allowanceAfter, "_helperSuperfluidPoolUnitsTransferFrom: allowance mismatch");
    }

    function _helperGetMemberPoolState(ISuperfluidPool pool_, address member_)
        internal
        view
        returns (bool isConnected, int256 units, int96 flowRate)
    {
        units = uint256(pool_.getUnits(member_)).toInt256();
        isConnected = sf.gda.isMemberConnected(pool_, member_);
        flowRate = pool_.getMemberFlowRate(member_);
    }

    function _helperGetPoolUnitsData(ISuperfluidPool pool_) internal view returns (PoolUnitData memory poolUnitData) {
        poolUnitData = PoolUnitData({
            totalUnits: pool_.getTotalUnits(),
            connectedUnits: pool_.getTotalConnectedUnits(),
            disconnectedUnits: pool_.getTotalDisconnectedUnits()
        });
    }

    function _helperGetPoolFlowRatesData(ISuperfluidPool pool_)
        internal
        view
        returns (PoolFlowRateData memory poolFlowRateData)
    {
        poolFlowRateData = PoolFlowRateData({
            totalFlowRate: pool_.getTotalFlowRate(),
            totalConnectedFlowRate: pool_.getTotalConnectedFlowRate(),
            totalDisconnectedFlowRate: pool_.getTotalDisconnectedFlowRate()
        });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Assertion Helpers
    //////////////////////////////////////////////////////////////////////////*/

    // ConstantFlowAgreement Assertions

    /// @dev Asserts that a single flow has been updated as expected
    function _assertFlowData(
        ISuperToken superToken_,
        address sender,
        address receiver,
        int96 expectedFlowRate,
        uint256 expectedLastUpdated,
        uint256 expectedOwedDeposit
    ) internal view {
        (uint256 lastUpdated, int96 flowRate, uint256 deposit, uint256 owedDeposit) =
            superToken_.getFlowInfo(sender, receiver);

        uint256 expectedDeposit = superToken_.getBufferAmountByFlowRate(expectedFlowRate);

        assertEq(flowRate, expectedFlowRate, "FlowData: flow rate");
        assertEq(lastUpdated, expectedLastUpdated, "FlowData: last updated");
        assertEq(deposit, expectedDeposit, "FlowData: deposit");
        assertEq(owedDeposit, expectedOwedDeposit, "FlowData: owed deposit");
    }

    /// @dev Asserts that a single flow has been removed on deletion
    function _assertFlowDataIsEmpty(ISuperToken superToken_, address sender, address receiver) internal view {
        _assertFlowData(superToken_, sender, receiver, 0, 0, 0);
    }

    function _assertFlowOperatorData(
        ISuperToken superToken_,
        address sender,
        address flowOperator,
        int96 expectedFlowRateAllowance,
        uint8 expectedPermissionsBitmask
    ) internal view {
        (bool canCreate, bool canUpdate, bool canDelete, int96 allowance) =
            superToken_.getFlowPermissions(sender, flowOperator);

        bool expectedAllowCreate = expectedPermissionsBitmask & 1 == 1;
        bool expectedAllowUpdate = expectedPermissionsBitmask >> 1 & 1 == 1;
        bool expectedAllowDelete = expectedPermissionsBitmask >> 2 & 1 == 1;

        assertEq(canCreate, expectedAllowCreate, "FlowOperatorData: create permissions");
        assertEq(canUpdate, expectedAllowUpdate, "FlowOperatorData: update permissions");
        assertEq(canDelete, expectedAllowDelete, "FlowOperatorData: delete permissions");
        assertEq(allowance, expectedFlowRateAllowance, "FlowOperatorData: flow rate allowance");
    }

    function _assertFlowOperatorDataIsEmpty(ISuperToken superToken_, address sender, address flowOperator)
        internal view
    {
        _assertFlowOperatorData(superToken_, sender, flowOperator, 0, 0);
    }

    /// @dev Asserts that account flow info has been updated as expected
    /// @param account The account to check
    /// @param flowRateDelta The delta of the flow rate
    /// @param flowInfoBefore The flow info before the update
    /// @param isSender Whether the account is the sender
    function _assertAccountFlowInfo(
        address account,
        int96 flowRateDelta,
        ConstantFlowAgreementV1.FlowData memory flowInfoBefore,
        bool isSender
    ) internal view {
        (uint256 lastUpdated, int96 netFlowRate, uint256 deposit, uint256 owedDeposit) =
            sf.cfa.getAccountFlowInfo(superToken, account);
        int96 expectedNetFlowRate = flowInfoBefore.flowRate + (isSender ? -flowRateDelta : flowRateDelta);
        int256 depositDelta =
            superToken.getBufferAmountByFlowRate(flowRateDelta < 0 ? -flowRateDelta : flowRateDelta).toInt256();
        depositDelta = flowRateDelta < 0 ? -depositDelta : depositDelta;
        uint256 expectedDeposit =
            (flowInfoBefore.deposit.toInt256() + (isSender ? depositDelta : int256(0))).toUint256();
        // TODO: we may need to pass expectedTimestamp at some point
        assertEq(lastUpdated, block.timestamp, "AccountFlowInfo: lastUpdated");
        assertEq(netFlowRate, expectedNetFlowRate, "AccountFlowInfo: net flow rate");
        assertEq(deposit, expectedDeposit, "AccountFlowInfo: deposit");
        // TODO: we may need to pass expectedOwedDeposit at some point
        assertEq(owedDeposit, 0, "AccountFlowInfo: owed deposit");
    }

    // GeneralDistributionAgreement Assertions

    function _assertPoolAllowance(ISuperfluidPool _pool, address owner, address spender, uint256 expectedAllowance)
        internal view
    {
        assertEq(_pool.allowance(owner, spender), expectedAllowance, "_assertPoolAllowance: allowance mismatch");
    }

    function _assertPoolMemberNFT(
        ISuperfluidToken _superToken,
        ISuperfluidPool _pool,
        address _member,
        uint128 _newUnits
    ) internal {
        IPoolMemberNFT poolMemberNFT = SuperToken(address(_superToken)).POOL_MEMBER_NFT();
        uint256 tokenId = poolMemberNFT.getTokenId(address(_pool), address(_member));
        if (_newUnits > 0) {
            // Assert Pool Member NFT owner
            assertEq(poolMemberNFT.ownerOf(tokenId), _member, "_assertPoolMemberNFT: member doesn't own NFT");

            // Assert Pool Member NFT data
            IPoolMemberNFT.PoolMemberNFTData memory poolMemberData = poolMemberNFT.poolMemberDataByTokenId(tokenId);
            assertEq(poolMemberData.pool, address(_pool), "_assertPoolMemberNFT: Pool Member NFT pool mismatch");
            assertEq(poolMemberData.member, _member, "_assertPoolMemberNFT: Pool Member NFT member mismatch");
            assertEq(poolMemberData.units, _newUnits, "_assertPoolMemberNFT: Pool Member NFT units mismatch");
        } else {
            vm.expectRevert(IPoolNFTBase.POOL_NFT_INVALID_TOKEN_ID.selector);
            poolMemberNFT.ownerOf(tokenId);
        }
    }
}
