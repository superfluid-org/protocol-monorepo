// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IERC165, IERC721, IERC721Metadata } from "@openzeppelin/contracts/interfaces/IERC721Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import {
    PoolNFTBaseStorageLayoutMock,
    PoolAdminNFTStorageLayoutMock,
    PoolMemberNFTStorageLayoutMock
} from "./PoolNFTUpgradabilityMock.t.sol";
import { IPoolNFTBase, PoolNFTBase } from "../../../contracts/agreements/gdav1/PoolNFTBase.sol";
import { TestToken } from "../../../contracts/utils/TestToken.sol";
import { PoolAdminNFT, IPoolAdminNFT } from "../../../contracts/agreements/gdav1/PoolAdminNFT.sol";
import { PoolMemberNFT, IPoolMemberNFT } from "../../../contracts/agreements/gdav1/PoolMemberNFT.sol";
import { PoolNFTBaseMock } from "./PoolNFTMock.t.sol";
import { ISuperfluidPool } from "../../../contracts/agreements/gdav1/SuperfluidPool.sol";
import { ERC721IntegrationTest } from "./ERC721.t.sol";

/// @title PoolNFTBaseIntegrationTest
/// @author Superfluid
/// @dev This is a base contract for testing PoolNFTBase
/// We test the functions in the PoolNFTBase directly via the base contract
/// and the assumption is that because it is tested here, it is tested for all
/// the derived contracts.
abstract contract PoolNFTBaseIntegrationTest is ERC721IntegrationTest {
    using Strings for uint256;

    string public constant NAME = "Pool NFT Base";
    string public constant SYMBOL = "PNFTB";

    PoolNFTBaseMock public poolNFTBaseMock;

    function setUp() public virtual override {
        super.setUp();
        poolNFTBaseMock = new PoolNFTBaseMock(sf.host, sf.gda);
        poolNFTBaseMock.initialize(NAME, SYMBOL);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Revert Tests
    //////////////////////////////////////////////////////////////////////////*/
    function testRevertIfContractAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");

        poolNFTBaseMock.initialize(NAME, SYMBOL);
    }

    function testRevertIfOwnerOfForNonExistentToken(uint256 _tokenId) public {
        _helperRevertIfOwnerOf(poolAdminNFT, _tokenId, IPoolNFTBase.POOL_NFT_INVALID_TOKEN_ID.selector);
    }

    function testRevertIfGetApprovedCalledForNonExistentToken(uint256 _tokenId) public {
        _helperRevertIfGetApproved(poolAdminNFT, _tokenId, IPoolNFTBase.POOL_NFT_INVALID_TOKEN_ID.selector);
    }

    function testRevertIfSetApprovalForAllOperatorApproveToCaller(address _account) public {
        vm.assume(_account != address(0));

        vm.startPrank(_account);
        vm.expectRevert(IPoolNFTBase.POOL_NFT_APPROVE_TO_CALLER.selector);
        poolNFTBaseMock.setApprovalForAll(_account, true);
        vm.stopPrank();
    }

    function testRevertIfApproveToCurrentOwner(address _pool, address _account) public {
        vm.assume(_pool != address(0));
        vm.assume(_account != address(0));

        uint256 nftId = _helperGetPoolNFTBaseMockNftId(_pool, _account);
        poolNFTBaseMock.mockMint(_pool, _account);

        vm.startPrank(_account);
        vm.expectRevert(IPoolNFTBase.POOL_NFT_APPROVE_TO_CURRENT_OWNER.selector);
        poolNFTBaseMock.approve(_account, nftId);
        vm.stopPrank();
    }

    function testRevertIfApproveAsNonOwner(address _pool, address _account, address _approver, address _approvedAccount)
        public
    {
        vm.assume(_pool != address(0));
        vm.assume(_account != address(0));
        /// @dev _account is owner of pool NFT
        vm.assume(_approver != _account);
        vm.assume(_approvedAccount != _account);

        uint256 nftId = _helperGetPoolNFTBaseMockNftId(_pool, _account);
        poolNFTBaseMock.mockMint(_pool, _account);
        vm.expectRevert(IPoolNFTBase.POOL_NFT_APPROVE_CALLER_NOT_OWNER_OR_APPROVED_FOR_ALL.selector);
        vm.startPrank(_approver);
        poolNFTBaseMock.approve(_approvedAccount, nftId);
        vm.stopPrank();
    }

    function testRevertIfTransferFrom(address _pool, address _account, address _recipient) public {
        vm.assume(_pool != address(0));
        vm.assume(_account != address(0));
        vm.assume(_recipient != address(0));

        uint256 nftId = _helperGetPoolNFTBaseMockNftId(_pool, _account);

        poolNFTBaseMock.mockMint(address(_pool), _account);

        _helperRevertIfTransferFrom(
            poolNFTBaseMock, _account, _account, _recipient, nftId, IPoolNFTBase.POOL_NFT_TRANSFER_NOT_ALLOWED.selector
        );
    }

    function testRevertIfSafeTransferFrom(address _pool, address _account, address _recipient) public {
        vm.assume(_pool != address(0));
        vm.assume(_account != address(0));
        vm.assume(_recipient != address(0));

        uint256 nftId = _helperGetPoolNFTBaseMockNftId(_pool, _account);

        poolNFTBaseMock.mockMint(address(_pool), _account);

        _helperRevertIfSafeTransferFrom(
            poolNFTBaseMock, _account, _account, _recipient, nftId, IPoolNFTBase.POOL_NFT_TRANSFER_NOT_ALLOWED.selector
        );
    }

    function testRevertIfSafeTransferFromWithData(address _pool, address _account, address _recipient) public {
        vm.assume(_pool != address(0));
        vm.assume(_account != address(0));
        vm.assume(_recipient != address(0));

        uint256 nftId = _helperGetPoolNFTBaseMockNftId(_pool, _account);

        poolNFTBaseMock.mockMint(address(_pool), _account);

        _helperRevertIfSafeTransferFrom(
            poolNFTBaseMock,
            _account,
            _account,
            _recipient,
            nftId,
            "0x",
            IPoolNFTBase.POOL_NFT_TRANSFER_NOT_ALLOWED.selector
        );
    }

    function testRevertIfTransferFromAsNonOwner(address _pool, address _account, address _recipient) public {
        vm.assume(_pool != address(0));
        vm.assume(_account != address(0));
        vm.assume(_recipient != address(0));
        vm.assume(_recipient != _account);

        uint256 nftId = _helperGetPoolNFTBaseMockNftId(_pool, _account);

        poolNFTBaseMock.mockMint(address(_pool), _account);

        _helperRevertIfTransferFrom(
            poolNFTBaseMock,
            _recipient,
            _account,
            _recipient,
            nftId,
            IPoolNFTBase.POOL_NFT_TRANSFER_CALLER_NOT_OWNER_OR_APPROVED_FOR_ALL.selector
        );
    }

    function testRevertIfSafeTransferFromAsNonOwner(address _pool, address _account, address _recipient) public {
        vm.assume(_pool != address(0));
        vm.assume(_account != address(0));
        vm.assume(_recipient != address(0));
        vm.assume(_recipient != _account);

        uint256 nftId = _helperGetPoolNFTBaseMockNftId(_pool, _account);

        poolNFTBaseMock.mockMint(address(_pool), _account);

        _helperRevertIfSafeTransferFrom(
            poolNFTBaseMock,
            _recipient,
            _account,
            _recipient,
            nftId,
            IPoolNFTBase.POOL_NFT_TRANSFER_CALLER_NOT_OWNER_OR_APPROVED_FOR_ALL.selector
        );
    }

    function testRevertIfSafeTransferFromWithDataAsNonOwner(address _pool, address _account, address _recipient)
        public
    {
        vm.assume(_pool != address(0));
        vm.assume(_account != address(0));
        vm.assume(_recipient != address(0));
        vm.assume(_recipient != _account);

        uint256 nftId = _helperGetPoolNFTBaseMockNftId(_pool, _account);

        poolNFTBaseMock.mockMint(address(_pool), _account);

        _helperRevertIfSafeTransferFrom(
            poolNFTBaseMock,
            _recipient,
            _account,
            _recipient,
            nftId,
            "0x",
            IPoolNFTBase.POOL_NFT_TRANSFER_CALLER_NOT_OWNER_OR_APPROVED_FOR_ALL.selector
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Passing Tests
    //////////////////////////////////////////////////////////////////////////*/

    function testContractSupportsExpectedInterfaces() public view {
        assertEq(poolNFTBaseMock.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(poolNFTBaseMock.supportsInterface(type(IERC721).interfaceId), true);
        assertEq(poolNFTBaseMock.supportsInterface(type(IERC721Metadata).interfaceId), true);
    }

    function testBalanceOfIsAlwaysOne(address owner) public view {
        assertEq(poolNFTBaseMock.balanceOf(owner), 1, "PoolNFTBase: balanceOf is not always one");
    }

    function testHostIsProperlySetInConstructor() public view {
        assertEq(address(poolNFTBaseMock.HOST()), address(sf.host));
    }

    function testGDAv1IsProperlySetInConstructor() public view {
        assertEq(address(poolNFTBaseMock.GENERAL_DISTRIBUTION_AGREEMENT_V1()), address(sf.gda));
    }

    function testNFTMetadataIsProperlyInitialized() public view {
        assertEq(poolNFTBaseMock.name(), NAME);
        assertEq(poolNFTBaseMock.symbol(), SYMBOL);
    }

    function testTokenURI(uint256 tokenId) public view {
        assertEq(poolNFTBaseMock.tokenURI(tokenId), string(abi.encodePacked("tokenId=", tokenId.toString())));
    }

    function testTriggerMetadataUpdate(uint256 tokenId) public {
        _assertEventMetadataUpdate(address(poolNFTBaseMock), tokenId);
        poolNFTBaseMock.triggerMetadataUpdate(tokenId);
    }

    function testApprove(address _account, address _pool, address _approvedAccount)
        public
        virtual
        returns (uint256 nftId)
    {
        vm.assume(_account != address(0));
        vm.assume(_pool != address(0));
        vm.assume(_account != _approvedAccount);

        nftId = _helperGetPoolNFTBaseMockNftId(_pool, _account);
        poolNFTBaseMock.mockMint(_pool, _account);

        _assertEventApproval(address(poolNFTBaseMock), _account, _approvedAccount, nftId);

        vm.startPrank(_account);
        poolNFTBaseMock.approve(_approvedAccount, nftId);
        vm.stopPrank();

        _assertApprovalIsExpected(poolNFTBaseMock, nftId, _approvedAccount);
    }

    function testSetApprovalForAll(address _tokenOwner, address _operator, bool _approved) public {
        vm.assume(_tokenOwner != address(0));
        vm.assume(_tokenOwner != _operator);

        _assertEventApprovalForAll(address(poolNFTBaseMock), _tokenOwner, _operator, _approved);

        vm.startPrank(_tokenOwner);
        poolNFTBaseMock.setApprovalForAll(_operator, _approved);
        vm.stopPrank();

        _assertOperatorApprovalIsExpected(poolNFTBaseMock, _tokenOwner, _operator, _approved);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Helper Functions
    //////////////////////////////////////////////////////////////////////////*/
    function _helperGetPoolNFTBaseMockNftId(address _pool, address _account) internal view returns (uint256) {
        return poolNFTBaseMock.getTokenId(_pool, _account);
    }

    function _helperGetPoolAdminNftId(address _pool, address _poolAdmin) internal view returns (uint256) {
        return poolAdminNFT.getTokenId(_pool, _poolAdmin);
    }

    function _helperGetPoolMemberNftId(address _pool, address _poolMember) internal view returns (uint256) {
        return poolMemberNFT.getTokenId(_pool, _poolMember);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Assertion Helpers
    //////////////////////////////////////////////////////////////////////////*/
    function _assertPoolAdminNftStateIsExpected(uint256 _tokenId, address _expectedPool, address _expectedAdmin)
        public view
    {
        PoolAdminNFT.PoolAdminNFTData memory poolAdminNFTData = poolAdminNFT.poolAdminDataByTokenId(_tokenId);

        assertEq(poolAdminNFTData.pool, _expectedPool, "PoolAdminNFT: pool address not as expected");

        // assert admin is equal to expected admin
        assertEq(poolAdminNFTData.admin, _expectedAdmin, "PoolAdminNFT: admin address not as expected");

        // assert owner of pool admin nft equal to expected admin
        _assertOwnerOfIsExpected(
            poolAdminNFT, _tokenId, _expectedAdmin, "PoolAdminNFT: owner of pool admin nft not as expected"
        );
    }

    function _assertPoolMemberNftStateIsExpected(
        uint256 _tokenId,
        address _expectedPool,
        address _expectedMember,
        uint128 _expectedUnits
    ) public view {
        PoolMemberNFT.PoolMemberNFTData memory poolMemberNFTData = poolMemberNFT.poolMemberDataByTokenId(_tokenId);

        assertEq(poolMemberNFTData.pool, _expectedPool, "PoolMemberNFT: pool address not as expected");

        // assert member is equal to expected member
        assertEq(poolMemberNFTData.member, _expectedMember, "PoolMemberNFT: member address not as expected");

        // assert units is equal to expected units
        assertEq(poolMemberNFTData.units, _expectedUnits, "PoolMemberNFT: units not as expected");

        // assert owner of pool member nft equal to expected member
        _assertOwnerOfIsExpected(
            poolAdminNFT, _tokenId, _expectedMember, "PoolMemberNFT: owner of pool member nft not as expected"
        );
    }
}

/// @title PoolNFTUpgradabilityTest
/// @author Superfluid
/// @notice Used for testing storage layout and upgradability of Pool NFT contracts
contract PoolNFTUpgradabilityTest is PoolNFTBaseIntegrationTest {
    /*//////////////////////////////////////////////////////////////////////////
                                Storage Layout Tests
    //////////////////////////////////////////////////////////////////////////*/
    function testPoolNFTBaseStorageLayout() public {
        PoolNFTBaseStorageLayoutMock poolNFTBaseStorageLayoutMock = new PoolNFTBaseStorageLayoutMock(sf.host, sf.gda);

        poolNFTBaseStorageLayoutMock.validateStorageLayout();
    }

    function testPoolMemberNFTStorageLayout() public {
        PoolMemberNFTStorageLayoutMock poolMemberNFTStorageLayoutMock =
            new PoolMemberNFTStorageLayoutMock(sf.host, sf.gda);

        poolMemberNFTStorageLayoutMock.validateStorageLayout();
    }

    function testPoolAdminNFTStorageLayout() public {
        PoolAdminNFTStorageLayoutMock poolAdminNFTStorageLayoutMock = new PoolAdminNFTStorageLayoutMock(sf.host, sf.gda);

        poolAdminNFTStorageLayoutMock.validateStorageLayout();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Revert Tests
    //////////////////////////////////////////////////////////////////////////*/
    function testRevertPoolNFTContractsCannotBeUpgradedByNonSuperTokenFactory(address notSuperTokenFactory) public {
        vm.assume(notSuperTokenFactory != address(sf.superTokenFactory));
        PoolAdminNFT newPoolAdminNFT = new PoolAdminNFT(sf.host, sf.gda);
        vm.expectRevert(IPoolNFTBase.POOL_NFT_ONLY_SUPER_TOKEN_FACTORY.selector);
        vm.prank(notSuperTokenFactory);
        poolAdminNFT.updateCode(address(newPoolAdminNFT));

        PoolMemberNFT newPoolMemberNFT = new PoolMemberNFT(sf.host, sf.gda);
        vm.expectRevert(IPoolNFTBase.POOL_NFT_ONLY_SUPER_TOKEN_FACTORY.selector);
        vm.prank(notSuperTokenFactory);
        poolMemberNFT.updateCode(address(newPoolMemberNFT));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Passing Tests
    //////////////////////////////////////////////////////////////////////////*/
    function testPoolNFTContractsCanBeUpgradedBySuperTokenFactory() public {
        PoolAdminNFT newPoolAdminNFT = new PoolAdminNFT(sf.host, sf.gda);
        vm.prank(address(sf.superTokenFactory));
        poolAdminNFT.updateCode(address(newPoolAdminNFT));

        PoolMemberNFT newPoolMemberNFT = new PoolMemberNFT(sf.host, sf.gda);
        vm.prank(address(sf.superTokenFactory));
        poolMemberNFT.updateCode(address(newPoolMemberNFT));
    }
}

contract FakePool {
    address public admin;
    address public superToken;

    constructor(address _admin, address _superToken) {
        admin = _admin;
        superToken = _superToken;
    }
}
