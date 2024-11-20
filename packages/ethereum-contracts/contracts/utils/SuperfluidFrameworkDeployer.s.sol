// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SuperfluidFrameworkDeploymentSteps, TokenDeployerLibrary } from "./SuperfluidFrameworkDeploymentSteps.t.sol";
import { ISuperTokenFactory } from "../superfluid/SuperTokenFactory.sol";
import { SuperToken } from "../superfluid/SuperToken.sol";
import { TestToken } from "./TestToken.sol";
import { ISETH } from "../interfaces/tokens/ISETH.sol";
import { IPureSuperToken } from "../interfaces/tokens/IPureSuperToken.sol";
import { PureSuperToken } from "../tokens/PureSuperToken.sol";
import { SETHProxy } from "../tokens/SETH.sol";

/// @title Superfluid Framework Deployer
/// @dev This deployer should only be used for local testing environments.
///
///      Notes:
///      - ERC1820 must be deployed as a prerequisite to using this contract.
///      - Some test frameworks may have difficulties in tuning its maximum contract code size limit. Using deployment
///        steps contract solves this issue.
contract SuperfluidFrameworkDeployer is SuperfluidFrameworkDeploymentSteps {
    /// @notice Deploys the Superfluid Framework (Test)
    /// @dev This uses default configurations for the framework.
    /// NOTE: ERC1820 must be deployed as a prerequisite before calling this function.
    function deployTestFramework() external {
        // Default Configs
        for (uint256 i = 0; i < getNumSteps(); ++i) {
            executeStep(uint8(i));
        }
    }

    /// @notice Deploys an ERC20 and a Wrapper Super Token for the ERC20 and lists both in the resolver
    /// @dev SuperToken name and symbol format: `Super ${_underlyingSymbol}` and `${_underlyingSymbol}x`, respectively
    /// @param _underlyingName The underlying token name
    /// @param _underlyingSymbol The token symbol
    /// @param _decimals The token decimals
    /// @param _mintLimit The mint limit of the underlying token
    /// @param _admin The admin address for the Super Token
    /// @return underlyingToken and superToken
    function deployWrapperSuperToken(
        string calldata _underlyingName,
        string calldata _underlyingSymbol,
        uint8 _decimals,
        uint256 _mintLimit,
        address _admin
    )
        external
        requiresSuperTokenFactory
        deploySuperTokenRequires1820
        returns (TestToken underlyingToken, SuperToken superToken)
    {
        return _deployWrapperSuperToken(_underlyingName, _underlyingSymbol, _decimals, _mintLimit, _admin);
    }

    /// @notice Deploys a Native Asset Super Token and lists it in the resolver
    /// @dev e.g. ETHx, MATICx, AVAXx, etc. The underlying is the Native Asset.
    /// @param _name The token name
    /// @param _symbol The super token symbol
    /// @return nativeAssetSuperToken
    function deployNativeAssetSuperToken(string calldata _name, string calldata _symbol)
        external
        requiresSuperTokenFactory
        deploySuperTokenRequires1820
        returns (ISETH nativeAssetSuperToken)
    {
        SETHProxy sethProxy = TokenDeployerLibrary.deploySETHProxy();
        nativeAssetSuperToken = ISETH(address(sethProxy));
        superTokenFactory.initializeCustomSuperToken(address(sethProxy));
        nativeAssetSuperToken.initialize(IERC20(address(0)), 18, _name, _symbol);

        string memory superTokenKey = string.concat(RESOLVER_BASE_SUPER_TOKEN_KEY, _symbol);
        _handleResolverList(true, superTokenKey, address(nativeAssetSuperToken));
    }

    /// @notice Deploys a Pure Super Token and lists it in the resolver
    /// @dev We specify the initial supply (because non-downgradeable) on creation and send it to the deployer
    /// @param _name The token name
    /// @param _symbol The token symbol
    /// @param _initialSupply The initial token supply of the pure super token
    /// @return pureSuperToken
    function deployPureSuperToken(string calldata _name, string calldata _symbol, uint256 _initialSupply)
        external
        requiresSuperTokenFactory
        deploySuperTokenRequires1820
        returns (IPureSuperToken pureSuperToken)
    {
        PureSuperToken pureSuperTokenProxy = TokenDeployerLibrary.deployPureSuperToken();
        superTokenFactory.initializeCustomSuperToken(address(pureSuperTokenProxy));
        pureSuperTokenProxy.initialize(_name, _symbol, _initialSupply);

        pureSuperToken = IPureSuperToken(address(pureSuperTokenProxy));

        _handleResolverList(true, string.concat(RESOLVER_BASE_SUPER_TOKEN_KEY, _symbol), address(pureSuperToken));

        // transfer initial supply to deployer
        pureSuperToken.transfer(msg.sender, _initialSupply);
    }

    function _handleResolverList(bool _listOnResolver, string memory _resolverKey, address _superTokenAddress)
        internal
    {
        if (address(testResolver) == address(0)) revert RESOLVER_LIST_REQUIRES_DEPLOY_PERIPHERALS();
        if (_listOnResolver) {
            testResolver.set(_resolverKey, address(_superTokenAddress));
        }
    }

    function _deployWrapperSuperToken(
        string calldata _underlyingName,
        string calldata _underlyingSymbol,
        uint8 _decimals,
        uint256 _mintLimit,
        address _admin
    ) internal returns (TestToken underlyingToken, SuperToken superToken) {
        underlyingToken =
            TokenDeployerLibrary.deployTestToken(_underlyingName, _underlyingSymbol, _decimals, _mintLimit);

        string memory superTokenSymbol = string.concat(_underlyingSymbol, "x");

        superToken = SuperToken(
            address(
                superTokenFactory.createERC20Wrapper(
                    IERC20Metadata(address(underlyingToken)),
                    underlyingToken.decimals(),
                    ISuperTokenFactory.Upgradability.SEMI_UPGRADABLE,
                    string.concat("Super ", _underlyingSymbol),
                    superTokenSymbol,
                    _admin
                )
            )
        );

        // list underlying token in resolver
        string memory underlyingTokenKey = string.concat(RESOLVER_BASE_TOKEN_KEY, underlyingToken.symbol());
        _handleResolverList(true, underlyingTokenKey, address(underlyingToken));

        // list super token in resolver
        string memory superTokenKey = string.concat(RESOLVER_BASE_SUPER_TOKEN_KEY, superToken.symbol());
        _handleResolverList(true, superTokenKey, address(superToken));
    }

    modifier requiresSuperTokenFactory() {
        if (address(superTokenFactory) == address(0)) revert DEPLOY_SUPER_TOKEN_REQUIRES_DEPLOY_SUPER_TOKEN_CONTRACTS();
        _;
    }

    modifier deploySuperTokenRequires1820() {
        if (!_is1820Deployed()) revert DEPLOY_SUPER_TOKEN_REQUIRES_1820();
        _;
    }
}
