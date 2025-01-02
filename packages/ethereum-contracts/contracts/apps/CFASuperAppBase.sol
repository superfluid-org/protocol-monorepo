// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.11;

import { ISuperfluid, ISuperToken, ISuperApp, SuperAppDefinitions } from "../interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "./SuperTokenV1Library.sol";

/**
 * @title abstract base contract for SuperApps using CFA callbacks
 * @author Superfluid
 * @dev This contract provides a more convenient API for implementing CFA callbacks.
 * It allows to write more concise and readable SuperApps.
 * The API is tailored for common use cases, with the "beforeX" and "afterX" callbacks being
 * abstrated into a single "onX" callback for create|update|delete flows.
 * If the previous state provided by this API (`previousFlowRate` and `lastUpdated`) is not sufficient for you use case,
 * you should implement the more generic low-level API of `ISuperApp` instead of using this base contract.
 */
abstract contract CFASuperAppBase is ISuperApp {
    using SuperTokenV1Library for ISuperToken;

    /// =================================================================================
    /// CONSTANTS & IMMUTABLES
    /// =================================================================================

    bytes32 public constant CFAV1_TYPE = keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");

    ISuperfluid public immutable HOST;

    /// =================================================================================
    /// ERRORS
    /// =================================================================================

    /// @dev Thrown when the callback caller is not the host.
    error UnauthorizedHost();

    /// @dev Thrown if a required callback wasn't implemented (overridden by the SuperApp)
    error NotImplemented();

    /// @dev Thrown when SuperTokens not accepted by the SuperApp are streamed to it
    error NotAcceptedSuperToken();

    // =================================================================================
    // SETUP
    // =================================================================================

    /**
     * @dev Creates the contract tied to the provided Superfluid host
     * @param host_ the Superfluid host the SuperApp belongs to
     * @notice You also need to register the app with the host in order to enable callbacks.
     * This can be done either by calling `selfRegister()` or by calling `host.registerApp()`.
     */
    constructor(ISuperfluid host_) {
        HOST = host_;
    }

    /**
     * @dev Registers the SuperApp with its Superfluid host contract (self-registration)
     * @param activateOnCreated if true, callbacks for `createFlow` will be activated
     * @param activateOnUpdated if true, callbacks for `updateFlow` will be activated
     * @param activateOnDeleted if true, callbacks for `deleteFlow` will be activated
     *
     * Note: if the App self-registers on a network with permissioned SuperApp registration,
     * self-registration can be used only if the tx.origin (EOA) is whitelisted as deployer.
     * If instead a whitelisted factory is used, the factory needs to call `host.registerApp(address app)`.
     * For more details, see https://github.com/superfluid-finance/protocol-monorepo/wiki/Super-App-White-listing-Guide
     */
    function selfRegister(
        bool activateOnCreated,
        bool activateOnUpdated,
        bool activateOnDeleted
    ) public {
        HOST.registerApp(getConfigWord(activateOnCreated, activateOnUpdated, activateOnDeleted));
    }

    /**
     * @dev Convenience function to get the `configWord` for app registration when not using self-registration
     * @param activateOnCreated if true, callbacks for `createFlow` will be activated
     * @param activateOnUpdated if true, callbacks for `updateFlow` will be activated
     * @param activateOnDeleted if true, callbacks for `deleteFlow` will be activated
     * @return configWord the `configWord` encoding the provided settings
     */
    function getConfigWord(
        bool activateOnCreated,
        bool activateOnUpdated,
        bool activateOnDeleted
    ) public pure returns (uint256 configWord) {
        // since only 1 level is allowed by the protocol, we can hardcode APP_LEVEL_FINAL
        configWord = SuperAppDefinitions.APP_LEVEL_FINAL
        // there's no information we want to carry over for create
            | SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;
        if (!activateOnCreated) {
            configWord |= SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP;
        }
        if (!activateOnUpdated) {
            configWord |= SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP;
        }
        if (!activateOnDeleted) {
            configWord |= SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;
        }
    }

    /**
     * @dev Optional (positive) filter for accepting only specific SuperTokens.
     *      The default implementation accepts all SuperTokens.
     *      Can be overridden by the SuperApp in order to apply arbitrary filters.
     */
    function isAcceptedSuperToken(ISuperToken /*superToken*/) public view virtual returns (bool) {
        return true;
    }

    // =================================================================================
    // CFA SPECIFIC CALLBACKS - TO BE OVERRIDDEN BY INHERITING SUPERAPPS
    // =================================================================================

    /// @dev override if the SuperApp shall have custom logic invoked when a new flow
    ///      to it is created.
    function onFlowCreated(
        ISuperToken /*superToken*/,
        address /*sender*/,
        bytes calldata ctx
    ) internal virtual returns (bytes memory /*newCtx*/) {
        return ctx;
    }

    /// @dev override if the SuperApp shall have custom logic invoked when an existing flow
    ///      to it is updated (flowrate change).
    function onFlowUpdated(
        ISuperToken /*superToken*/,
        address /*sender*/,
        int96 /*previousFlowRate*/,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal virtual returns (bytes memory /*newCtx*/) {
        return ctx;
    }

    /// @dev override if the SuperApp shall have custom logic invoked when an existing flow
    ///      to it is deleted (flowrate set to 0).
    ///      Unlike the other callbacks, this method is NOT allowed to revert.
    ///      Failing to satisfy that requirement leads to jailing (defunct SuperApp).
    function onFlowDeleted(
        ISuperToken /*superToken*/,
        address /*sender*/,
        int96 /*previousFlowRate*/,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal virtual returns (bytes memory /*newCtx*/) {
        return ctx;
    }

    /// @dev override if the SuperApp shall have custom logic invoked when an outgoing flow
    ///      is deleted by the receiver (it's not triggered when deleted by the SuperApp itself).
    ///      A possible implementation is to make outflows "sticky" by simply reopening it.
    ///      Like onFlowDeleted, this method is NOT allowed to revert.
    ///      It's safe to not override this method if the SuperApp doesn't have outgoing flows,
    ///      or if it doesn't want/need to know if an outgoing flow is deleted by its receiver.
    /// Note: In theory this hook could also be triggered by a liquidation, but this would imply
    /// that the SuperApp is insolvent, and would thus be jailed already.
    /// Thus in practice this is triggered only when a receiver of an outgoing flow deletes that flow.
    function onOutflowDeleted(
        ISuperToken /*superToken*/,
        address /*receiver*/,
        int96 /*previousFlowRate*/,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal virtual returns (bytes memory /*newCtx*/) {
        return ctx;
    }

    // =================================================================================
    // INTERNAL IMPLEMENTATION
    // =================================================================================

    // The following methods SHALL NOT BE OVERRIDDEN by SuperApps inheriting from this contract.
    // If more fine grained control than provided by the onX callbacks is needed,
    // you should implement the more generic low-level API of `ISuperApp` instead of using this base contract.

    // The before-callbacks are implemented to relay data (flowrate, timestamp) to the after-callbacks.
    // The after-callbacks invoke the more convenient onX callbacks.

    // CREATED callback

    // Empty implementation to fulfill the interface - is never called because disabled in the app manifest.
    function beforeAgreementCreated(
        ISuperToken /*superToken*/,
        address /*agreementClass*/,
        bytes32 /*agreementId*/,
        bytes calldata /*agreementData*/,
        bytes calldata /*ctx*/
    ) external pure override returns (bytes memory /*beforeData*/) {
        return "0x";
    }

    function afterAgreementCreated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 /*agreementId*/,
        bytes calldata agreementData,
        bytes calldata /*cbdata*/,
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        if (msg.sender != address(HOST)) revert UnauthorizedHost();
        if (!_isAcceptedAgreement(agreementClass)) return ctx;
        if (!isAcceptedSuperToken(superToken)) revert NotAcceptedSuperToken();

        (address sender, ) = abi.decode(agreementData, (address, address));

        return
            onFlowCreated(
                superToken,
                sender,
                ctx // userData can be acquired with `host.decodeCtx(ctx).userData`
            );
    }

    // UPDATED callbacks

    function beforeAgreementUpdated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 /*agreementId*/,
        bytes calldata agreementData,
        bytes calldata /*ctx*/
    ) external view override returns (bytes memory /*beforeData*/) {
        if (msg.sender != address(HOST)) revert UnauthorizedHost();
        if (!_isAcceptedAgreement(agreementClass)) return "0x";
        if (!isAcceptedSuperToken(superToken)) revert NotAcceptedSuperToken();

        (address sender, ) = abi.decode(agreementData, (address, address));
        (uint256 lastUpdated, int96 flowRate,,) = superToken.getCFAFlowInfo(sender, address(this));

        return abi.encode(
            flowRate,
            lastUpdated
        );
    }

    function afterAgreementUpdated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 /*agreementId*/,
        bytes calldata agreementData,
        bytes calldata cbdata,
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        if (msg.sender != address(HOST)) revert UnauthorizedHost();
        if (!_isAcceptedAgreement(agreementClass)) return ctx;
        if (!isAcceptedSuperToken(superToken)) revert NotAcceptedSuperToken();

        (address sender, ) = abi.decode(agreementData, (address, address));
        (int96 previousFlowRate, uint256 lastUpdated) = abi.decode(cbdata, (int96, uint256));

        return
            onFlowUpdated(
                superToken,
                sender,
                previousFlowRate,
                lastUpdated,
                ctx // userData can be acquired with `host.decodeCtx(ctx).userData`
            );
    }

    // DELETED callbacks

    function beforeAgreementTerminated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 /*agreementId*/,
        bytes calldata agreementData,
        bytes calldata /*ctx*/
    ) external view override returns (bytes memory /*beforeData*/) {
        // we're not allowed to revert in this callback, thus just return empty beforeData on failing checks
        if (msg.sender != address(HOST)
            || !_isAcceptedAgreement(agreementClass)
            || !isAcceptedSuperToken(superToken))
        {
            return "0x";
        }

        (address sender, address receiver) = abi.decode(agreementData, (address, address));
        (uint256 lastUpdated, int96 flowRate,,) = superToken.getCFAFlowInfo(sender, receiver);

        return abi.encode(
            lastUpdated,
            flowRate
        );
    }

    function afterAgreementTerminated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 /*agreementId*/,
        bytes calldata agreementData,
        bytes calldata cbdata,
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        // we're not allowed to revert in this callback, thus just return ctx on failing checks
        if (msg.sender != address(HOST)
            || !_isAcceptedAgreement(agreementClass)
            || !isAcceptedSuperToken(superToken))
        {
            return ctx;
        }

        (address sender, address receiver) = abi.decode(agreementData, (address, address));
        (uint256 lastUpdated, int96 previousFlowRate) = abi.decode(cbdata, (uint256, int96));

        if (receiver == address(this)) {
            return
                onFlowDeleted(
                    superToken,
                    sender,
                    previousFlowRate,
                    lastUpdated,
                    ctx
                );
        } else {
            return
                onOutflowDeleted(
                    superToken,
                    receiver,
                    previousFlowRate,
                    lastUpdated,
                    ctx
                );
        }
    }


    // ---------------------------------------------------------------------------------------------
    // HELPERS

    /**
     * @dev Expect Super Agreement involved in callback to be an accepted one
     *      This function can be overridden with custom logic and to revert if desired
     *      Current implementation expects ConstantFlowAgreement
     */
    function _isAcceptedAgreement(address agreementClass) internal view returns (bool) {
        return agreementClass == address(HOST.getAgreementClass(CFAV1_TYPE));
    }
}
