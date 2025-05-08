// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IERC721Metadata } from "@openzeppelin/contracts/interfaces/IERC721Metadata.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";
import { PoolAdminNFTMock, PoolMemberNFTMock } from "./PoolNFTMock.t.sol";
import { TestToken } from "../../../contracts/utils/TestToken.sol";
import { PoolAdminNFT, IPoolAdminNFT } from "../../../contracts/agreements/gdav1/PoolAdminNFT.sol";
import { PoolMemberNFT, IPoolMemberNFT } from "../../../contracts/agreements/gdav1/PoolMemberNFT.sol";
import { UUPSProxy } from "../../../contracts/upgradability/UUPSProxy.sol";
import { UUPSProxiable } from "../../../contracts/upgradability/UUPSProxiable.sol";
import { SuperToken, SuperTokenMock, IConstantOutflowNFT, IConstantInflowNFT } from "../../../contracts/mocks/SuperTokenMock.t.sol";

contract ERC721IntegrationTest is FoundrySuperfluidTester {
    string internal constant POOL_MEMBER_NFT_NAME_TEMPLATE = "Pool Member NFT";
    string internal constant POOL_MEMBER_NFT_SYMBOL_TEMPLATE = "PMF";
    string internal constant POOL_ADMIN_NFT_NAME_TEMPLATE = "Pool Admin NFT";
    string internal constant POOL_ADMIN_NFT_SYMBOL_TEMPLATE = "PAF";

    SuperTokenMock public superTokenMock;

    PoolMemberNFTMock public poolMemberNFTLogic;
    PoolAdminNFTMock public poolAdminNFTLogic;

    PoolMemberNFTMock public poolMemberNFT;
    PoolAdminNFTMock public poolAdminNFT;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    event MetadataUpdate(uint256 _tokenId);

    constructor() FoundrySuperfluidTester(5) { }

    function setUp() public virtual override {
        super.setUp();

        // Deploy Pool NFTs

        // deploy pool member NFT contract
        UUPSProxy poolMemberProxy = new UUPSProxy();

        // deploy pool admin NFT contract
        UUPSProxy poolAdminProxy = new UUPSProxy();

        // we deploy mock NFT contracts for the tests to access internal functions
        poolMemberNFTLogic = new PoolMemberNFTMock(sf.host, sf.gda);
        poolAdminNFTLogic = new PoolAdminNFTMock(sf.host, sf.gda);

        poolMemberNFTLogic.castrate();
        poolAdminNFTLogic.castrate();

        // initialize proxy to point at logic
        poolMemberProxy.initializeProxy(address(poolMemberNFTLogic));

        // initialize proxy to point at logic
        poolAdminProxy.initializeProxy(address(poolAdminNFTLogic));

        poolMemberNFT = PoolMemberNFTMock(address(poolMemberProxy));
        poolAdminNFT = PoolAdminNFTMock(address(poolAdminProxy));

        poolMemberNFT.initialize(POOL_MEMBER_NFT_NAME_TEMPLATE, POOL_MEMBER_NFT_SYMBOL_TEMPLATE);

        poolAdminNFT.initialize(POOL_ADMIN_NFT_NAME_TEMPLATE, POOL_ADMIN_NFT_SYMBOL_TEMPLATE);

        // Deploy TestToken
        TestToken testTokenMock = new TestToken("Mock Test", "MT", 18, 100000000);

        // Deploy SuperToken proxy
        UUPSProxy superTokenMockProxy = new UUPSProxy();

        // deploy super token mock for testing with mock constant outflow/inflow NFTs
        SuperTokenMock superTokenMockLogic = new SuperTokenMock(
            sf.host,
            0,
            IConstantOutflowNFT(address(0)),
            IConstantInflowNFT(address(0)),
            IPoolAdminNFT(address(poolAdminNFT)),
            IPoolMemberNFT(address(poolMemberNFT))
        );
        superTokenMockProxy.initializeProxy(address(superTokenMockLogic));

        superTokenMock = SuperTokenMock(address(superTokenMockProxy));
        superTokenMock.initialize(testTokenMock, 18, "Super Mock Test", "MTx");

        // mint tokens to test accounts
        for (uint256 i = 0; i < N_TESTERS; i++) {
            superTokenMock.mintInternal(TEST_ACCOUNTS[i], INIT_SUPER_TOKEN_BALANCE, "0x", "0x");
        }
    }

    // If we properly create mock contracts for the base NFT contracts
    // then we can just use the base NFT contracts for testing these reverts
    // and the other functionality of ERC721 here
    // Instead of testing each of the NFT contracts separately
    function _helperRevertIfOwnerOf(IERC721Metadata _nftContract, uint256 _tokenId, bytes4 _errorSelector) internal {
        vm.expectRevert(_errorSelector);
        _nftContract.ownerOf(_tokenId);
    }

    function _helperRevertIfGetApproved(IERC721Metadata _nftContract, uint256 _tokenId, bytes4 _errorSelector)
        internal
    {
        vm.expectRevert(_errorSelector);
        _nftContract.getApproved(_tokenId);
    }

    function _helperRevertIfTransferFrom(
        IERC721Metadata _nftContract,
        address _caller,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes4 _errorSelector
    ) internal {
        vm.startPrank(_caller);
        vm.expectRevert(_errorSelector);
        _nftContract.transferFrom(_from, _to, _tokenId);
        vm.stopPrank();
    }

    function _helperRevertIfSafeTransferFrom(
        IERC721Metadata _nftContract,
        address _caller,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes4 _errorSelector
    ) internal {
        vm.startPrank(_caller);
        vm.expectRevert(_errorSelector);
        _nftContract.safeTransferFrom(_from, _to, _tokenId);
        vm.stopPrank();
    }

    function _helperRevertIfSafeTransferFrom(
        IERC721Metadata _nftContract,
        address _caller,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data,
        bytes4 _errorSelector
    ) internal {
        vm.startPrank(_caller);
        vm.expectRevert(_errorSelector);
        _nftContract.safeTransferFrom(_from, _to, _tokenId, _data);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Assertion Helpers
    //////////////////////////////////////////////////////////////////////////*/
    function _assertOwnerOfIsExpected(
        IERC721Metadata _nftContract,
        uint256 _tokenId,
        address _expectedOwner,
        string memory _message) public view
    {
        // we use mockOwnerOf to overcome the CFA_NFT_INVALID_TOKEN_ID error
        address owner = PoolAdminNFTMock(address(_nftContract)).mockOwnerOf(_tokenId);

        assertEq(owner, _expectedOwner, _message);
    }

    function _assertApprovalIsExpected(IERC721Metadata _nftContract, uint256 _tokenId, address _expectedApproved)
        public view
    {
        address approved = _nftContract.getApproved(_tokenId);

        assertEq(approved, _expectedApproved);
    }

    function _assertOperatorApprovalIsExpected(
        IERC721Metadata _nftContract,
        address _expectedOwner,
        address _expectedOperator,
        bool _expectedOperatorApproval
    ) public view {
        bool operatorApproval = _nftContract.isApprovedForAll(_expectedOwner, _expectedOperator);

        assertEq(operatorApproval, _expectedOperatorApproval);
    }

    function _assertEventTransfer(
        address _emittingAddress,
        address _expectedFrom,
        address _expectedTo,
        uint256 _expectedTokenId
    ) public {
        vm.expectEmit(true, true, true, false, _emittingAddress);

        emit Transfer(_expectedFrom, _expectedTo, _expectedTokenId);
    }

    function _assertEventApproval(
        address _emittingAddress,
        address _expectedOwner,
        address _expectedApproved,
        uint256 _expectedTokenId
    ) public {
        vm.expectEmit(true, true, true, false, _emittingAddress);

        emit Approval(_expectedOwner, _expectedApproved, _expectedTokenId);
    }

    function _assertEventApprovalForAll(
        address _emittingAddress,
        address _expectedOwner,
        address _expectedOperator,
        bool _expectedApproved
    ) public {
        vm.expectEmit(true, true, false, true, _emittingAddress);

        emit ApprovalForAll(_expectedOwner, _expectedOperator, _expectedApproved);
    }

    function _assertEventMetadataUpdate(address _emittingAddress, uint256 _tokenId) public {
        vm.expectEmit(true, false, false, false, _emittingAddress);

        emit MetadataUpdate(_tokenId);
    }
}
