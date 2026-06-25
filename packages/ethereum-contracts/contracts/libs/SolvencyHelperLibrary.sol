// SPDX-License-Identifier: AGPLv3

import {
    ISuperfluid,
    ISuperfluidToken,
    ISuperfluidGovernance,
    SuperfluidGovernanceConfigs
} from "../interfaces/superfluid/ISuperfluid.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";

pragma solidity ^0.8.23;

library SolvencyHelperLibrary {
    using SafeCast for uint256;

    function decode3PsData(ISuperfluid host, ISuperfluidToken token)
        internal
        view
        returns (uint256 liquidationPeriod, uint256 patricianPeriod)
    {
        ISuperfluidGovernance gov = ISuperfluidGovernance(host.getGovernance());
        // @note we are explicitly using CFAV1_PPP_CONFIG_KEY for both CFA and GDA
        uint256 pppConfig = gov.getConfigAsUint256(host, token, SuperfluidGovernanceConfigs.CFAV1_PPP_CONFIG_KEY);
        (liquidationPeriod, patricianPeriod) = SuperfluidGovernanceConfigs.decodePPPConfig(pppConfig);
    }

    function isPatricianPeriod(
        int256 availableBalance,
        int256 signedTotalDeposit,
        uint256 liquidationPeriod,
        uint256 patricianPeriod
    ) internal pure returns (bool) {
        if (signedTotalDeposit == 0) {
            return false;
        }

        int256 signedLiquidationPeriod = liquidationPeriod.toInt256();
        int256 signedPatricianPeriodTail = (liquidationPeriod - patricianPeriod).toInt256();
        int256 totalRewardLeft = availableBalance + signedTotalDeposit;
        int256 totalOutflowRate = signedTotalDeposit / signedLiquidationPeriod;

        return totalRewardLeft / totalOutflowRate > signedPatricianPeriodTail;
    }
}
