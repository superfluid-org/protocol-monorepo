// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IERC165, IERC721, IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { PoolNFTBaseIntegrationTest, FakePool } from "./PoolNFTBase.t.sol";
import { IPoolNFTBase } from "../../../contracts/interfaces/agreements/gdav1/IPoolNFTBase.sol";
import { IPoolMemberNFT } from "../../../contracts/interfaces/agreements/gdav1/IPoolMemberNFT.sol";
import { ISuperfluidPool } from "../../../contracts/agreements/gdav1/SuperfluidPool.sol";
import { IGeneralDistributionAgreementV1 } from "../../../contracts/interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import "forge-std/Test.sol";

contract PoolMemberNFTIntegrationTest is PoolNFTBaseIntegrationTest {
    /*//////////////////////////////////////////////////////////////////////////
                                    Revert Tests
    //////////////////////////////////////////////////////////////////////////*/

    function testRevertIfTransferFromForPoolMemberNFT(address _poolAdmin, address _receiver) public {
        vm.assume(_poolAdmin != address(0));
        vm.assume(_receiver != address(0));

        ISuperfluidPool pool = sf.gda.createPool(superTokenMock, _poolAdmin, poolConfig);
        uint256 nftId = _helperGetPoolMemberNftId(address(pool), alice);

        vm.startPrank(_poolAdmin);
        pool.updateMemberUnits(alice, 1);
        vm.stopPrank();

        _helperRevertIfTransferFrom(
            poolMemberNFT, alice, alice, _receiver, nftId, IPoolNFTBase.POOL_NFT_TRANSFER_NOT_ALLOWED.selector
        );
    }

    function testRevertIfMintingForNotPool(address _pool, address _member) public {
        vm.expectRevert();
        poolMemberNFT.mockMint(_pool, _member);
    }

    function testRevertIfMintingForFakePool(address _admin, address _member) public {
        vm.assume(_admin != address(0));
        vm.assume(_member != address(0));
        FakePool pool = new FakePool(_admin, address(superTokenMock));
        vm.expectRevert(IPoolNFTBase.POOL_NFT_NOT_REGISTERED_POOL.selector);
        poolMemberNFT.mockMint(address(pool), _member);
    }

    function testRevertIfMintingForZeroUnitMember() public {
        address admin_ = alice;
        address member = bob;
        ISuperfluidPool pool = sf.gda.createPool(superTokenMock, admin_, poolConfig);
        vm.expectRevert(IPoolMemberNFT.POOL_MEMBER_NFT_NO_UNITS.selector);
        poolMemberNFT.mockMint(address(pool), member);
    }

    function testRevertIfBurningNFTOfMemberWithUnits(address _admin, address _member) public {
        vm.assume(_admin != address(0));
        vm.assume(_member != address(0));
        ISuperfluidPool pool = sf.gda.createPool(superTokenMock, _admin, poolConfig);
        uint256 nftId = _helperGetPoolMemberNftId(address(pool), _member);

        vm.startPrank(_admin);
        pool.updateMemberUnits(_member, 1);
        vm.stopPrank();

        vm.expectRevert(IPoolMemberNFT.POOL_MEMBER_NFT_HAS_UNITS.selector);
        poolMemberNFT.mockBurn(nftId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Passing Tests
    //////////////////////////////////////////////////////////////////////////*/

    function testProxiableUUIDIsExpectedValue() public view {
        assertEq(
            poolMemberNFT.proxiableUUID(), keccak256("org.superfluid-finance.contracts.PoolMemberNFT.implementation")
        );
    }

    function testTokenURIForPoolMemberNFT(uint256 tokenId) public view {
        assertEq(poolMemberNFT.tokenURI(tokenId), string(abi.encodePacked(poolMemberNFT.baseURI())));
    }
}
