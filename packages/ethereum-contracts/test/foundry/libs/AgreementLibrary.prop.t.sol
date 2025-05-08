// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { AgreementLibrary } from "../../../contracts/agreements/AgreementLibrary.sol";

import "forge-std/Test.sol";

contract AgreementLibraryPropertyTest is Test {
    function testAdjustNewAppCreditUsed(uint256 appCreditGranted, int256 appCreditUsed) public pure {
        vm.assume(appCreditGranted <= uint256(type(int256).max));
        vm.assume(appCreditUsed <= type(int256).max);
        int256 adjustedAppCreditUsed = AgreementLibrary._adjustNewAppCreditUsed(appCreditGranted, appCreditUsed);

        assertFalse(adjustedAppCreditUsed < 0);
        assertFalse(uint256(adjustedAppCreditUsed) > appCreditGranted);
    }
}
