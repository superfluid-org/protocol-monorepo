// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { UUPSProxy } from "../../../contracts/upgradability/UUPSProxy.sol";
import { UUPSProxiable } from "../../../contracts/upgradability/UUPSProxiable.sol";
import { IERC20, ISuperToken, SuperToken, IConstantOutflowNFT, IConstantInflowNFT }
    from "../../../contracts/superfluid/SuperToken.sol";
import { PoolAdminNFT, IPoolAdminNFT } from "../../../contracts/agreements/gdav1/PoolAdminNFT.sol";
import { PoolMemberNFT, IPoolMemberNFT } from "../../../contracts/agreements/gdav1/PoolMemberNFT.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";
import { TestToken } from "../../../contracts/utils/TestToken.sol";
import { TokenDeployerLibrary } from "../../../contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol";

contract SuperTokenIntegrationTest is FoundrySuperfluidTester {
    constructor() FoundrySuperfluidTester(0) { }

    function setUp() public override {
        super.setUp();
    }

    function testUnderlyingTokenDecimals() public view {
        assertEq(token.decimals(), superToken.getUnderlyingDecimals());
    }

    function testToUnderlyingAmountWithUpgrade(uint8 decimals, uint256 amount) public {
        vm.assume(amount < type(uint64).max);
        // We assume that most underlying tokens will not have more than 32 decimals
        vm.assume(decimals <= 32);
        (TestToken localToken, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("FTT", "FTT", decimals, type(uint256).max, address(0));
        (uint256 underlyingAmount, uint256 adjustedAmount) = localSuperToken.toUnderlyingAmount(amount);
        localToken.mint(alice, INIT_TOKEN_BALANCE);
        vm.startPrank(alice);
        localToken.approve(address(localSuperToken), underlyingAmount);
        localSuperToken.upgrade(adjustedAmount);
        vm.stopPrank();
        uint256 upgradedBalance = localSuperToken.balanceOf(alice);
        assertEq(upgradedBalance, adjustedAmount, "testToUnderlyingAmount: upgraded amount wrong");
    }

    function testToUnderlyingAmountWithDowngrade(uint8 decimals, uint256 upgradeAmount, uint256 downgradeAmount)
        public
    {
        vm.assume(upgradeAmount < type(uint64).max);
        // We assume that most underlying tokens will not have more than 32 decimals
        vm.assume(decimals <= 32);
        vm.assume(downgradeAmount < upgradeAmount);
        (TestToken localToken, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("FTT", "FTT", decimals, type(uint256).max, address(0));
        (uint256 underlyingAmount, uint256 adjustedAmount) = localSuperToken.toUnderlyingAmount(upgradeAmount);
        localToken.mint(alice, INIT_TOKEN_BALANCE);

        vm.startPrank(alice);
        localToken.approve(address(localSuperToken), underlyingAmount);
        localSuperToken.upgrade(adjustedAmount);

        uint256 underlyingBalanceBefore = localToken.balanceOf(alice);
        (underlyingAmount, adjustedAmount) = localSuperToken.toUnderlyingAmount(downgradeAmount);
        localSuperToken.downgrade(adjustedAmount);
        uint256 underlyingBalance = localToken.balanceOf(alice);
        vm.stopPrank();

        assertEq(
            underlyingBalance,
            underlyingBalanceBefore + underlyingAmount,
            "testToUnderlyingAmount: underlying amount wrong"
        );
    }

    function testInitializeSuperTokenWithAndWithoutAdmin(address _admin) public {
        (, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("FTT", "FTT", 18, type(uint256).max, _admin);

        assertEq(
            localSuperToken.getAdmin(),
            _admin,
            "testInitializeSuperTokenWithAndWithoutAdmin: _admin address not set correctly"
        );
    }

    function testOnlyHostCanChangeAdminWhenNoAdmin(address _admin) public {
        (, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("FTT", "FTT", 18, type(uint256).max, address(0));

        vm.startPrank(address(sf.host));
        localSuperToken.changeAdmin(_admin);
        vm.stopPrank();

        assertEq(
            localSuperToken.getAdmin(), _admin, "testOnlyHostCanChangeAdminWhenNoAdmin: admin address not set correctly"
        );
    }

    function testOnlyAdminCanChangeAdmin(address _admin, address newAdmin) public {
        if (_admin == address(0)) {
            _admin = address(sf.host);
        }

        (, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("FTT", "FTT", 18, type(uint256).max, _admin);

        vm.startPrank(_admin);
        localSuperToken.changeAdmin(newAdmin);
        vm.stopPrank();

        assertEq(localSuperToken.getAdmin(), newAdmin, "testOnlyAdminCanChangeAdmin: admin address not set correctly");
    }

    function testRevertWhenNonAdminTriesToChangeAdmin(address _admin, address nonAdmin) public {
        vm.assume(_admin != nonAdmin);
        vm.assume(nonAdmin != address(0));
        if (_admin == address(0)) {
            _admin = address(sf.host);
        }

        (, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("FTT", "FTT", 18, type(uint256).max, _admin);

        vm.startPrank(nonAdmin);
        vm.expectRevert(ISuperToken.SUPER_TOKEN_ONLY_ADMIN.selector);
        localSuperToken.changeAdmin(nonAdmin);
        vm.stopPrank();
    }

    function testRevertWhenNonAdminTriesToUpdateCode(address _admin, address nonAdmin) public {
        vm.assume(_admin != address(sf.host));
        vm.assume(nonAdmin != address(sf.host));

        (TestToken localTestToken, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("FTT", "FTT", 18, type(uint256).max, address(0));

        SuperToken newSuperTokenLogic =
            _helperDeploySuperTokenAndInitialize(localSuperToken, localTestToken, 18, "FTT", "FTT", _admin);

        vm.startPrank(nonAdmin);
        vm.expectRevert(ISuperToken.SUPER_TOKEN_ONLY_ADMIN.selector);
        UUPSProxiable(address(localSuperToken)).updateCode(address(newSuperTokenLogic));
        vm.stopPrank();
    }

    function testOnlyHostCanUpdateCodeWhenNoAdmin() public {
        (TestToken localTestToken, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("FTT", "FTT", 18, type(uint256).max, address(0));

        SuperToken newSuperTokenLogic =
            _helperDeploySuperTokenAndInitialize(localSuperToken, localTestToken, 18, "FTT", "FTT", address(0));

        vm.startPrank(address(sf.host));
        UUPSProxiable(address(localSuperToken)).updateCode(address(newSuperTokenLogic));
        vm.stopPrank();

        assertEq(
            UUPSProxiable(address(localSuperToken)).getCodeAddress(),
            address(newSuperTokenLogic),
            "testOnlyHostCanUpdateCodeWhenNoAdmin: super token logic not updated correctly"
        );
    }

    function testOnlyAdminCanUpdateCode(address _admin) public {
        if (_admin == address(0)) {
            _admin = address(sf.host);
        }

        (TestToken localTestToken, ISuperToken localSuperToken) =
            sfDeployer.deployWrapperSuperToken("FTT", "FTT", 18, type(uint256).max, _admin);

        SuperToken newSuperTokenLogic =
            _helperDeploySuperTokenAndInitialize(localSuperToken, localTestToken, 18, "FTT", "FTT", _admin);

        vm.startPrank(_admin);
        UUPSProxiable(address(localSuperToken)).updateCode(address(newSuperTokenLogic));
        vm.stopPrank();

        assertEq(
            UUPSProxiable(address(localSuperToken)).getCodeAddress(),
            address(newSuperTokenLogic),
            "testOnlyHostCanUpdateCodeWhenNoAdmin: super token logic not updated correctly"
        );
    }
}
