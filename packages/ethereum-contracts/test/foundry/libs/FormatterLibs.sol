// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Strings } from "@openzeppelin-v5/contracts/utils/Strings.sol";

function _formatUnits(uint256 amount, uint8 exponent, uint8 maxDecimals) pure returns (string memory) {
    if (exponent > maxDecimals) {
        uint256 factor = 10 ** (exponent - maxDecimals);
        amount = (amount + (factor / 2)) / factor;
    }
    uint256 intPart = amount / 10 ** maxDecimals;
    uint256 fracPart = amount % 10 ** maxDecimals;
    string memory intString = Strings.toString(intPart);
    if (fracPart == 0) {
        return intString;
    }
    string memory fracString = Strings.toString(fracPart);
    while (bytes(fracString).length < maxDecimals) {
        fracString = string.concat("0", fracString);
    }
    return string.concat(intString, ".", fracString);
}

library FlowRateFormatter {
    enum Period {
        SECOND,
        MINUTE,
        HOUR,
        DAY,
        WEEK,
        MONTH,
        YEAR
    }

    error InvalidPeriod();

    function toFlowRatePerDay(int96 flowRate) internal pure returns (string memory) {
        return toFlowRateX(flowRate, Period.DAY, 5);
    }

    function toFlowRateX(int96 flowRate, Period period, uint8 maxDecimals)
        internal
        pure
        returns (string memory)
    {
        int256 absFlowRate = (flowRate < 0) ? -flowRate : flowRate;
        uint256 tokensPerPeriod = uint256(absFlowRate) * _getSecondsInPeriod(period);
        string memory frAbs = _formatUnits(tokensPerPeriod, 18, maxDecimals);
        return (flowRate < 0) ? string.concat("-", frAbs) : frAbs;
    }

    function _getSecondsInPeriod(Period period) private pure returns (uint256) {
        if (period == Period.SECOND) return 1;
        if (period == Period.MINUTE) return 60;
        if (period == Period.HOUR) return 3600;
        if (period == Period.DAY) return 86400;
        if (period == Period.WEEK) return 604800;
        if (period == Period.MONTH) return 2628000;
        if (period == Period.YEAR) return 31536000;
        revert InvalidPeriod();
    }
}

library AmountFormatter {
    function toHumanReadable(uint256 amount) internal pure returns (string memory) {
        return _formatUnits(amount, 18, 5);
    }
}
