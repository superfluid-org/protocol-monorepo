// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { IPoolMemberNFT } from "../../interfaces/agreements/gdav1/IPoolMemberNFT.sol";
import { PoolNFTBase } from "./PoolNFTBase.sol";
import { IGeneralDistributionAgreementV1, ISuperfluid } from "../../interfaces/superfluid/ISuperfluid.sol";
import { ISuperfluidPool } from "../../interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { ISuperfluidToken } from "../../interfaces/superfluid/ISuperfluidToken.sol";

contract PoolMemberNFT is PoolNFTBase, IPoolMemberNFT {
    //// Storage Variables ////

    /// NOTE: The storage variables in this contract MUST NOT:
    /// - change the ordering of the existing variables
    /// - change any of the variable types
    /// - rename any of the existing variables
    /// - remove any of the existing variables

    /// @notice A mapping from token id to PoolMemberNFT data
    /// PoolMemberNFTData: { address pool, address member, uint128 units }
    /// @dev The token id is uint256(keccak256(abi.encode(pool, member)))
    mapping(uint256 => PoolMemberNFTData) internal _poolMemberDataByTokenId;

    constructor(ISuperfluid host, IGeneralDistributionAgreementV1 gdaV1) PoolNFTBase(host, gdaV1) { }

    // note that this is used so we don't upgrade to wrong logic contract
    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("org.superfluid-finance.contracts.PoolMemberNFT.implementation");
    }

    function _ownerOf(uint256 tokenId) internal view override returns (address) {
        return _poolMemberDataByTokenId[tokenId].member;
    }

    function poolMemberDataByTokenId(uint256 tokenId) public view override returns (PoolMemberNFTData memory data) {
        return _poolMemberDataByTokenId[tokenId];
    }

    /// @notice Reverts - Transfer of pool member NFT is not allowed.
    /// @dev We revert when users attempt to transfer pool member NFTs.
    function _transfer(
        address, // from,
        address, // to,
        uint256 // tokenId
    ) internal pure override {
        revert POOL_NFT_TRANSFER_NOT_ALLOWED();
    }

    function getTokenId(address pool, address member) external view override returns (uint256 tokenId) {
        return _getTokenId(pool, member);
    }

    function _getTokenId(address pool, address member) internal view returns (uint256 tokenId) {
        return uint256(keccak256(abi.encode("PoolMemberNFT", block.chainid, pool, member)));
    }

    /// @inheritdoc PoolNFTBase
    function tokenURI(uint256 tokenId) external view override(IERC721Metadata, PoolNFTBase) returns (string memory) {
        return super._tokenURI(tokenId);
    }

    /// @notice Mints `newTokenId` and transfers it to `member`
    /// @dev `pool` must be a registered pool in the GDA.
    /// `newTokenId` must not exist, `member` cannot be `address(0)`, `pool` cannot be `address(0)`,
    /// and `pool` cannot be `member`.
    /// We emit a {Transfer} event.
    /// @param pool The pool address
    /// @param member The member address
    function onCreate(address pool, address member) external override {
        _mint(pool, member);
    }

    /// @notice Updates token with `tokenId`.
    /// @dev `tokenId` must exist AND we emit a {MetadataUpdate} event
    /// @param pool The pool address
    /// @param member The member address
    function onUpdate(address pool, address member) external override {
        uint256 tokenId = _getTokenId(pool, member);
        address owner = _ownerOf(tokenId);
        assert(owner != address(0));
        PoolMemberNFTData storage data = _poolMemberDataByTokenId[tokenId];
        data.units = ISuperfluidPool(data.pool).getUnits(data.member);

        _triggerMetadataUpdate(tokenId);
    }

    /// @notice Destroys token with `tokenId` and clears approvals from previous owner.
    /// @dev `tokenId` must exist AND we emit a {Transfer} event
    /// @param pool The pool address
    /// @param member The member address
    function onDelete(address pool, address member) external override {
        uint256 tokenId = _getTokenId(pool, member);
        _burn(tokenId);
    }

    function _mint(address pool, address member) internal {
        ISuperfluidToken superToken = ISuperfluidPool(pool).superToken();
        if (!GENERAL_DISTRIBUTION_AGREEMENT_V1.isPool(superToken, pool)) {
            revert POOL_NFT_NOT_REGISTERED_POOL();
        }

        assert(pool != address(0));
        assert(member != address(0));
        assert(pool != member);

        uint256 newTokenId = _getTokenId(pool, member);
        assert(!_exists(newTokenId));

        uint128 units = ISuperfluidPool(pool).getUnits(member);

        if (units == 0) {
            revert POOL_MEMBER_NFT_NO_UNITS();
        }

        // update mapping for new NFT to be minted
        _poolMemberDataByTokenId[newTokenId] = PoolMemberNFTData(pool, member, units);

        // emit mint of new pool member token with newTokenId
        emit Transfer(address(0), member, newTokenId);
    }

    function _burn(uint256 tokenId) internal override {
        PoolMemberNFTData storage data = _poolMemberDataByTokenId[tokenId];
        if (ISuperfluidPool(data.pool).getUnits(data.member) > 0) {
            revert POOL_MEMBER_NFT_HAS_UNITS();
        }

        address owner = _ownerOf(tokenId);
        assert(owner != address(0));
        super._burn(tokenId);

        // remove previous tokenId flow data mapping
        delete _poolMemberDataByTokenId[tokenId];

        // emit burn of pool member token with tokenId
        emit Transfer(owner, address(0), tokenId);
    }
}
