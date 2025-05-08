// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { IPoolAdminNFT } from "../../interfaces/agreements/gdav1/IPoolAdminNFT.sol";
import { PoolNFTBase } from "./PoolNFTBase.sol";
import { IGeneralDistributionAgreementV1, ISuperfluid } from "../../interfaces/superfluid/ISuperfluid.sol";
import { ISuperfluidPool } from "../../interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { ISuperfluidToken } from "../../interfaces/superfluid/ISuperfluidToken.sol";

contract PoolAdminNFT is PoolNFTBase, IPoolAdminNFT {
    //// Storage Variables ////

    /// NOTE: The storage variables in this contract MUST NOT:
    /// - change the ordering of the existing variables
    /// - change any of the variable types
    /// - rename any of the existing variables
    /// - remove any of the existing variables

    /// @notice A mapping from token id to PoolAdminNFT data
    /// PoolAdminNFTData: { address pool, address admin }
    /// @dev The token id is uint256(keccak256(abi.encode(pool, admin)))
    mapping(uint256 => PoolAdminNFTData) internal _poolAdminDataByTokenId;

    constructor(ISuperfluid host, IGeneralDistributionAgreementV1 gdaV1) PoolNFTBase(host, gdaV1) { }

    // note that this is used so we don't upgrade to wrong logic contract
    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("org.superfluid-finance.contracts.PoolAdminNFT.implementation");
    }

    function _ownerOf(uint256 tokenId) internal view override returns (address) {
        return _poolAdminDataByTokenId[tokenId].admin;
    }

    function poolAdminDataByTokenId(uint256 tokenId) external view override returns (PoolAdminNFTData memory data) {
        return _poolAdminDataByTokenId[tokenId];
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

    function getTokenId(address pool, address admin) external view override returns (uint256 tokenId) {
        return _getTokenId(pool, admin);
    }

    function _getTokenId(address pool, address admin) internal view returns (uint256 tokenId) {
        return uint256(keccak256(abi.encode("PoolAdminNFT", block.chainid, pool, admin)));
    }

    /// @inheritdoc PoolNFTBase
    function tokenURI(uint256 tokenId) external view override(IERC721Metadata, PoolNFTBase) returns (string memory) {
        return super._tokenURI(tokenId);
    }

    function mint(address pool) external {
        _mint(pool);
    }

    /// @notice Mints `newTokenId` and transfers it to `admin`
    /// @dev `pool` must be a registered pool in the GDA.
    /// `newTokenId` must not exist, `admin` cannot be `address(0)` and we emit a {Transfer} event.
    /// `admin` cannot be equal to `pool`.
    /// @param pool The pool address
    function _mint(address pool) internal {
        ISuperfluidToken superToken = ISuperfluidPool(pool).superToken();
        if (!GENERAL_DISTRIBUTION_AGREEMENT_V1.isPool(superToken, pool)) {
            revert POOL_NFT_NOT_REGISTERED_POOL();
        }
        ISuperfluidPool poolContract = ISuperfluidPool(pool);
        address admin = poolContract.admin();
        assert(pool != admin);

        uint256 newTokenId = _getTokenId(pool, admin);
        assert(!_exists(newTokenId));

        // update mapping for new NFT to be minted
        _poolAdminDataByTokenId[newTokenId] = PoolAdminNFTData(pool, admin);

        // emit mint of new pool admin token with newTokenId
        emit Transfer(address(0), admin, newTokenId);
    }
}
