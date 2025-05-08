// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import {
    ISuperfluid, ISuperToken, SuperAppBase, ISuperApp, SuperAppDefinitions, ISuperAgreement
} from "../apps/SuperAppBase.sol";
import { SuperTokenV1Library } from "../apps/SuperTokenV1Library.sol";

contract StreamRedirector is SuperAppBase {
    using SuperTokenV1Library for ISuperToken;
    ISuperfluid public host;
    bytes32 public constant CFA_ID =
        keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    address public receiver; // flow is redirected to hardcoded receiver address
    ISuperToken public token; // accepted super token

    constructor(
        ISuperfluid _host,
        ISuperToken _token,
        address _receiver,
        uint256 _appLevel
    ) {
        assert(address(_token) != address(0));
        assert(address(_receiver) != address(0));
        assert(address(_host) != address(0));

        host = _host;

        uint256 configWord = _appLevel |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

        token = _token;
        receiver = _receiver;

        host.registerAppWithKey(configWord, "");
    }

    /**
     * Custom Errors
     */
    error OnlyHost();
    error OnlyCFA();
    error UnsupportedToken();

    /**
     * Creates a stream from an _originAccount who has granted this SuperApp ACL permissions
     * to this SuperApp.
     * @param _originAccount ACL permissions granter
     * @param _flowRate desired flow rate
     */
    function startStreamToSelf(address _originAccount, int96 _flowRate) public {
        token.createFlowFrom(
            _originAccount,
            address(this),
            _flowRate
        );
    }

    /**
     * Terminates a stream from an _originAccount who has granted this SuperApp ACL permissions
     * @param _originAccount ACL permissions granter
     */
    function stopStreamToSelf(address _originAccount) public {
        token.deleteFlowFrom(_originAccount, address(this));
    }

    /**
     * Creates a stream from this Super App to another SuperApp.
     * @param _superApp the targeted super app
     * @param _flowRate desired flow rate
     */
    function startStreamToSuperApp(address _superApp, int96 _flowRate) public {
        token.createFlow(_superApp,_flowRate);
    }

    /**
     * Delete a stream from sender to receiver.
     * @param _sender the sender super app
     * @param _receiver the receiver super app
     */
    function stopStreamToSuperApp(address _sender, address _receiver) public {
        token.deleteFlow(_sender, _receiver);
    }

    /**
     * A callback which occurs after CF agreement creation which redirects a stream.
     */
    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // agreementId,
        bytes calldata, // agreementData,
        bytes calldata, // cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyHost
        onlySupportedSuperToken(_superToken)
        onlyCFA(_agreementClass)
        returns (bytes memory newCtx)
    {
        newCtx = _ctx;
        newCtx = _superToken.createFlowWithCtx(
            receiver,
            _superToken.getNetFlowRate(address(this)),
            newCtx
        );
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // calldata _agreementData,
        bytes calldata, // calldata _cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        if (!_isCFAv1(_agreementClass) || address(_superToken) != address(token)) {
            return _ctx;
        }

        newCtx = _ctx;
        int96 currentFlowRate = _superToken.getFlowRate(address(this), receiver);

        if (currentFlowRate > 0) {
            newCtx = _superToken.deleteFlowWithCtx(
                address(this),
                receiver,
                newCtx
            );
        }
    }

    /**
     * Alleviates the composite app rule by allowing this app to call
     * the target app.
     * @param _targetApp address of the target super app, should be initialized with final_level
     */
    function allowCompositeApp(address _targetApp) public {
        host.allowCompositeApp(ISuperApp(_targetApp));
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return ISuperAgreement(agreementClass).agreementType() == CFA_ID;
    }

    /**
     * Modifiers
     */
    modifier onlyHost() {
        if (msg.sender != address(host)) revert OnlyHost();
        _;
    }
    modifier onlySupportedSuperToken(ISuperToken _superToken) {
        if (address(_superToken) != address(token)) revert UnsupportedToken();
        _;
    }

    modifier onlyCFA(address agreementClass) {
        if (!_isCFAv1(agreementClass)) revert OnlyCFA();
        _;
    }
}
