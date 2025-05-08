// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import {
    ISuperfluid, ISuperAgreement, ISuperToken, ISuperfluidPool,
    IConstantFlowAgreementV1, IGeneralDistributionAgreementV1
} from "../interfaces/superfluid/ISuperfluid.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Batch liquidator contract
 * @author Superfluid
 * @dev This contract allows to delete multiple flows in a single transaction.
 * @notice Reduces calldata by having host and cfa hardcoded, this can make a significant difference in tx fees on L2s
 */

contract BatchLiquidator {
    enum FlowType {
        ConstantFlowAgreement,
        GeneralDistributionAgreement
    }

    struct FlowLiquidationData {
        FlowType agreementOperation;
        address sender;
        address receiver;
    }

    address public immutable host;
    address public immutable cfa;
    address public immutable gda;

    constructor(address host_) {
        host = host_;
        cfa = address(
            ISuperfluid(host).getAgreementClass(keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1"))
        );
        gda = address(
            ISuperfluid(host).getAgreementClass(
                keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1")
            )
        );
    }

    /**
     * @dev Delete flows in batch
     * @param superToken - The super token the flows belong to.
     * @param data - The array of flow data to be deleted.
     */
    function deleteFlows(address superToken, FlowLiquidationData[] memory data) external {
        for (uint256 i; i < data.length;) {
            // We tolerate any errors occured during liquidations.
            // It could be due to flow had been liquidated by others.
            _deleteFlow(superToken, data[i]);

            unchecked {
                i++;
            }
        }

        // If the liquidation(s) resulted in any super token
        // rewards, send them all to the sender instead of having them
        // locked in the contract
        {
            uint256 balance = ERC20(superToken).balanceOf(address(this));
            if (balance > 0) {
                // don't fail for non-transferrable tokens
                try ERC20(superToken).transferFrom(address(this), msg.sender, balance)
                // solhint-disable-next-line no-empty-blocks
                {} catch {}
            }
        }
    }

    /**
     * @dev Delete a single flow
     * @param superToken - The super token the flow belongs to.
     * @param data - The flow data to be deleted.
     */
    function deleteFlow(address superToken, FlowLiquidationData memory data) external {
        /* solhint-disable */
        (bool success, bytes memory returndata) = _deleteFlow(superToken, data);
        if (!success) {
            if (returndata.length == 0) revert();
            // solhint-disable
            assembly {
                revert(add(32, returndata), mload(returndata))
            }
        }
        /* solhint-enable */
        // If the liquidation(s) resulted in any super token
        // rewards, send them all to the sender instead of having them
        // locked in the contract
        {
            uint256 balance = ERC20(superToken).balanceOf(address(this));
            if (balance > 0) {
                try ERC20(superToken).transferFrom(address(this), msg.sender, balance)
                // solhint-disable-next-line no-empty-blocks
                {} catch {}
            }
        }
    }

    function _deleteFlow(address superToken, FlowLiquidationData memory data)
        internal
        returns (bool success, bytes memory returndata)
    {
        if (data.agreementOperation == FlowType.ConstantFlowAgreement) {
            // solhint-disable-next-line avoid-low-level-calls
            (success, returndata) = address(host).call(
                abi.encodeCall(
                    ISuperfluid(host).callAgreement,
                    (
                        ISuperAgreement(cfa),
                        abi.encodeCall(
                            IConstantFlowAgreementV1(cfa).deleteFlow,
                            (ISuperToken(superToken), data.sender, data.receiver, new bytes(0))
                            ),
                        new bytes(0)
                    )
                )
            );
        } else {
            // solhint-disable-next-line avoid-low-level-calls
            (success, returndata) = address(host).call(
                abi.encodeCall(
                    ISuperfluid(host).callAgreement,
                    (
                        ISuperAgreement(gda),
                        abi.encodeCall(
                            IGeneralDistributionAgreementV1(gda).distributeFlow,
                            (ISuperToken(superToken), data.sender, ISuperfluidPool(data.receiver), 0, new bytes(0))
                            ),
                        new bytes(0)
                    )
                )
            );
        }
    }
}
