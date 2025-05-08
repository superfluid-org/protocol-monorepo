// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

// What do you expect...
// solhint-disable max-states-count

import { CFAv1Forwarder } from "./CFAv1Forwarder.sol";
import { GDAv1Forwarder } from "./GDAv1Forwarder.sol";
import { ISuperfluid, ISuperfluidToken, Superfluid } from "../superfluid/Superfluid.sol";
import { TestGovernance } from "./TestGovernance.sol";
import { ConstantFlowAgreementV1 } from "../agreements/ConstantFlowAgreementV1.sol";
import { PoolAdminNFT, IPoolAdminNFT } from "../agreements/gdav1/PoolAdminNFT.sol";
import { PoolMemberNFT, IPoolMemberNFT } from "../agreements/gdav1/PoolMemberNFT.sol";
import { InstantDistributionAgreementV1 } from "../agreements/InstantDistributionAgreementV1.sol";
import {
    IGeneralDistributionAgreementV1,
    GeneralDistributionAgreementV1
} from "../agreements/gdav1/GeneralDistributionAgreementV1.sol";
import { SuperTokenFactory } from "../superfluid/SuperTokenFactory.sol";
import { TestToken } from "./TestToken.sol";
import { PureSuperToken } from "../tokens/PureSuperToken.sol";
import { SETHProxy } from "../tokens/SETH.sol";
import { ISuperToken, SuperToken, IConstantOutflowNFT, IConstantInflowNFT } from "../superfluid/SuperToken.sol";
import { TestResolver } from "./TestResolver.sol";
import { SuperfluidLoader } from "./SuperfluidLoader.sol";
import { SuperfluidPool } from "../agreements/gdav1/SuperfluidPool.sol";
import { SuperfluidUpgradeableBeacon } from "../upgradability/SuperfluidUpgradeableBeacon.sol";
import { UUPSProxy } from "../upgradability/UUPSProxy.sol";
import { BatchLiquidator } from "./BatchLiquidator.sol";
import { TOGA } from "./TOGA.sol";
import { IResolver } from "../interfaces/utils/IResolver.sol";
import { SimpleForwarder } from "../utils/SimpleForwarder.sol";
import { ERC2771Forwarder } from "../utils/ERC2771Forwarder.sol";
import { MacroForwarder } from "../utils/MacroForwarder.sol";

