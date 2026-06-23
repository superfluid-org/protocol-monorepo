// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IERC4626 } from "@openzeppelin-v5/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin-v5/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPermit2 } from "../../../contracts/interfaces/external/IPermit2.sol";
import { BatchOperation, ISuperfluid, IERC20 } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IClearMacro } from "../../../contracts/interfaces/utils/IClearMacro.sol";

address constant PERMIT2_CANONICAL = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

/**
 * @title Permit2VaultDepositMacro
 * @dev Test macro: pull underlying via Permit2 and deposit into an ERC-4626 vault for the user.
 *
 * ## Why Permit2 runs inside the macro batch
 *
 * `runPermit2AndMacro` validates the Permit2 witness, then calls `buildBatchOperations`, which only
 * receives `action.params`. It does not receive `permit2Context` calldata. Yet the actual
 * `permitWitnessTransferFrom` must be called with `msg.sender == spender`, and in witness-only mode
 * the spender is this macro (not the forwarder). So the batch emits a `SIMPLE_FORWARD_CALL` into
 * `depositViaPermit2`, where the macro pulls tokens and deposits them.
 *
 * ## Why Permit2 data lives in `actionParams`
 *
 * `Payload.action.params` is the only byte blob the forwarder hands to the macro at execution time.
 * Fields the forwarder already checked in `permit2Context` — witness, witness type string, permit
 * details, signature — are copied into `ExecutionParams` so the macro can call Permit2 from inside
 * the batch. The forwarder validates the witness against `encodedPayload` before the batch runs;
 * the macro forwards the same witness to Permit2 without recomputing it.
 *
 * ## Why those fields are not in `Action(...)`
 *
 * Wallets show intent (`description`, `vault`). Token, amount, owner, Permit2 nonce/deadline, and
 * the Permit2 signature are already bound by the user's Permit2 signature over
 * `PermitWitnessTransferFrom(TokenPermissions, …, witness)`. The witness itself is bound the same
 * way. Re-listing them in the ClearMacro `Action` type would duplicate what Permit2 already
 * commits. `getActionStructHash` hashes only `description` and `vault`.
 *
 * ## `actionParams` layout
 *
 * `abi.encode(string description, address vault, ExecutionParams execution)`
 */
contract Permit2VaultDepositMacro is IClearMacro {
    using SafeERC20 for IERC20;

    string public constant PRIMARY_TYPE_NAME = "Permit2VaultDeposit";
    string public constant ACTION_TYPE_DEFINITION = "Action(string description,address vault)";

    /// @dev Permit2 pull + vault deposit inputs. Not part of the EIP-712 `Action` type; see contract natspec.
    struct ExecutionParams {
        address owner;
        address token;
        uint256 amount;
        uint256 permitNonce;
        uint256 permitDeadline;
        bytes32 witness;
        string witnessTypeString;
        bytes permit2Signature;
    }

    error VaultAssetMismatch(address vault, address expected, address actual);

    function encodeActionParams(string memory description, address vault, ExecutionParams memory execution)
        public
        pure
        returns (bytes memory actionParams)
    {
        return abi.encode(description, vault, execution);
    }

    /// @dev Permit2 pull + ERC-4626 deposit. Witness is forwarded from `actionParams`; not recomputed here.
    function depositViaPermit2(bytes calldata actionParams) external {
        (, address vault, ExecutionParams memory execution) = _decode(actionParams);

        if (IERC4626(vault).asset() != execution.token) {
            revert VaultAssetMismatch(vault, execution.token, IERC4626(vault).asset());
        }

        IPermit2(PERMIT2_CANONICAL).permitWitnessTransferFrom(
            IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({ token: execution.token, amount: execution.amount }),
                nonce: execution.permitNonce,
                deadline: execution.permitDeadline
            }),
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: execution.amount }),
            execution.owner,
            execution.witness,
            execution.witnessTypeString,
            execution.permit2Signature
        );

        IERC20(execution.token).forceApprove(vault, execution.amount);
        IERC4626(vault).deposit(execution.amount, execution.owner);
    }

    function buildBatchOperations(ISuperfluid, bytes memory actionParams, address)
        external
        view
        override
        returns (ISuperfluid.Operation[] memory operations)
    {
        operations = new ISuperfluid.Operation[](1);
        operations[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(this),
            data: abi.encodeCall(this.depositViaPermit2, (actionParams))
        });
    }

    function postCheck(ISuperfluid, bytes memory actionParams, address account) external view override {
        (, address vault,) = _decode(actionParams);
        if (IERC4626(vault).balanceOf(account) == 0) {
            revert("no vault shares received");
        }
    }

    function getActionTypeDefinition(bytes memory /*encodedPayload*/) external pure override returns (string memory) {
        return ACTION_TYPE_DEFINITION;
    }

    function getPrimaryTypeName(bytes memory /*encodedPayload*/) external pure override returns (string memory) {
        return PRIMARY_TYPE_NAME;
    }

    /// @dev Hashes only the user-facing `Action` fields (`description`, `vault`).
    function getActionStructHash(bytes memory actionParams) external pure override returns (bytes32) {
        (string memory description, address vault,) = _decode(actionParams);
        bytes32 actionTypeHash = keccak256(abi.encodePacked(ACTION_TYPE_DEFINITION));
        return keccak256(abi.encode(actionTypeHash, keccak256(bytes(description)), vault));
    }

    function _decode(bytes memory actionParams)
        internal
        pure
        returns (string memory description, address vault, ExecutionParams memory execution)
    {
        return abi.decode(actionParams, (string, address, ExecutionParams));
    }
}
