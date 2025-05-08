// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.11;

import { ISuperfluid, ISuperToken, ISuperApp, SuperAppDefinitions } from "../interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "./SuperTokenV1Library.sol";

/**
 * @title abstract base contract for SuperApps using CFA callbacks
 * @author Superfluid
 * @dev This contract provides a more convenient API for implementing CFA callbacks.
 * It allows to write more concise and readable SuperApps when the full flexibility
 * of the low-level agreement callbacks isn't needed.
 * The API is tailored for the most common use cases, with the "beforeX" and "afterX" callbacks being
 * abstrated into a single "onX" callback for create|update|delete flows.
 * For use cases requiring more flexibility (specifically if more data needs to be provided by the before callbacks)
 * it's recommended to implement the low-level callbacks directly instead of using this base contract.
 */
abstract contract CFASuperAppBase is ISuperApp {
    using SuperTokenV1Library for ISuperToken;

    bytes32 public constant CFAV1_TYPE = keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");

    ISuperfluid public immutable HOST;

    /// @dev Thrown when the callback caller is not the host.
    error UnauthorizedHost();

    /// @dev Thrown if a required callback wasn't implemented (overridden by the SuperApp)
    error NotImplemented();

    /// @dev Thrown when SuperTokens not accepted by the SuperApp are streamed to it
    error NotAcceptedSuperToken();

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
     * If a whitelisted factory is used, it needs to call `host.registerApp()` itself.
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
        configWord = SuperAppDefinitions.APP_LEVEL_FINAL
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


    // ---------------------------------------------------------------------------------------------
    // CFA specific convenience callbacks
    // to be overridden and implemented by inheriting SuperApps

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
        address /*receiver*/,
        int96 /*previousFlowRate*/,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal virtual returns (bytes memory /*newCtx*/) {
        return ctx;
    }


    // ---------------------------------------------------------------------------------------------
    // Low-level callbacks
    // Shall NOT be overriden by SuperApps when inheriting from this contract.
    // The before-callbacks are implemented to forward data (flowrate, timestamp),
    // the after-callbacks invoke the CFA specific specific convenience callbacks.

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
        if (!isAcceptedAgreement(agreementClass)) return ctx;
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
        if (!isAcceptedAgreement(agreementClass)) return "0x";
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
        if (!isAcceptedAgreement(agreementClass)) return ctx;
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
            || !isAcceptedAgreement(agreementClass)
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
            || !isAcceptedAgreement(agreementClass)
            || !isAcceptedSuperToken(superToken))
        {
            return ctx;
        }

        (address sender, address receiver) = abi.decode(agreementData, (address, address));
        (uint256 lastUpdated, int96 previousFlowRate) = abi.decode(cbdata, (uint256, int96));

        return
            onFlowDeleted(
                superToken,
                sender,
                receiver,
                previousFlowRate,
                lastUpdated,
                ctx
            );
    }


    // ---------------------------------------------------------------------------------------------
    // HELPERS

    /**
     * @dev Expect Super Agreement involved in callback to be an accepted one
     *      This function can be overridden with custom logic and to revert if desired
     *      Current implementation expects ConstantFlowAgreement
     */
    function isAcceptedAgreement(address agreementClass) internal view virtual returns (bool) {
        return agreementClass == address(HOST.getAgreementClass(CFAV1_TYPE));
    }
}