/// @title Superfluid Framework Deployment Steps
/// @author Superfluid
/// @notice A contract which splits framework deployment into steps.
/// @dev This was necessary because of the contract size limit of the deployed contract
///      which is an issue when deploying the original framework with Hardhat.
/// https://github.com/NomicFoundation/hardhat/issues/3404#issuecomment-1346849400
contract SuperfluidFrameworkDeploymentSteps {
    bool public constant DEFAULT_NON_UPGRADEABLE = false;
    bool public constant DEFAULT_APP_WHITELISTING_ENABLED = false;
    address public constant DEFAULT_REWARD_ADDRESS = address(69);
    uint256 public constant DEFAULT_LIQUIDATION_PERIOD = 4 hours;
    uint256 public constant DEFAULT_PATRICIAN_PERIOD = 30 minutes;
    uint256 public constant DEFAULT_TOGA_MIN_BOND_DURATION = 1 weeks;

    string public constant RESOLVER_BASE_SUPER_TOKEN_KEY = "supertokens.test.";
    string public constant RESOLVER_BASE_TOKEN_KEY = "tokens.test.";

    struct Framework {
        TestGovernance governance;
        Superfluid host;
        ConstantFlowAgreementV1 cfa;
        InstantDistributionAgreementV1 ida;
        GeneralDistributionAgreementV1 gda;
        SuperTokenFactory superTokenFactory;
        ISuperToken superTokenLogic;
        TestResolver resolver;
        SuperfluidLoader superfluidLoader;
        CFAv1Forwarder cfaV1Forwarder;
        GDAv1Forwarder gdaV1Forwarder;
        MacroForwarder macroForwarder;
        BatchLiquidator batchLiquidator;
        TOGA toga;
    }

    uint8 private currentStep;

    // Core Contracts
    TestGovernance internal testGovernance;
    Superfluid internal host;

    // Agreement Contracts
    ConstantFlowAgreementV1        internal cfaV1;
    InstantDistributionAgreementV1 internal idaV1;
    GeneralDistributionAgreementV1 internal gdaV1;

    // SuperToken-related Contracts
    PoolAdminNFT       internal poolAdminNFT;
    PoolMemberNFT      internal poolMemberNFT;

    ISuperToken       internal superTokenLogic;
    SuperTokenFactory internal superTokenFactory;

    // Forwarders
    CFAv1Forwarder internal cfaV1Forwarder;
    GDAv1Forwarder internal gdaV1Forwarder;
    MacroForwarder internal macroForwarder;

    // Other Peripheral Contracts
    TestResolver internal testResolver;
    SuperfluidLoader internal superfluidLoader;
    BatchLiquidator internal batchLiquidator;
    TOGA internal toga;

    error DEPLOY_TOGA_REQUIRES_1820();
    error DEPLOY_SUPER_TOKEN_REQUIRES_1820();
    error DEPLOY_SUPER_TOKEN_REQUIRES_DEPLOY_SUPER_TOKEN_CONTRACTS();
    error RESOLVER_LIST_REQUIRES_DEPLOY_PERIPHERALS();

    /// @notice Fetches the framework contracts
    function getFramework() external view returns (Framework memory sf) {
        sf = Framework({
            governance: testGovernance,
            host: host,
            cfa: cfaV1,
            ida: idaV1,
            gda: gdaV1,
            superTokenFactory: superTokenFactory,
            superTokenLogic: superTokenLogic,
            resolver: testResolver,
            superfluidLoader: superfluidLoader,
            cfaV1Forwarder: cfaV1Forwarder,
            gdaV1Forwarder: gdaV1Forwarder,
            macroForwarder: macroForwarder,
            batchLiquidator: batchLiquidator,
            toga: toga
        });
        return sf;
    }

    /// @notice Transfer ownership of the TestGovernance contract
    /// @dev This function allows you to transfer ownership of TestGovernance when testing
    /// @param newOwner the new owner of the TestGovernance contract
    function transferOwnership(address newOwner) public {
        testGovernance.transferOwnership(newOwner);
    }

    function getNumSteps() public pure returns (uint8) {
        return 7;
    }

    function executeStep(uint8 step) public {
        if (step != currentStep) revert("Incorrect step");

        if (step == 0) { // CORE CONTRACT: TestGovernance
            // Deploy TestGovernance, a Superfluid Governance for testing purpose. It needs initialization later.
            testGovernance = SuperfluidGovDeployerLibrary.deployTestGovernance();
            SuperfluidGovDeployerLibrary.transferOwnership(testGovernance, address(this));
        } else if (step == 1) { // CORE CONTRACT: Superfluid (Host)
            SimpleForwarder simpleForwarder = new SimpleForwarder();
            ERC2771Forwarder erc2771Forwarder = new ERC2771Forwarder();
            // Deploy Host and initialize the test governance.
            // 3_000_000 is the min callback gas limit used in a prod deployment
            host = SuperfluidHostDeployerLibrary.deploy(
                true, false, 3_000_000, address(simpleForwarder), address(erc2771Forwarder)
            );
            simpleForwarder.transferOwnership(address(host));
            erc2771Forwarder.transferOwnership(address(host));

            host.initialize(testGovernance);

            testGovernance.initialize(
                host,
                DEFAULT_REWARD_ADDRESS,
                DEFAULT_LIQUIDATION_PERIOD,
                DEFAULT_PATRICIAN_PERIOD,
                new address[](0) // no trusted forwarders
            );
        } else if (step == 2) { // CORE CONTRACTS: Core Agreements
            ConstantFlowAgreementV1 cfaV1Logic = SuperfluidCFAv1DeployerLibrary.deploy(host);
            InstantDistributionAgreementV1 idaV1Logic = SuperfluidIDAv1DeployerLibrary.deploy(host);
            GeneralDistributionAgreementV1 gdaV1Logic;
            {
                // GDA proxy is not created yet, hence this is a bootstrapping workaround.
                // First deploy the bootstrapping superfluid pool with GDA = address(0),
                // We will redeploy the pool logic and upgrade this in the beacon later.
                SuperfluidPool superfluidPoolLogic =
                    SuperfluidPoolLogicDeployerLibrary.deploy(GeneralDistributionAgreementV1(address(0)));
                SuperfluidUpgradeableBeacon superfluidPoolBeacon =
                    ProxyDeployerLibrary.deploySuperfluidUpgradeableBeacon(address(superfluidPoolLogic));
                gdaV1Logic = SuperfluidGDAv1DeployerLibrary.deploy(host, superfluidPoolBeacon);
            }

            // we set the canonical address based on host.getAgreementClass() because
            // in the upgradeable case, we create a new proxy contract in the function
            // and set it as the canonical agreement.
            testGovernance.registerAgreementClass(host, address(cfaV1Logic));
            cfaV1 = ConstantFlowAgreementV1(address(host.getAgreementClass(cfaV1Logic.agreementType())));
            testGovernance.registerAgreementClass(host, address(idaV1Logic));
            idaV1 = InstantDistributionAgreementV1(address(host.getAgreementClass(idaV1Logic.agreementType())));
            testGovernance.registerAgreementClass(host, address(gdaV1Logic));
            gdaV1 = GeneralDistributionAgreementV1(address(host.getAgreementClass(gdaV1Logic.agreementType())));

            {
                SuperfluidPool superfluidPoolLogic = SuperfluidPoolLogicDeployerLibrary.deploy(gdaV1);
                superfluidPoolLogic.castrate();

                // Deploy SuperfluidPool beacon
                // @note we upgrade the superfluid beacon to point to the new and correct superfluid pool logic
                gdaV1Logic.superfluidPoolBeacon().upgradeTo(address(superfluidPoolLogic));
                gdaV1Logic.superfluidPoolBeacon().transferOwnership(address(host));
            }
        } else if (step == 3) {// PERIPHERAL CONTRACTS: NFT Proxy and Logic
            {
                poolAdminNFT = PoolAdminNFT(address(ProxyDeployerLibrary.deployUUPSProxy()));
                PoolAdminNFT poolAdminNFTLogic =
                    SuperfluidPoolNFTLogicDeployerLibrary.deployPoolAdminNFT(host, gdaV1);
                poolAdminNFTLogic.castrate();
                UUPSProxy(payable(address(poolAdminNFT))).initializeProxy(address(poolAdminNFTLogic));

                poolMemberNFT = PoolMemberNFT(address(ProxyDeployerLibrary.deployUUPSProxy()));
                PoolMemberNFT poolMemberNFTLogic =
                    SuperfluidPoolNFTLogicDeployerLibrary.deployPoolMemberNFT(host, gdaV1);
                poolMemberNFTLogic.castrate();
                UUPSProxy(payable(address(poolMemberNFT))).initializeProxy(address(poolMemberNFTLogic));

                poolAdminNFT.initialize("Pool Admin NFT", "PA");
                poolMemberNFT.initialize("Pool Member NFT", "PM");
            }
        } else if (step == 4) { // PERIPHERAL CONTRACTS: FORWARDERS
            // Deploy CFAv1Forwarder
            cfaV1Forwarder = CFAv1ForwarderDeployerLibrary.deploy(host);
            testGovernance.enableTrustedForwarder(host, ISuperfluidToken(address(0)), address(cfaV1Forwarder));

            // Deploy GDAv1Forwarder
            gdaV1Forwarder = GDAv1ForwarderDeployerLibrary.deploy(host);
            testGovernance.enableTrustedForwarder(host, ISuperfluidToken(address(0)), address(gdaV1Forwarder));

            // Deploy MacroForwarder
            macroForwarder = new MacroForwarder(host);
            testGovernance.enableTrustedForwarder(host, ISuperfluidToken(address(0)), address(macroForwarder));
        } else if (step == 5) {// PERIPHERAL CONTRACTS: SuperToken Logic and SuperTokenFactory Logic
            // Deploy canonical SuperToken logic contract
            superTokenLogic = SuperToken(SuperTokenDeployerLibrary.deploy(
                host,
                poolAdminNFT,
                poolMemberNFT
            ));

            // Deploy SuperToken Factory
            // Note:
            // - Logic contract is used because super token factory caches them as an optimization during upgrade. Read
            //   its code.
            SuperTokenFactory superTokenFactoryLogic = SuperTokenFactoryDeployerLibrary.deploy(
                host,
                superTokenLogic,
                IPoolAdminNFT(poolAdminNFT.getCodeAddress()),
                IPoolMemberNFT(poolMemberNFT.getCodeAddress())
            );

            // 'Update' code with Governance and register SuperTokenFactory with Superfluid
            testGovernance.updateContracts(
                host, address(0), new address[](0), address(superTokenFactoryLogic), address(0)
            );

            // we set the canonical address based on host.getSuperTokenFactory() because
            // in the upgradeable case, we create a new proxy contract in the function
            // and set it as the canonical supertokenfactory.
            superTokenFactory = SuperTokenFactory(address(host.getSuperTokenFactory()));
        } else if (step == 6) {// PERIPHERAL CONTRACTS: Resolver, SuperfluidLoader, TOGA, BatchLiquidator
            // Deploy TestResolver
            // Deploy SuperfluidLoader and make SuperfluidFrameworkDeployer an admin for the TestResolver
            // Set TestGovernance, Superfluid, SuperfluidLoader and CFAv1Forwarder in TestResolver
            testResolver = SuperfluidPeripheryDeployerLibrary.deployTestResolver(address(this));

            // Deploy superfluid loader
            superfluidLoader = SuperfluidPeripheryDeployerLibrary.deploySuperfluidLoader(testResolver);

            // Register Governance with Resolver
            testResolver.set("TestGovernance.test", address(testGovernance));

            // Register Superfluid with Resolver
            testResolver.set("Superfluid.test", address(host));

            // Register SuperfluidLoader with Resolver
            testResolver.set("SuperfluidLoader-v1", address(superfluidLoader));

            // Register CFAv1Forwarder with Resolver
            testResolver.set("CFAv1Forwarder", address(cfaV1Forwarder));

            // Register GDAv1Forwarder with Resolver
            testResolver.set("GDAv1Forwarder", address(gdaV1Forwarder));

            // Make SuperfluidFrameworkDeployer deployer an admin for the TestResolver as well
            testResolver.addAdmin(msg.sender);

            // Deploy batch liquidator
            batchLiquidator = SuperfluidPeripheryDeployerLibrary.deployBatchLiquidator(host);

            // Deploy TOGA
            if (!_is1820Deployed()) revert DEPLOY_TOGA_REQUIRES_1820();
            toga = SuperfluidPeripheryDeployerLibrary.deployTOGA(host, DEFAULT_TOGA_MIN_BOND_DURATION);
            testGovernance.setRewardAddress(host, ISuperfluidToken(address(0)), address(toga));
        } else {
            revert("Invalid step");
        }

        currentStep++;
    }

    function _is1820Deployed() internal view returns (bool) {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24)
        }
        return codeSize != 0;
    }
}

