// SPDX-License-Identifier: AGPLv3
// solhint-disable reason-string
pragma solidity ^0.8.23;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import {
    IGeneralDistributionAgreementV1, ISuperfluid
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { PoolAdminNFT } from "../../../contracts/agreements/gdav1/PoolAdminNFT.sol";
import { PoolMemberNFT } from "../../../contracts/agreements/gdav1/PoolMemberNFT.sol";
import { PoolNFTBase } from "../../../contracts/agreements/gdav1/PoolNFTBase.sol";

contract PoolNFTBaseMock is PoolNFTBase {
    using Strings for uint256;

    mapping(uint256 => address) private _owners;

    constructor(ISuperfluid host, IGeneralDistributionAgreementV1 gdaV1) PoolNFTBase(host, gdaV1) { }

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("org.superfluid-finance.contracts.PoolNFTBaseMock.implementation");
    }

    /// @dev The owner of here is always the flow sender
    function _ownerOf(uint256 tokenId) internal view override returns (address) {
        return _owners[tokenId];
    }

    function getTokenId(address pool, address account) external view override returns (uint256 tokenId) {
        return _getTokenId(pool, account);
    }

    function _getTokenId(address pool, address account) internal view returns (uint256 tokenId) {
        return uint256(keccak256(abi.encode("PoolNFTMock", block.chainid, pool, account)));
    }

    /// @dev a mock mint function that sets the owner
    function mockMint(address pool, address account) public {
        uint256 tokenId = _getTokenId(pool, account);
        _owners[tokenId] = account;
    }

    function _transfer(
        address, //from,
        address, //to,
        uint256 //tokenId
    ) internal pure override {
        revert POOL_NFT_TRANSFER_NOT_ALLOWED();
    }

    function tokenURI(uint256 tokenId) external pure override returns (string memory) {
        return string(abi.encodePacked("tokenId=", tokenId.toString()));
    }
}

contract PoolAdminNFTMock is PoolAdminNFT {
    constructor(ISuperfluid host, IGeneralDistributionAgreementV1 gdaV1) PoolAdminNFT(host, gdaV1) { }

    /// @dev a mock mint function that exposes the internal _mint function
    function mockMint(address _pool) public {
        _mint(_pool);
    }

    /// @dev this ownerOf doesn't revert if _tokenId doesn't exist
    function mockOwnerOf(uint256 _tokenId) public view returns (address) {
        return _ownerOf(_tokenId);
    }

    /// @dev This exposes the _tokenApprovals storage without the requireMinted call
    function mockGetApproved(uint256 _tokenId) public view returns (address) {
        return _tokenApprovals[_tokenId];
    }
}

contract PoolMemberNFTMock is PoolMemberNFT {
    constructor(ISuperfluid host, IGeneralDistributionAgreementV1 gdaV1) PoolMemberNFT(host, gdaV1) { }

    /// @dev a mock mint function that exposes the internal _mint function
    function mockMint(address _pool, address _member) public {
        _mint(_pool, _member);
    }

    /// @dev a mock burn function that exposes the internal _burn function
    function mockBurn(uint256 _tokenId) public {
        _burn(_tokenId);
    }

    /// @dev this ownerOf doesn't revert if _tokenId doesn't exist
    function mockOwnerOf(uint256 _tokenId) public view returns (address) {
        return _ownerOf(_tokenId);
    }

    /// @dev This exposes the _tokenApprovals storage without the requireMinted call
    function mockGetApproved(uint256 _tokenId) public view returns (address) {
        return _tokenApprovals[_tokenId];
    }
}
