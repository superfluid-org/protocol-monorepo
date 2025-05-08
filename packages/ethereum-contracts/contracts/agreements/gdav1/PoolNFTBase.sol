// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

// Notes: We use reserved slots for upgradable contracts.
// solhint-disable max-states-count

// Notes: We use these interfaces in natspec documentation below, grep @inheritdoc
// solhint-disable-next-line no-unused-import
import { IERC165, IERC721, IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { UUPSProxiable } from "../../upgradability/UUPSProxiable.sol";
import { IGeneralDistributionAgreementV1, ISuperfluid } from "../../interfaces/superfluid/ISuperfluid.sol";
import { ISuperTokenFactory } from "../../interfaces/superfluid/ISuperTokenFactory.sol";
import { IPoolNFTBase } from "../../interfaces/agreements/gdav1/IPoolNFTBase.sol";

abstract contract PoolNFTBase is UUPSProxiable, IPoolNFTBase {
    string public constant DEFAULT_BASE_URI = "https://nft.superfluid.finance/pool/v2/getmeta";

    function baseURI() public pure returns (string memory) { return DEFAULT_BASE_URI; }

    /// @notice Superfluid host contract address
    ISuperfluid public immutable HOST;

    /// @notice Superfluid GDAv1 contract address
    IGeneralDistributionAgreementV1 public immutable GENERAL_DISTRIBUTION_AGREEMENT_V1;

    //// Storage Variables ////

    /// NOTE: The storage variables in this contract MUST NOT:
    /// - change the ordering of the existing variables
    /// - change any of the variable types
    /// - rename any of the existing variables
    /// - remove any of the existing variables

    string internal _name;
    string internal _symbol;

    /// @notice Mapping for token approvals
    /// @dev tokenID => approved address mapping
    mapping(uint256 => address) internal _tokenApprovals;

    /// @notice Mapping for operator approvals
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    /// @notice This allows us to add new storage variables in the base contract
    /// without having to worry about messing up the storage layout that exists in COFNFT or CIFNFT.
    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// Slots 5-21 are reserved for future use.
    /// We use this pattern in SuperToken.sol and favor this over the OpenZeppelin pattern
    /// as this prevents silly footgunning.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256 internal _reserve5;
    uint256 private _reserve6;
    uint256 private _reserve7;
    uint256 private _reserve8;
    uint256 private _reserve9;
    uint256 private _reserve10;
    uint256 private _reserve11;
    uint256 private _reserve12;
    uint256 private _reserve13;
    uint256 private _reserve14;
    uint256 private _reserve15;
    uint256 private _reserve16;
    uint256 private _reserve17;
    uint256 private _reserve18;
    uint256 private _reserve19;
    uint256 private _reserve20;
    uint256 internal _reserve21;

    constructor(ISuperfluid host, IGeneralDistributionAgreementV1 gdaV1) {
        HOST = host;
        GENERAL_DISTRIBUTION_AGREEMENT_V1 = gdaV1;
    }

    function initialize(string memory nftName, string memory nftSymbol)
        external
        override
        initializer // OpenZeppelin Initializable
    {
        _name = nftName;
        _symbol = nftSymbol;
    }

    function updateCode(address newAddress) external override {
        ISuperTokenFactory superTokenFactory = HOST.getSuperTokenFactory();
        if (msg.sender != address(superTokenFactory)) {
            revert POOL_NFT_ONLY_SUPER_TOKEN_FACTORY();
        }

        UUPSProxiable._updateCodeAddress(newAddress);
    }

    /// @notice Emits the MetadataUpdate event with `tokenId` as the argument.
    /// @dev Callable by anyone.
    /// @param tokenId the token id to trigger a metaupdate for
    function triggerMetadataUpdate(uint256 tokenId) external {
        _triggerMetadataUpdate(tokenId);
    }

    /// @notice This contract supports IERC165, IERC721 and IERC721Metadata
    /// @dev This is part of the Standard Interface Detection EIP: https://eips.ethereum.org/EIPS/eip-165
    /// @param interfaceId the XOR of all function selectors in the interface
    /// @return boolean true if the interface is supported
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure virtual override returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x80ac58cd // ERC165 Interface ID for ERC721
            || interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /// @inheritdoc IERC721
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _ownerOf(tokenId);
        if (owner == address(0)) {
            revert POOL_NFT_INVALID_TOKEN_ID();
        }
        return owner;
    }

    /// @notice Returns a hardcoded balance of 1
    /// @dev We always return 1 to avoid the need for additional mapping
    /// @return balance = 1
    function balanceOf(
        address // owner
    ) external pure returns (uint256 balance) {
        balance = 1;
    }

    /// @notice Returns the name of the NFT
    /// @dev Should follow the naming convention: (Pool Admin|Pool Member) NFT
    /// @return name of the NFT
    function name() external view virtual override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the NFT
    /// @dev Should follow the naming convention: PA|PM
    /// @return symbol of the NFT
    function symbol() external view virtual override returns (string memory) {
        return _symbol;
    }

    /// @notice This returns the Uniform Resource Identifier (URI), where the metadata for the NFT lives.
    /// @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
    /// @return the token URI
    function tokenURI(uint256 tokenId) external view virtual returns (string memory);

    function _tokenURI(uint256 /*tokenId*/) internal view virtual returns (string memory) {
        return string(abi.encodePacked(baseURI()));
    }

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = PoolNFTBase.ownerOf(tokenId);
        if (to == owner) {
            revert POOL_NFT_APPROVE_TO_CURRENT_OWNER();
        }

        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) {
            revert POOL_NFT_APPROVE_CALLER_NOT_OWNER_OR_APPROVED_FOR_ALL();
        }

        _approve(to, tokenId);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        _requireMinted(tokenId);

        return _tokenApprovals[tokenId];
    }

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) external virtual override {
        _setApprovalForAll(msg.sender, operator, approved);
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /// @inheritdoc IERC721
    function transferFrom(address from, address to, uint256 tokenId) external virtual override {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert POOL_NFT_TRANSFER_CALLER_NOT_OWNER_OR_APPROVED_FOR_ALL();
        }

        _transfer(from, to, tokenId);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId) external virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert POOL_NFT_TRANSFER_CALLER_NOT_OWNER_OR_APPROVED_FOR_ALL();
        }

        _safeTransfer(from, to, tokenId, data);
    }

    /// @notice Returns whether `spender` is allowed to manage `tokenId`.
    /// @dev Will revert if `tokenId` doesn't exist.
    /// @param spender the spender of the token
    /// @param tokenId the id of the token to be spent
    /// @return whether `tokenId` can be spent by `spender`
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = PoolNFTBase.ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    /// @notice Reverts if `tokenId` doesn't exist
    /// @param tokenId the token id whose existence we are checking
    function _requireMinted(uint256 tokenId) internal view {
        if (!_exists(tokenId)) revert POOL_NFT_INVALID_TOKEN_ID();
    }

    /// @notice Returns whether `tokenId` exists
    /// @dev Tokens can be managed by their owner or approved accounts via `approve` or `setApprovalForAll`.
    /// Tokens start existing when they are minted (`_mint`),
    /// and stop existing when they are burned (`_burn`).
    /// @param tokenId the token id we're interested in seeing if exists
    /// @return bool whether ot not the token exists
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function _triggerMetadataUpdate(uint256 tokenId) internal {
        emit MetadataUpdate(tokenId);
    }

    function _approve(address to, uint256 tokenId) internal {
        _tokenApprovals[tokenId] = to;

        emit Approval(_ownerOf(tokenId), to, tokenId);
    }

    function _setApprovalForAll(address owner, address operator, bool approved) internal {
        if (owner == operator) revert POOL_NFT_APPROVE_TO_CALLER();

        _operatorApprovals[owner][operator] = approved;

        emit ApprovalForAll(owner, operator, approved);
    }

    /// @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist.
    /// @param tokenId the token id whose existence we're checking
    /// @return address the address of the owner of `tokenId`
    function _ownerOf(uint256 tokenId) internal view virtual returns (address);

    function _transfer(address from, address to, uint256 tokenId) internal virtual;

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory // data
    ) internal virtual {
        _transfer(from, to, tokenId);
    }

    /// @dev Deletes the tokenApprovals for `tokenId`
    /// @param tokenId the token id whose approvals we're clearing
    function _burn(uint256 tokenId) internal virtual {
        // clear approvals from the previous owner
        delete _tokenApprovals[tokenId];
    }
}