//// External Libraries ////

library SuperfluidGovDeployerLibrary {
    function deployTestGovernance() external returns (TestGovernance) {
        return new TestGovernance();
    }

    function transferOwnership(TestGovernance _gov, address _newOwner) external {
        _gov.transferOwnership(_newOwner);
    }
}

library SuperfluidHostDeployerLibrary {
    function deploy(
        bool _nonUpgradable,
        bool _appWhiteListingEnabled,
        uint64 callbackGasLimit,
        address simpleForwarderAddress,
        address erc2771ForwarderAddress
    )
        external returns (Superfluid)
    {
        return new Superfluid(
            _nonUpgradable, _appWhiteListingEnabled, callbackGasLimit, simpleForwarderAddress, erc2771ForwarderAddress
        );
    }
}

library SuperfluidCFAv1DeployerLibrary {
    function deploy(ISuperfluid _host) external returns (ConstantFlowAgreementV1) {
        return new ConstantFlowAgreementV1(_host);
    }
}

library SuperfluidIDAv1DeployerLibrary {
    function deploy(ISuperfluid _host)
        external
        returns (InstantDistributionAgreementV1)
    {
        return new InstantDistributionAgreementV1(_host);
    }
}

library SuperfluidPoolLogicDeployerLibrary {
    function deploy(GeneralDistributionAgreementV1 gda) external returns (SuperfluidPool) {
        return new SuperfluidPool(gda);
    }
}

