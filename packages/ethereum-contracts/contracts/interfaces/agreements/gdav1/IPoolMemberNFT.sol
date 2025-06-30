// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { IPoolNFTBase } from "./IPoolNFTBase.sol";

interface IPoolMemberNFT is IPoolNFTBase {
    // PoolMemberNFTData struct storage packing:
    // b = bits
    // WORD 1: | pool   | FREE
    //         | 160b   | 96b
    // WORD 2: | member | FREE
    //         | 160b   | 96b
    // WORD 3: | units  | FREE
    //         | 128b   | 128b
    struct PoolMemberNFTData {
        address pool;
        address member;
        uint128 units;
    }

    /// Errors ///

    error POOL_MEMBER_NFT_NO_ZERO_POOL();
    error POOL_MEMBER_NFT_NO_ZERO_MEMBER();
    error POOL_MEMBER_NFT_NO_UNITS();
    error POOL_MEMBER_NFT_HAS_UNITS();
    error POOL_MEMBER_NFT_ONLY_OWNER();

    function onCreate(address pool, address member) external;

    function onUpdate(address pool, address member) external;

    function onDelete(address pool, address member) external;

    /// Allows the owner to burn their token
    function burn(uint256 tokenId) external;

    /// View Functions ///

    function poolMemberDataByTokenId(uint256 tokenId) external view returns (PoolMemberNFTData memory data);
}