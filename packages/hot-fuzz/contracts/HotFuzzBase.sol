// SPDX-License-Identifier: AGPLv3
// solhint-disable reason-string
// solhint-disable func-name-mixedcase
pragma solidity >= 0.8.0;

import { Vm } from "forge-std/Vm.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { ISuperfluid, Superfluid } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/Superfluid.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import {
    ConstantFlowAgreementV1
} from "@superfluid-finance/ethereum-contracts/contracts/agreements/ConstantFlowAgreementV1.sol";
import {
    SuperfluidFrameworkDeployer
} from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import {
    SuperTokenV1Library
} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import {
    IERC20,
    ISuperToken,
    IConstantFlowAgreementV1,
    SuperfluidTester
} from "./SuperfluidTester.sol";

contract HotFuzzBase {
    using SuperTokenV1Library for SuperToken;

    // Minimal hevm cheatcode access (avoid inheriting forge-std Test under Echidna).
    // solhint-disable-next-line const-name-snakecase
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // constants
    uint private constant INIT_TOKEN_BALANCE = type(uint160).max;
    uint private constant INIT_SUPER_TOKEN_BALANCE = type(uint128).max;

    // immutables
    SuperfluidFrameworkDeployer internal immutable _sfDeployer;
    TestToken  internal immutable token;
    SuperToken internal immutable superToken;
    uint internal immutable nTesters;

    SuperfluidFrameworkDeployer.Framework internal sf;

    // test states
    SuperfluidTester[] internal testers;
    address[] internal otherAccounts;
    uint256 internal expectedTotalSupply = 0;
    bool internal liquidationFails;
    // Set by CFA/GDA liquidation actions when post-conditions fail. Property-mode Echidna
    // only observes echidna_* flags — inline asserts would be discarded.
    bool internal liquidationPostconditionViolated;

    struct LiquidationExpectations {
        bool isCritical;
        address rewardAccount;
        int256 rewardAccountAfter;
        int256 liquidatorAfter;
    }

    constructor(uint nTesters_) {
        _sfDeployer = new SuperfluidFrameworkDeployer();
        _sfDeployer.deployTestFramework();
        sf = _sfDeployer.getFramework();

        (token, superToken) =
            _sfDeployer.deployWrapperSuperToken("HOTFuzz Token", "HOTT", 18, type(uint256).max, address(0));
        nTesters = nTesters_;
        otherAccounts = new address[](0);

        _addAccount(address(sf.gda));
        _addAccount(address(sf.toga));
    }

    function _initTesters() virtual internal {
        testers = new SuperfluidTester[](nTesters);
        for (uint i = 0; i < nTesters; ++i) {
            testers[i] = _createTester();
            token.mint(address(testers[i]), INIT_TOKEN_BALANCE);
            testers[i].upgradeSuperToken(INIT_SUPER_TOKEN_BALANCE);
            expectedTotalSupply += INIT_SUPER_TOKEN_BALANCE;
        }
    }

    /**************************************************************************
     * IHotFuzz implementation
     **************************************************************************/

    function _createTester()
        virtual internal
        returns (SuperfluidTester)
    {
        return new SuperfluidTester(sf, token, superToken);
    }

    function _addAccount(address a)
        internal
    {
        otherAccounts.push(a);
    }

    function _listAccounts()
        internal view
        returns (address[] memory accounts)
    {
        accounts = new address[](_numAccounts());
        for (uint i = 0; i < nTesters; ++i) accounts[i] = address(testers[i]);
        for (uint i = 0; i < otherAccounts.length; ++i) accounts[i + nTesters] = otherAccounts[i];
    }

    function _numAccounts() internal view returns (uint256) {
        return nTesters + otherAccounts.length;
    }

    function _getOneTester(uint8 a)
        internal view
        returns (SuperfluidTester tester)
    {
        tester = testers[a % nTesters];
    }

    /// @dev The testers returned may be the same
    function _getTwoTesters(uint8 a, uint8 b)
        internal view
        returns (SuperfluidTester testerA, SuperfluidTester testerB)
    {
        testerA = _getOneTester(a);
        testerB = _getOneTester(b);
    }

    /// @dev The testers returned may be the same
    function _getThreeTesters(uint8 a, uint8 b, uint8 c)
        internal view
        returns (SuperfluidTester testerA, SuperfluidTester testerB, SuperfluidTester testerC)
    {
        testerA = _getOneTester(a);
        testerB = _getOneTester(b);
        testerC = _getOneTester(c);
    }

    function _superTokenBalanceOfNow(address a) internal view returns (int256 avb) {
        (avb,,,) = superToken.realtimeBalanceOfNow(a);
    }

    function _getLiquidationExpectations(
        address account,
        address liquidator,
        uint256 singleDeposit,
        bool isPatricianPeriod
    ) internal view returns (LiquidationExpectations memory expectations) {
        (int256 availableBalance, uint256 totalDeposit,,) = superToken.realtimeBalanceOfNow(account);
        expectations.isCritical = availableBalance < 0;
        expectations.rewardAccount = sf.governance.getRewardAddress(sf.host, superToken);
        (expectations.rewardAccountAfter,,,) =
            superToken.realtimeBalanceOfNow(expectations.rewardAccount);
        (expectations.liquidatorAfter,,,) = superToken.realtimeBalanceOfNow(liquidator);
        if (!expectations.isCritical) return expectations;

        // Account-level totalDeposit from realtimeBalanceOf (across agreements).
        int256 signedTotalDeposit = int256(totalDeposit);
        int256 totalRewardLeft = availableBalance + signedTotalDeposit;
        if (totalRewardLeft >= 0) {
            int256 reward = int256(singleDeposit) * totalRewardLeft / signedTotalDeposit;
            if (isPatricianPeriod) {
                expectations.rewardAccountAfter += reward;
            } else {
                expectations.liquidatorAfter += reward;
            }
        } else {
            expectations.rewardAccountAfter += totalRewardLeft - int256(singleDeposit);
            expectations.liquidatorAfter += int256(singleDeposit);
        }
    }

    /// @dev CFA/GDA pack timestamps as uint32; never leave that domain.
    function _warpBy(uint256 dt) private {
        if (dt == 0) return;
        uint256 maxTs = type(uint32).max;
        if (block.timestamp >= maxTs) return;
        uint256 room = maxTs - block.timestamp;
        if (dt > room) dt = room;
        vm.warp(block.timestamp + dt);
    }

    function warpTime(uint32 seconds_) public {
        if (seconds_ == 0) return;
        uint256 dt = uint256(seconds_) % 7 days;
        if (dt == 0) dt = 1;
        _warpBy(dt);
    }

    /// @notice Bring tester `a` to a critical available balance if it has net outflow.
    /// @dev Testers start with ~2^128 tokens. Waiting for flow alone to drain that can
    ///      exceed the uint32 timestamp domain and break dynamic balances / liquidity-sum.
    ///      Drain spendable balance to another tester first (preserves total liquidity),
    ///      then warp a short bounded time — same setup pattern as the Foundry solvency tests.
    function warpToCritical(uint8 a, uint32 secondsAfterCritical) public {
        SuperfluidTester tester = _getOneTester(a);
        if (superToken.getNetFlowRate(address(tester)) >= 0) return;

        SuperfluidTester sink = _getOneTester(a + 1);
        if (address(sink) != address(tester)) {
            tester.transferAll(address(sink));
        }

        uint256 dt = uint256(secondsAfterCritical) % 1 days;
        if (dt == 0) dt = 1;
        _warpBy(dt);
    }

    function _checkLiquidationBalances(LiquidationExpectations memory expectations, address liquidator)
        internal
        view
        returns (bool ok)
    {
        (int256 rewardAccountAfter,,,) = superToken.realtimeBalanceOfNow(expectations.rewardAccount);
        (int256 liquidatorAfter,,,) = superToken.realtimeBalanceOfNow(liquidator);
        return rewardAccountAfter == expectations.rewardAccountAfter
            && liquidatorAfter == expectations.liquidatorAfter;
    }

    /**************************************************************************
     * Invariances
     **************************************************************************/

    function echidna_check_total_supply() public view returns (bool) {
        assert(superToken.totalSupply() == expectedTotalSupply);
        return superToken.totalSupply() == expectedTotalSupply;
    }

    function echidna_check_liquiditySumInvariance() public view returns (bool) {
        int256 liquiditySum = 0;
        address[] memory accounts = _listAccounts();
        for (uint i = 0; i < accounts.length; ++i) {
            (int256 avb, uint256 d, uint256 od, ) = superToken.realtimeBalanceOfNow(accounts[i]);
            // FIXME: correct formula
            // liquiditySum += avb + int256(d) - int256(od);
            // current faulty one
            liquiditySum += avb + (d > od ? int256(d) - int256(od) : int256(0));
        }
        assert(int256(expectedTotalSupply) == liquiditySum);
        return int256(expectedTotalSupply) == liquiditySum;
    }

    function echidna_check_netFlowRateSumInvariant() public view returns (bool) {
        int96 netFlowRateSum = 0;
        address[] memory accounts = _listAccounts();
        for (uint i = 0; i < accounts.length; ++i) {
            netFlowRateSum += superToken.getNetFlowRate(accounts[i]);
        }
        assert(netFlowRateSum == 0);
        return netFlowRateSum == 0;
    }

    function echidna_check_validLiquidationNeverRevertsInvariant() public view returns (bool) {
        bool liquidationNeverFails = !liquidationFails;
        assert(liquidationNeverFails);
        return liquidationNeverFails;
    }

    function echidna_check_liquidationPostconditions() public view returns (bool) {
        bool ok = !liquidationPostconditionViolated;
        assert(ok);
        return ok;
    }
}