library SuperfluidGDAv1DeployerLibrary {
    function deploy(ISuperfluid host, SuperfluidUpgradeableBeacon superfluidPoolBeacon) external
        returns (GeneralDistributionAgreementV1 gdaV1Logic)
    {
        gdaV1Logic = new GeneralDistributionAgreementV1(host, superfluidPoolBeacon);
    }
}

library CFAv1ForwarderDeployerLibrary {
    function deploy(ISuperfluid _host) external returns (CFAv1Forwarder) {
        return new CFAv1Forwarder(_host);
    }
}

library GDAv1ForwarderDeployerLibrary {
    function deploy(ISuperfluid _host) external returns (GDAv1Forwarder) {
        return new GDAv1Forwarder(_host);
    }
}

library SuperTokenDeployerLibrary {
    function deploy(
        ISuperfluid host,
        IPoolAdminNFT poolAdminNFT,
        IPoolMemberNFT poolMemberNFT
    ) external returns (address) {
        return address(new SuperToken(
            host,
            IConstantOutflowNFT(address(0)),
            IConstantInflowNFT(address(0)),
            poolAdminNFT,
            poolMemberNFT
        ));
    }
}

library SuperfluidPoolNFTLogicDeployerLibrary {
    function deployPoolAdminNFT(ISuperfluid host, IGeneralDistributionAgreementV1 gda)
        external
        returns (PoolAdminNFT)
    {
        return new PoolAdminNFT(host, gda);
    }

    function deployPoolMemberNFT(ISuperfluid host, IGeneralDistributionAgreementV1 gda)
        external
        returns (PoolMemberNFT)
    {
        return new PoolMemberNFT(host, gda);
    }
}

