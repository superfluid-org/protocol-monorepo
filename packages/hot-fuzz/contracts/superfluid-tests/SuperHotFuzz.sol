// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.8.0;

import "./ConstantFlowAgreementV1.hott.sol";
import "./GeneralDistributionAgreementV1.hott.sol";
import "./SuperToken.hott.sol";

// Combine all the hot fuzzes
contract SuperHotFuzz is HotFuzzBase(10), CFAHotFuzzMixin, GDAHotFuzzMixin, SuperTokenHotFuzzMixin {
    constructor() {
        _initTesters();
    }
}
