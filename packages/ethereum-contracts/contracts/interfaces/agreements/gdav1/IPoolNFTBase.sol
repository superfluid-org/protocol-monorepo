// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

import { IERC721Metadata } from "@openzeppelin-v5/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IPoolNFTBase is IERC721Metadata {
    error POOL_NFT_APPROVE_TO_CALLER();                             // 0x9212b333
    error POOL_NFT_ONLY_SUPER_TOKEN_FACTORY();                      // 0x1fd7e3d8
    error POOL_NFT_INVALID_TOKEN_ID();                              // 0x09275994
    error POOL_NFT_APPROVE_TO_CURRENT_OWNER();                      // 0x020226d3
    error POOL_NFT_APPROVE_CALLER_NOT_OWNER_OR_APPROVED_FOR_ALL();  // 0x1e82f255
    error POOL_NFT_NOT_REGISTERED_POOL();                           // 0x6421912e
    error POOL_NFT_TRANSFER_NOT_ALLOWED();                          // 0x432fb160
    error POOL_NFT_TRANSFER_CALLER_NOT_OWNER_OR_APPROVED_FOR_ALL(); // 0x4028ee0e

    /// @notice Informs third-party platforms that NFT metadata should be updated
    /// @dev This event comes from https://eips.ethereum.org/EIPS/eip-4906
    /// @param tokenId the id of the token that should have its metadata updated
    event MetadataUpdate(uint256 tokenId);

    function initialize(string memory nftName, string memory nftSymbol) external; // initializer;

    function triggerMetadataUpdate(uint256 tokenId) external;

    /// @notice Gets the token id
    /// @dev For PoolAdminNFT, `account` is admin
    function getTokenId(address pool, address account) external view returns (uint256 tokenId);
}
