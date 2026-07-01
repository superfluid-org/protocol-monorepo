// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IERC20Metadata } from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    ISuperTokenFactory,
    ISuperToken
} from "../interfaces/superfluid/ISuperTokenFactory.sol";
import {
    ISuperfluid, IPoolAdminNFT
} from "../interfaces/superfluid/ISuperfluid.sol";
import { UUPSProxy } from "../upgradability/UUPSProxy.sol";
import { UUPSProxiable } from "../upgradability/UUPSProxiable.sol";
import { FullUpgradableSuperTokenProxy } from "./FullUpgradableSuperTokenProxy.sol";
import { IPoolMemberNFT } from "./SuperToken.sol";

abstract contract SuperTokenFactoryBase is
    UUPSProxiable,
    ISuperTokenFactory
{
    /**************************************************************************
    * Immutable Variables
    **************************************************************************/

    // solhint-disable-next-line var-name-mixedcase
    ISuperToken immutable public _SUPER_TOKEN_LOGIC;

    ISuperfluid immutable internal _host;

    // solhint-disable-next-line var-name-mixedcase
    IPoolAdminNFT immutable public POOL_ADMIN_NFT_LOGIC;

    // solhint-disable-next-line var-name-mixedcase
    IPoolMemberNFT immutable public POOL_MEMBER_NFT_LOGIC;

    /**************************************************************************
    * Storage Variables
    **************************************************************************/

    /* WARNING: NEVER RE-ORDER VARIABLES! Including the base contracts.
        Always double-check that new
        variables are added APPEND-ONLY. Re-ordering variables can
        permanently BREAK the deployed proxy contract. */

    // @dev This is the old SuperToken logic contract that is no longer used
    // It is kept here for backwards compatibility due to the fact that we cannot
    // change the storage layout of the contract
    ISuperToken internal _superTokenLogicDeprecated;

    // @dev Deprecated mapping from removed canonical wrapper APIs (v1.4.3 experiment).
    // It is kept here for backwards compatibility due to the fact that we cannot
    // change the storage layout of the contract
    mapping(address => address) internal _canonicalWrapperSuperTokensDeprecated;

    /// NOTE: Whenever modifying the storage layout here it is important to update the validateStorageLayout
    /// function in its respective mock contract to ensure that it doesn't break anything or lead to unexpected
    /// behaviors/layout when upgrading

    constructor(
        ISuperfluid host,
        ISuperToken superTokenLogic,
        IPoolAdminNFT poolAdminNFTLogic,
        IPoolMemberNFT poolMemberNFTLogic
    ) {
        _host = host;

        // SuperToken logic is now deployed prior to new factory logic deployment
        // and passed in as a parameter to SuperTokenFactory constructor
        _SUPER_TOKEN_LOGIC = superTokenLogic;

        // this is optional - allow to fail in order to not force re-deployment
        // solhint-disable-next-line no-empty-blocks
        try UUPSProxiable(address(_SUPER_TOKEN_LOGIC)).castrate() {}
        // solhint-disable-next-line no-empty-blocks
        catch {}

        POOL_ADMIN_NFT_LOGIC = poolAdminNFTLogic;

        POOL_MEMBER_NFT_LOGIC = poolMemberNFTLogic;

        // emit SuperTokenLogicCreated event
        // note that creation here means the setting of the super token logic contract
        // as the canonical super token logic for the Superfluid framework and not the
        // actual contract creation
        emit SuperTokenLogicCreated(_SUPER_TOKEN_LOGIC);
    }

    /// @inheritdoc ISuperTokenFactory
    function getHost()
       external view
       override(ISuperTokenFactory)
       returns(address host)
    {
       return address(_host);
    }

    /**************************************************************************
    * UUPSProxiable
    **************************************************************************/
    /// @inheritdoc ISuperTokenFactory
    function initialize()
        external
        override
        initializer // OpenZeppelin Initializable
    // solhint-disable-next-line no-empty-blocks
    {

    }

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("org.superfluid-finance.contracts.SuperTokenFactory.implementation");
    }

    /// @notice Updates the logic contract for the SuperTokenFactory
    /// @dev This function updates the logic contract for the SuperTokenFactory
    /// @param newAddress the new address of the SuperTokenFactory logic contract
    function updateCode(address newAddress) external override {
        if (msg.sender != address(_host)) {
            revert SUPER_TOKEN_FACTORY_ONLY_HOST();
        }
        _updateCodeAddress(newAddress);

        // Upgrade the PoolAdminNFT logic contract on the canonical proxy
        // We only do this if the new logic contract passed in updating the SuperTokenFactory
        // is different from the current logic contract
        SuperTokenFactory newFactory = SuperTokenFactory(newAddress);

        if (address(POOL_ADMIN_NFT_LOGIC) != address(newFactory.POOL_ADMIN_NFT_LOGIC())) {
            UUPSProxiable(address(_SUPER_TOKEN_LOGIC.POOL_ADMIN_NFT())).updateCode(
                address(newFactory.POOL_ADMIN_NFT_LOGIC())
            );
        }
    }

    /**************************************************************************
    * ISuperTokenFactory
    **************************************************************************/
    /// @inheritdoc ISuperTokenFactory
    function getSuperTokenLogic()
        external view override
        returns (ISuperToken)
    {
        return _SUPER_TOKEN_LOGIC;
    }

    function createERC20Wrapper(
        IERC20Metadata underlyingToken,
        uint8 underlyingDecimals,
        Upgradability upgradability,
        string calldata name,
        string calldata symbol,
        address admin
    ) public override returns (ISuperToken superToken) {
        if (address(underlyingToken) == address(0)) {
            revert SUPER_TOKEN_FACTORY_ZERO_ADDRESS();
        }

        if (upgradability == Upgradability.NON_UPGRADABLE) {
            revert SUPER_TOKEN_FACTORY_NON_UPGRADEABLE_IS_DEPRECATED();
        } else if (upgradability == Upgradability.SEMI_UPGRADABLE) {
            UUPSProxy proxy = new UUPSProxy();
            // initialize the wrapper
            proxy.initializeProxy(address(_SUPER_TOKEN_LOGIC));
            superToken = ISuperToken(address(proxy));
        } else /* if (type == Upgradability.FULL_UPGRADABLE) */ {
            FullUpgradableSuperTokenProxy proxy = new FullUpgradableSuperTokenProxy();
            proxy.initialize();
            superToken = ISuperToken(address(proxy));
        }

        // initialize the token
        superToken.initializeWithAdmin(
            underlyingToken,
            underlyingDecimals,
            name,
            symbol,
            admin
        );

        emit SuperTokenCreated(superToken);
    }

    /// @inheritdoc ISuperTokenFactory
    function createERC20Wrapper(
        IERC20Metadata underlyingToken,
        uint8 underlyingDecimals,
        Upgradability upgradability,
        string calldata name,
        string calldata symbol
    )
        external override
        returns (ISuperToken superToken)
    {
        return createERC20Wrapper(
            underlyingToken,
            underlyingDecimals,
            upgradability,
            name,
            symbol,
            address(0)
        );
    }

    /// @inheritdoc ISuperTokenFactory
    function createERC20Wrapper(
        IERC20Metadata underlyingToken,
        Upgradability upgradability,
        string calldata name,
        string calldata symbol,
        address admin
    )
        external override
        returns (ISuperToken superToken)
    {
        return createERC20Wrapper(
            underlyingToken,
            underlyingToken.decimals(),
            upgradability,
            name,
            symbol,
            admin
        );
    }

    /// @inheritdoc ISuperTokenFactory
    function createERC20Wrapper(
        IERC20Metadata underlyingToken,
        Upgradability upgradability,
        string calldata name,
        string calldata symbol
    )
        external override
        returns (ISuperToken superToken)
    {
        return createERC20Wrapper(
            underlyingToken,
            underlyingToken.decimals(),
            upgradability,
            name,
            symbol,
            address(0)
        );
    }

    /// @inheritdoc ISuperTokenFactory
    function initializeCustomSuperToken(
        address customSuperTokenProxy
    )
        external override
    {
        // odd solidity stuff..
        // NOTE payable necessary because UUPSProxy has a payable fallback function
        address payable a = payable(address(uint160(customSuperTokenProxy)));
        UUPSProxy(a).initializeProxy(address(_SUPER_TOKEN_LOGIC));

        emit CustomSuperTokenCreated(ISuperToken(customSuperTokenProxy));
    }
}

contract SuperTokenFactory is SuperTokenFactoryBase
{
    /* WARNING: NEVER RE-ORDER VARIABLES! Including the base contracts.
        Always double-check that new
        variables are added APPEND-ONLY. Re-ordering variables can
        permanently BREAK the deployed proxy contract. */

    constructor(
        ISuperfluid host,
        ISuperToken superTokenLogic,
        IPoolAdminNFT poolAdminNFTLogic,
        IPoolMemberNFT poolMemberNFTLogic
    )
        SuperTokenFactoryBase(
            host,
            superTokenLogic,
            poolAdminNFTLogic,
            poolMemberNFTLogic
        )
    // solhint-disable-next-line no-empty-blocks
    {}
}