library ProxyDeployerLibrary {
    function deployUUPSProxy() external returns (UUPSProxy) {
        return new UUPSProxy();
    }

    function deploySuperfluidUpgradeableBeacon(address logicContract) external returns (SuperfluidUpgradeableBeacon) {
        return new SuperfluidUpgradeableBeacon(logicContract);
    }
}

library TokenDeployerLibrary {
    function deployTestToken(
        string calldata _underlyingName,
        string calldata _underlyingSymbol,
        uint8 _decimals,
        uint256 _mintLimit
    ) external returns (TestToken) {
        return new TestToken(_underlyingName, _underlyingSymbol, _decimals, _mintLimit);
    }

    function deploySETHProxy() external returns (SETHProxy) {
        return new SETHProxy();
    }

    function deployPureSuperToken() external returns (PureSuperToken) {
        return new PureSuperToken();
    }
}

library SuperTokenFactoryDeployerLibrary {
    function deploy(
        ISuperfluid host,
        ISuperToken superTokenLogic,
        IPoolAdminNFT poolAdminNFTLogic,
        IPoolMemberNFT poolMemberNFTLogic
    ) external returns (SuperTokenFactory) {
        return new SuperTokenFactory(
            host,
            superTokenLogic,
            IConstantOutflowNFT(address(0)),
            IConstantInflowNFT(address(0)),
            poolAdminNFTLogic,
            poolMemberNFTLogic
        );
    }
}

library SuperfluidPeripheryDeployerLibrary {
    function deployTestResolver(address additionalAdmin) external returns (TestResolver) {
        return new TestResolver(additionalAdmin);
    }

    function deploySuperfluidLoader(IResolver resolver) external returns (SuperfluidLoader) {
        return new SuperfluidLoader(resolver);
    }

    function deployBatchLiquidator(ISuperfluid host) external returns (BatchLiquidator) {
        return new BatchLiquidator(address(host));
    }

    function deployTOGA(ISuperfluid host, uint256 minBondDuration) external returns (TOGA) {
        return new TOGA(host, minBondDuration);
    }
}
