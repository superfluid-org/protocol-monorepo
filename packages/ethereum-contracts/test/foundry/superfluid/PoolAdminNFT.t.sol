// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IERC165, IERC721, IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { PoolNFTBaseIntegrationTest, FakePool } from "./PoolNFTBase.t.sol";
import { IPoolNFTBase } from "../../../contracts/interfaces/agreements/gdav1/IPoolNFTBase.sol";
import { IPoolAdminNFT } from "../../../contracts/interfaces/agreements/gdav1/IPoolAdminNFT.sol";
import { ISuperfluidPool } from "../../../contracts/agreements/gdav1/SuperfluidPool.sol";

contract PoolAdminNFTIntegrationTest is PoolNFTBaseIntegrationTest {
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                    Revert Tests
    //////////////////////////////////////////////////////////////////////////*/

    function testRevertIfTransferFromForPoolAdminNFT() public {
        address poolAdmin = alice;
        address receiver = bob;

        ISuperfluidPool pool = sf.gda.createPool(superTokenMock, poolAdmin, poolConfig);
        uint256 nftId = _helperGetPoolAdminNftId(address(pool), poolAdmin);

        _helperRevertIfTransferFrom(
            poolAdminNFT, poolAdmin, poolAdmin, receiver, nftId, IPoolNFTBase.POOL_NFT_TRANSFER_NOT_ALLOWED.selector
        );
    }

    function testRevertIfMintingForFakePool() public {
        FakePool pool = new FakePool(alice, address(superTokenMock));
        vm.expectRevert(IPoolNFTBase.POOL_NFT_NOT_REGISTERED_POOL.selector);
        poolAdminNFT.mockMint(address(pool));
    }

    function testRevertIfMintingForNotPool(address _pool) public {
        vm.expectRevert();
        poolAdminNFT.mockMint(_pool);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    Passing Tests
    //////////////////////////////////////////////////////////////////////////*/

    function testProxiableUUIDIsExpectedValue() public view {
        assertEq(
            poolAdminNFT.proxiableUUID(), keccak256("org.superfluid-finance.contracts.PoolAdminNFT.implementation")
        );
    }

    function testTokenURIForPoolAdminNFT(uint256 tokenId) public view {
        assertEq(poolAdminNFT.tokenURI(tokenId), string(abi.encodePacked(poolAdminNFT.baseURI())));
    }
}
