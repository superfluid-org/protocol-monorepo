// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.11;

library SuperfluidLoaderLibrary {
    error UnsupportedNetwork();

    // mainnet
    uint256 private constant ETH_MAINNET = 1;
    uint256 private constant OPTIMISM_MAINNET = 10;
    uint256 private constant BSC_MAINNET = 56;
    uint256 private constant XDAI_MAINNET = 100;
    uint256 private constant POLYGON_MAINNET = 137;
    uint256 private constant BASE_MAINNET = 8453;
    uint256 private constant ARBITRUM_ONE = 42161;
    uint256 private constant CELO_MAINNET = 42220;
    uint256 private constant AVALANCHE_C = 43114;
    uint256 private constant SCROLL_MAINNET = 534352;
    uint256 private constant DEGENCHAIN = 666666666;


    // testnets
    uint256 private constant AVALANCHE_FUJI = 43113;
    uint256 private constant SCROLL_SEPOLIA = 534351;
    uint256 private constant ETH_SEPOLIA = 11155111;
    uint256 private constant OPTIMISM_SEPOLIA = 11155420;
    uint256 private constant BASE_SEPOLIA = 84532;


    function getHost() public view returns (address) {
        // mainnets
        if (block.chainid == ETH_MAINNET) {
            return 0x4E583d9390082B65Bef884b629DFA426114CED6d;
        } else if (block.chainid == OPTIMISM_MAINNET) {
            return 0x567c4B141ED61923967cA25Ef4906C8781069a10;
        } else if (block.chainid == BSC_MAINNET) {
            return 0xd1e2cFb6441680002Eb7A44223160aB9B67d7E6E;
        } else if (block.chainid == XDAI_MAINNET) {
            return 0x2dFe937cD98Ab92e59cF3139138f18c823a4efE7;
        } else if (block.chainid == POLYGON_MAINNET) {
            return 0x3E14dC1b13c488a8d5D310918780c983bD5982E7;
        } else if (block.chainid == BASE_MAINNET) {
            return 0x4C073B3baB6d8826b8C5b229f3cfdC1eC6E47E74;
        } else if (block.chainid == ARBITRUM_ONE) {
            return 0xCf8Acb4eF033efF16E8080aed4c7D5B9285D2192;
        } else if (block.chainid == CELO_MAINNET) {
            return 0xA4Ff07cF81C02CFD356184879D953970cA957585;
        } else if (block.chainid == AVALANCHE_C) {
            return 0x60377C7016E4cdB03C87EF474896C11cB560752C;
        } else if (block.chainid == SCROLL_MAINNET) {
            return 0x0F86a21F6216c061B222c224e315d9FC34520bb7;
        } else if (block.chainid == DEGENCHAIN) {
            return 0xc1314EdcD7e478C831a7a24169F7dEADB2646eD2;
        // testnets
        } else if (block.chainid == AVALANCHE_FUJI) {
            return 0x85Fe79b998509B77BF10A8BD4001D58475D29386;
        } else if (block.chainid == SCROLL_SEPOLIA) {
            return 0x42b05a6016B9eED232E13fd56a8F0725693DBF8e;
        } else if (block.chainid == ETH_SEPOLIA) {
            return 0x109412E3C84f0539b43d39dB691B08c90f58dC7c;
        } else if (block.chainid == OPTIMISM_SEPOLIA) {
            return 0xd399e2Fb5f4cf3722a11F65b88FAB6B2B8621005;
        } else if (block.chainid == BASE_SEPOLIA) {
            return 0x109412E3C84f0539b43d39dB691B08c90f58dC7c;
        } else {
            revert UnsupportedNetwork();
        }
    }
}
