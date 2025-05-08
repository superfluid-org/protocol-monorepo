// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { CallUtils } from "../libs/CallUtils.sol";

contract FakeSuperfluidMock {

    function callAgreement(
        address agreement,
        bytes calldata callData
    )
        external
    {
        bool success;
        bytes memory returnedData;
        // solhint-disable-next-line avoid-low-level-calls
        (success, returnedData) = agreement.call(callData);
        assert(!success);
        CallUtils.revertFromReturnedData(returnedData);
    }
}
