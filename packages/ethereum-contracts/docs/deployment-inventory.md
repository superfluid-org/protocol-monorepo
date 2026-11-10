# Deployment inventory

Observation date: **2026-11-10 (UTC)**. Scope: all 16 supported metadata networks (5 testnets, 11 mainnets); degenchain excluded. This is read-only evidence, not a deployment/change log. Repository source is the `feature/truffle-removal` worktree based on PR #2257 head `7d26f130`.

## Method and reproduction

All state reads used `https://<network-name>.rpc.x.superfluid.dev`, exactly the metadata network name, with the single block below supplied to **every** call, code read and storage read. Chain IDs were independently read and matched metadata on all 16 networks. Block headers were also recorded to identify the snapshots. Network links in every table point to the input metadata; a table's getter legend is the RPC source for **every cell** in that table at that network's observation block.

Discovery-only toolchain exception authorized by the coordinator: Nix is unavailable on this host (`nix: command not found`, no `/nix`); used `cast 1.8.3`, commit `cae51ad458f6abb64852b7709eb784352429825d`, dist build dated 2026-09-15. No forge/solc build, signing, transaction, broadcast or proposal submission was performed. Maintained build/test work must still use the repository's pinned Nix shell.

```bash
# Run from repository root. Substitute NETWORK and its B from the table below.
NETWORK=eth-sepolia
B=12106192
RPC="https://${NETWORK}.rpc.x.superfluid.dev"
CAST=cast # discovery used /home/dev1/.foundry/bin/cast
ZERO=0x0000000000000000000000000000000000000000
ROLE0=0x0000000000000000000000000000000000000000000000000000000000000000
SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
$CAST chain-id --rpc-url "$RPC"
$CAST block "$B" --rpc-url "$RPC" --json
# c ADDRESS 'getter(inputs)(outputs)' [ARG ...] is the exact call pattern below.
c() { "$CAST" call "$1" "$2" "${@:3}" --rpc-url "$RPC" --block "$B" --json; }
# For every metadata address (contractsV1 recursively, nativeTokenWrapper and
# trustedForwarders), and every discovered nonzero contract address in A–D:
$CAST code ADDRESS --rpc-url "$RPC" --block "$B"
# Used when governance getCodeAddress() failed:
$CAST storage GOVERNANCE "$SLOT" --rpc-url "$RPC" --block "$B"
# Agreement type inputs (ConstantFlow / InstantDistribution / GeneralDistribution):
$CAST keccak 'org.superfluid-finance.agreements.ConstantFlowAgreement.v1'
c HOST 'getAgreementClass(bytes32)(address)' AGREEMENT_TYPE_HASH
# Every proxy → implementation pair:
c PROXY 'getCodeAddress()(address)'
```

`ZERO` and `ROLE0` mean the full zero address and zero bytes32 respectively. Arrow notation always means proxy/address → implementation. A zero NFT address means **not deployed through the exposed getter**, not an RPC failure. Failed/missing getters are never converted to false/zero. Future replay requires RPC historical state at these blocks: Avalanche C and BSC had already stopped serving some supplemental historical calls (see unknowns); archive retention is not implied by today's endpoint reachability.

### Observation blocks

Source: `cast chain-id --rpc-url "$RPC"`; `cast block-number --rpc-url "$RPC"` (once, to choose B); `cast block "$B" --rpc-url "$RPC" --json`.

| Network / metadata | Chain ID | Observation block | Block hash | UTC |
| --- | --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | 43113 | 60846313 | `0xf649b4f12be151ff2f83a37e41b9c8b3bb537a1b5a095fc0be3209e07a952238` | 2026-11-10 17:44:13 |
| [eth-sepolia](../../metadata/networks.json#L51) | 11155111 | 12106192 | `0xe9a230c7b70e574dd9942b2537194ca1c443cfe0bf3f0ef26428f972322e8ecc` | 2026-11-10 17:44:12 |
| [optimism-sepolia](../../metadata/networks.json#L91) | 11155420 | 51265057 | `0xd251f33cdbb96a49eccce5e9d46fcb10931d0cc087cc149b197ef5c81a57da73` | 2026-11-10 17:44:14 |
| [base-sepolia](../../metadata/networks.json#L149) | 84532 | 57053929 | `0x4d7ac6d2159dda49279a132c0b8a68cffe238ac3d1f56273b25c2b01372c9f7f` | 2026-11-10 17:44:14 |
| [arc-testnet](../../metadata/networks.json#L185) | 5042002 | 71744617 | `0x1800e973fe8c8ed21708c5ae1d29385d5da35e1bab9903de811d194a29f03d47` | 2026-11-10 17:44:14 |
| [xdai-mainnet](../../metadata/networks.json#L223) | 100 | 49210998 | `0xf92bdb48b05debb15c855743b4f7c1fe9024d68b39275d06f1c31603ec8a903e` | 2026-11-10 17:44:10 |
| [polygon-mainnet](../../metadata/networks.json#L286) | 137 | 97084799 | `0x138b6666d76c3c92ce5982527399132bfd09d0738bb545aded5a3c25a5ace99d` | 2026-11-10 17:44:15 |
| [optimism-mainnet](../../metadata/networks.json#L348) | 10 | 159366938 | `0x92e7a54321bed8c88fbd04492566b19363e6d0128fa23c0eaa2e1c8314aa01df` | 2026-11-10 17:44:13 |
| [arbitrum-one](../../metadata/networks.json#L411) | 42161 | 523048301 | `0x64abf3735501b3ebe30b02b72f8ffe5e347aabd2b45c23ade44b082b56d022fd` | 2026-11-10 17:44:14 |
| [avalanche-c](../../metadata/networks.json#L473) | 43114 | 99956603 | `0x92566ff7d30a56cd31a70c83392f294e56726dc49e14dca4ea4579fac51ee203` | 2026-11-10 17:44:12 |
| [bsc-mainnet](../../metadata/networks.json#L535) | 56 | 132818450 | `0x5dd8d399776d65a22552291ccbd61a8951c55f67266b6bf088a337946695fd41` | 2026-11-10 17:44:14 |
| [eth-mainnet](../../metadata/networks.json#L597) | 1 | 26386086 | `0xe92f88e32054213d64c2c2425287cefc6c770b4962c97b4ed0ae2ece6b265b80` | 2026-11-10 17:44:11 |
| [celo-mainnet](../../metadata/networks.json#L658) | 42220 | 82431901 | `0xd9f2c15d016ad6c29f31780bdbeda90d7c3daf1b70bc5773ec9a8f3048f3d37f` | 2026-11-10 17:44:19 |
| [base-mainnet](../../metadata/networks.json#L698) | 8453 | 55711395 | `0xbf61574473f13956bd43f41772b881134c048b9bd2e6f67e718200892388aac8` | 2026-11-10 17:44:14 |
| [scroll-mainnet](../../metadata/networks.json#L758) | 534352 | 35675492 | `0x5f6d5d139b25828d85c194d43f38e17c4c1266d18b8566a33db4310125ccd30b` | 2026-11-10 17:43:47 |
| [arc-mainnet](../../metadata/networks.json#L797) | 5042 | 30556544 | `0x97a3bce367ca48cadc2c33e6322e8b777cd9e400c219d2b1025cbe9be9cb3134` | 2026-11-10 17:44:14 |

## Table A — core configuration

RPC getters on host: `getCodeAddress()(address)`, `NON_UPGRADABLE_DEPLOYMENT()(bool)`, `APP_WHITE_LISTING_ENABLED()(bool)`, `CALLBACK_GAS_LIMIT()(uint64)`, `getGovernance()(address)`. Governance owner: `owner()(address)`. Owner classification uses `cast code OWNER` (EOA = zero bytes), or `VERSION()(string)`, `getOwners()(address[])`, `getThreshold()(uint256)` (Safe); see B for thresholds and signers. Host immutables are defined in [Superfluid.sol:53–66](../contracts/superfluid/Superfluid.sol#L53), constructor [111–124](../contracts/superfluid/Superfluid.sol#L111).

| Network | Host → implementation | NON_UPGRADABLE | Whitelisting | Callback gas | Governance | Owner type |
| --- | --- | --- | --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | `0x85Fe79b998509B77BF10A8BD4001D58475D29386` → `0x4408C35532306d7131AC203C194C6fF9Ab5A4967` | false | false | 7500000 | `0xb4DBbceC2b6ba2e0d9186e032e6d7747CCE46019` | EOA (0 code bytes) |
| [eth-sepolia](../../metadata/networks.json#L51) | `0x109412E3C84f0539b43d39dB691B08c90f58dC7c` → `0xabB75d7c0052059993a4dDdCa26aFF0BeCFf6eEB` | false | false | 12000000 | `0xC6ec04c7b2f09E66aa50Ad9127dF6E0dC4B15DD3` | EOA (0 code bytes) |
| [optimism-sepolia](../../metadata/networks.json#L91) | `0xd399e2Fb5f4cf3722a11F65b88FAB6B2B8621005` → `0x2Aa175eFEC5192E506a25A93B69D68E49C5d3477` | false | false | 12000000 | `0xcd6870a8D963626bF55fD0327F9D8F5ef275cd86` | EOA (0 code bytes) |
| [base-sepolia](../../metadata/networks.json#L149) | `0x109412E3C84f0539b43d39dB691B08c90f58dC7c` → `0x2D7E9b5eAdd88662Cf97665e79d6b3B6D8E5EC42` | false | false | 12000000 | `0x7370970504E0bc013b9fa1d9cA0a3409Dcdb0208` | EOA (0 code bytes) |
| [arc-testnet](../../metadata/networks.json#L185) | `0xd0DE1486F69495D49c02D8f541B7dADf9Cf5CD91` → `0x60f89041bf199A112980ad221971fc47c5D7BE1E` | false | false | 12000000 | `0x385439D9063cAD130E4786FEAB5A17eD79E648D5` | EOA (0 code bytes) |
| [xdai-mainnet](../../metadata/networks.json#L223) | `0x2dFe937cD98Ab92e59cF3139138f18c823a4efE7` → `0x5406FadCFBE525e9c81fF83ec35B11022A9a86B1` | false | true | 8500000 | `0xaCc7380323681fdb8a0B9F2FE7d69dDFf0664478` | Safe 1.3.0 2-of-4 |
| [polygon-mainnet](../../metadata/networks.json#L286) | `0x3E14dC1b13c488a8d5D310918780c983bD5982E7` → `0xEC988018D913f78Fe9B96Dd94FDc7f62FBeCF009` | false | true | 12000000 | `0x3AD3f7A0965Ce6f9358AD5CCE86Bc2b05F1EE087` | Safe 1.3.0 2-of-4 |
| [optimism-mainnet](../../metadata/networks.json#L348) | `0x567c4B141ED61923967cA25Ef4906C8781069a10` → `0x092462ef87bDd081a6346102B0Be134ff63da01B` | false | true | 12000000 | `0x0170FFCC75d178d426EBad5b1a31451d00Ddbd0D` | Safe 1.3.0 2-of-4 |
| [arbitrum-one](../../metadata/networks.json#L411) | `0xCf8Acb4eF033efF16E8080aed4c7D5B9285D2192` → `0x83fD14e2384E7b2F1BAe7Abacfacf66E33dd82d8` | false | true | 12000000 | `0x0170FFCC75d178d426EBad5b1a31451d00Ddbd0D` | Safe 1.3.0 2-of-4 |
| [avalanche-c](../../metadata/networks.json#L473) | `0x60377C7016E4cdB03C87EF474896C11cB560752C` → `0xE0C565d4831f4031CdD7feF7bF79AE01e41C74E6` | false | true | 7500000 | `0xF74390BabA510ec2fE196c2e02B037380d7a6F12` | Safe 1.3.0 2-of-4 |
| [bsc-mainnet](../../metadata/networks.json#L535) | `0xd1e2cFb6441680002Eb7A44223160aB9B67d7E6E` → `0x61CDA9595c618993C68E968FD2bdcc48a171d670` | false | true | 12000000 | `0xee07D9fce4Cf2a891BC979E9d365929506C2982f` | Safe 1.3.0 2-of-4 |
| [eth-mainnet](../../metadata/networks.json#L597) | `0x4E583d9390082B65Bef884b629DFA426114CED6d` → `0x85Fe79b998509B77BF10A8BD4001D58475D29386` | false | true | 3000000 | `0xe2E14e2C4518cB06c32Cd0818B4C01f53E1Ba653` | Safe 1.3.0 2-of-4 |
| [celo-mainnet](../../metadata/networks.json#L658) | `0xA4Ff07cF81C02CFD356184879D953970cA957585` → `0xE49c89f4324E48F39b5376d69ca7f862c6710138` | false | true | 12000000 | `0x0170FFCC75d178d426EBad5b1a31451d00Ddbd0D` | Safe 1.3.0 2-of-4 |
| [base-mainnet](../../metadata/networks.json#L698) | `0x4C073B3baB6d8826b8C5b229f3cfdC1eC6E47E74` → `0x2Dc25E221D493526Bf6A6FcE3076bA2C72b47678` | false | true | 12000000 | `0x55F7758dd99d5e185f4CC08d4Ad95B71f598264D` | Safe 1.3.0 2-of-4 |
| [scroll-mainnet](../../metadata/networks.json#L758) | `0x0F86a21F6216c061B222c224e315d9FC34520bb7` → `0x7D725842d9Bd0c63b3566d55e3833624A8BD1F90` | false | true | 3000000 | `0xC2C9a709A6744816b3712D520BD314fe610AEa33` | Safe 1.3.0 2-of-4 |
| [arc-mainnet](../../metadata/networks.json#L797) | `0x43Cd22BA2aDEd92BAa390506b8F1f15BF4651A7f` → `0x9196BbBB41554b81b3ebcC227d628655A21a2380` | false | false | 12000000 | `0xC2C9a709A6744816b3712D520BD314fe610AEa33` | Safe 1.3.0 2-of-3 |

All 16 hosts also return `MAX_APP_CALLBACK_LEVEL()(uint256) = 1`, `MAX_NUM_AGREEMENTS()(uint32) = 256`, `versionRecipient()(string) = "v1"`; these are constants, not chain-specific constructor settings ([Superfluid.sol:76–80](../contracts/superfluid/Superfluid.sol#L76), [982–987](../contracts/superfluid/Superfluid.sol#L982)). Factory and remaining host immutables are in D.

## Table B — governance owners and resolver admins

RPC sources: governance `getCodeAddress()(address)` and `owner()(address)`; resolver `DEFAULT_ADMIN_ROLE()(bytes32)`, `getRoleMemberCount(bytes32)(uint256) ROLE0`, `getRoleMember(bytes32,uint256)(address) ROLE0 0`, `get(string)(address) Superfluid.v1`. All 16 resolvers return **ROLE0**, **one** member, and `Superfluid.v1 == metadata host`. No RoleGranted log reconstruction was needed: every resolver was enumerable. The actual authority is **DEFAULT_ADMIN_ROLE**, not a separate ADMIN_ROLE ([Resolver.sol:18–28](../contracts/utils/Resolver.sol#L18)). Without `RESOLVER_ADDRESS`, getConfig uses this same metadata resolver; an operator override is not an onchain value ([getConfig.js:97](deployment-tooling.md)).

Testnet governance: `getCodeAddress()` failed and the EIP-1967 slot was zero on all five. Therefore no UUPS/EIP-1967 implementation was found; **inferred** direct TestGovernance is consistent with [TestGovernance.sol:18–24](../contracts/utils/TestGovernance.sol#L18), not proof against every imaginable custom proxy. Mainnet governance returns the nonzero UUPS implementation below ([UUPSProxiable.sol:15–18](../contracts/upgradability/UUPSProxiable.sol#L15)).

| Network | Governance implementation | Governance owner / route | Resolver | Sole resolver admin / route | Admin == gov owner? |
| --- | --- | --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | no UUPS impl; EIP-1967=0 | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | `0xf0ec6A8842Ca72Aec8A4D4573E731242389e18A8` | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | yes |
| [eth-sepolia](../../metadata/networks.json#L51) | no UUPS impl; EIP-1967=0 | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | `0x6813edE4E78ecb830d380d0F7F684c12aAc95F02` | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | yes |
| [optimism-sepolia](../../metadata/networks.json#L91) | no UUPS impl; EIP-1967=0 | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | `0x554c06487bEc8c890A0345eb05a5292C1b1017Bd` | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | yes |
| [base-sepolia](../../metadata/networks.json#L149) | no UUPS impl; EIP-1967=0 | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | `0x21d4E9fbB9DB742E6ef4f29d189a7C18B0b59136` | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | yes |
| [arc-testnet](../../metadata/networks.json#L185) | no UUPS impl; EIP-1967=0 | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | `0x777Be25F9fdcA87e8a0E06Ad4be93d65429FCb9f` | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | yes |
| [xdai-mainnet](../../metadata/networks.json#L223) | `0x818fbe37EcFee8b981dD1a2Bb2C292EEBE0AB21E` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0x9634Fa35188C59DD3B0ADa0Dd9adD7e4ECefc0a9` | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | **no** |
| [polygon-mainnet](../../metadata/networks.json#L286) | `0x491B808fbc0d8972BD5C88a533dA9Cab98447382` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0x8bDCb5613153f41B2856F71Bd7A7e0432F6dbe58` | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`; direct EOA | **no** |
| [optimism-mainnet](../../metadata/networks.json#L348) | `0x2E4861B1f56A67473B7BF0dd1eF85E9e9fA5aD75` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0x743B5f46BC86caF41bE4956d9275721E0531B186` | `0x9cC7fc484fF588926149577e9330fA5b2cA74336`; W2 (legacy multisig 1-of-6) | **no** |
| [arbitrum-one](../../metadata/networks.json#L411) | `0x2E4861B1f56A67473B7BF0dd1eF85E9e9fA5aD75` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0x609b9d9d6Ee9C3200745A79B9d3398DBd63d509F` | `0x9cC7fc484fF588926149577e9330fA5b2cA74336`; W2 (legacy multisig 1-of-6) | **no** |
| [avalanche-c](../../metadata/networks.json#L473) | `0x6345Aa6cec42a85160CF436810F97661e28c1876` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0x24a3F04F70B7f07B9673EadD3e146391BcfEa5c1` | `0xee07D9fce4Cf2a891BC979E9d365929506C2982f`; W3 (legacy multisig 1-of-5) | **no** |
| [bsc-mainnet](../../metadata/networks.json#L535) | `0x9A65E8d1115d246130BAD2f1162ca69C5fEE7b3d` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0x69604aA4e9e8BF44A73C680997205Edb03A92E41` | `0xFC63B7C762B10670Eda15cF3ca3970bCDB28C9eF`; W4 (legacy multisig 1-of-6) | **no** |
| [eth-mainnet](../../metadata/networks.json#L597) | `0x835e58065fb76cD51e6fDd156A7C2240194Dc27c` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0xeE4cD028f5fdaAdeA99f8fc38e8bA8A57c90Be53` | `0xae09720B8E27CfC171d07baEb1b6eF97030C3D52`; W5 (legacy multisig 1-of-4) | **no** |
| [celo-mainnet](../../metadata/networks.json#L658) | `0xaDcF0AC9F2aa04a79fc64A1fDf0a0c9f3aE0556A` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0x05eE721BD4D803d6d477Aa7607395452B65373FF` | `0xEe1bd2C743BF40B1206B090Fa9aB27A0C57d7B90`; W6 (legacy multisig 1-of-4) | **no** |
| [base-mainnet](../../metadata/networks.json#L698) | `0x4E89088Cd14064f38E5B2F309cFaB9C864F9a8e6` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0x6a214c324553F96F04eFBDd66908685525Da0E0d` | `0x8B5a2CF69a56d7F8Fa027edcA23594cdDF544dDc`; W7 (legacy multisig 1-of-4) | **no** |
| [scroll-mainnet](../../metadata/networks.json#L758) | `0xb9349347fcC0318137e6143A01c6582C072Fb581` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W1 (Safe 2-of-4) | `0xb25a19c0e7d10c8D37E5b63Ed3213b67f7ebfF80` | `0xFCD84210f5d51Cd40a30443d44d6A5500d5D10dF`; W8 (legacy multisig 1-of-3) | **no** |
| [arc-mainnet](../../metadata/networks.json#L797) | `0xb9349347fcC0318137e6143A01c6582C072Fb581` | `0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6`; W9 (Safe 2-of-3) | `0xFD4b701C75a52E9744E5a0f2905AC9765a8b678D` | `0x889ebeCaD5F8C34Fd96023456d0fC5cE54eb74Cb`; W8 (legacy multisig 1-of-3) | **no** |

Wallet sets below preserve `getOwners()` order. For each row in B, call these getters on that row's owner/admin at that row's B: Safe `VERSION()(string)`, `getOwners()(address[])`, `getThreshold()(uint256)`; legacy `getOwners()(address[])`, `required()(uint256)` (Safe getters failed, except see archival caveat for Avalanche C/BSC). Identical addresses on different chains are still queried independently.

| Wallet set | Detected type | Authority | Owners |
| --- | --- | --- | --- |
| W1 | Safe 1.3.0 | 2-of-4 | `0x4289a2b29be2555b0973422167321bF42CC39A3B`, `0x2770cC972a7666C974B1b1269F4F31b97f99f898`, `0x9c4033F637cbc6170349B079C2114c599de30dDE`, `0x069C4343EF842Df2A3b7a77486A5DeceaB528295` |
| W2 | legacy Gnosis MultiSigWallet | 1-of-6 | `0xCcA090FD60d405a10b786559933daEEc4e2053Af`, `0x5eb449B88Ff8f03cD0C736A72ac70B76258E4B10`, `0x568658Dd13A880fF8418Efe194004019A675955F`, `0x2b61101447829abC7a92Ce34A366A582FE0d5096`, `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`, `0x6B663333d080FEC34038A9ed1d50300AA103C83A` |
| W3 | legacy Gnosis MultiSigWallet | 1-of-5 | `0xCcA090FD60d405a10b786559933daEEc4e2053Af`, `0x568658Dd13A880fF8418Efe194004019A675955F`, `0x5eb449B88Ff8f03cD0C736A72ac70B76258E4B10`, `0x2b61101447829abC7a92Ce34A366A582FE0d5096`, `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015` |
| W4 | legacy Gnosis MultiSigWallet | 1-of-6 | `0xCcA090FD60d405a10b786559933daEEc4e2053Af`, `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`, `0x5eb449B88Ff8f03cD0C736A72ac70B76258E4B10`, `0x568658Dd13A880fF8418Efe194004019A675955F`, `0x2b61101447829abC7a92Ce34A366A582FE0d5096`, `0x63333d080fEC34038a9Ed1D50300AA103c83aAdd` |
| W5 | legacy Gnosis MultiSigWallet | 1-of-4 | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`, `0x568658Dd13A880fF8418Efe194004019A675955F`, `0x5eb449B88Ff8f03cD0C736A72ac70B76258E4B10`, `0xd1Ad5b3090dEA1026C7CB2Ffa3A6c3565526E5ED` |
| W6 | legacy Gnosis MultiSigWallet | 1-of-4 | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`, `0x2b61101447829abC7a92Ce34A366A582FE0d5096`, `0xFC63B7C762B10670Eda15cF3ca3970bCDB28C9eF`, `0xBA0705bc9E4754B03c0c6293567D0afA25ef8bB6` |
| W7 | legacy Gnosis MultiSigWallet | 1-of-4 | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`, `0xd1Ad5b3090dEA1026C7CB2Ffa3A6c3565526E5ED`, `0x568658Dd13A880fF8418Efe194004019A675955F`, `0x5eb449B88Ff8f03cD0C736A72ac70B76258E4B10` |
| W8 | legacy Gnosis MultiSigWallet | 1-of-3 | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015`, `0x568658Dd13A880fF8418Efe194004019A675955F`, `0x2b61101447829abC7a92Ce34A366A582FE0d5096` |
| W9 | Safe 1.3.0 | 2-of-3 | `0xE400820f3D60d77a3EC8018d44366ed0d334f93C`, `0x9c4033F637cbc6170349B079C2114c599de30dDE`, `0x069C4343EF842Df2A3b7a77486A5DeceaB528295` |

### B.1 — governance defaults (not token-specific overrides)

RPC sources on governance, always with metadata host and `ZERO` token: `getRewardAddress(address,address)(address) HOST ZERO`, `getPPPConfig(address,address)(uint256,uint256) HOST ZERO`, `getSuperTokenMinimumDeposit(address,address)(uint256) HOST ZERO`. App key samples use `verifyAppRegistrationKey(address,address,string)(bool,uint256) HOST OWNER_OR_RESOLVER_ADMIN k1`; the table reports `validNow / expirationTs` for both sampled addresses, not a claim that all registration keys are absent. Getter semantics: [SuperfluidGovernanceBase.sol:274](../contracts/gov/SuperfluidGovernanceBase.sol#L274), [327](../contracts/gov/SuperfluidGovernanceBase.sol#L327), [384](../contracts/gov/SuperfluidGovernanceBase.sol#L384), [472](../contracts/gov/SuperfluidGovernanceBase.sol#L472).

| Network | Reward address | Liquidation / patrician (seconds) | Minimum deposit | k1: gov owner; resolver admin |
| --- | --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015` | 3600 / 720 | 0 | false, 0; false, 0 |
| [eth-sepolia](../../metadata/networks.json#L51) | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015` | 3600 / 720 | 0 | false, 0; false, 0 |
| [optimism-sepolia](../../metadata/networks.json#L91) | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015` | 3600 / 720 | 0 | false, 0; false, 0 |
| [base-sepolia](../../metadata/networks.json#L149) | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015` | 3600 / 720 | 0 | false, 0; false, 0 |
| [arc-testnet](../../metadata/networks.json#L185) | `0xd15D5d0f5b1b56A4daEF75CfE108Cb825E97d015` | 3600 / 720 | 0 | false, 0; false, 0 |
| [xdai-mainnet](../../metadata/networks.json#L223) | `0x177Ab68dc7B0032Fce7d64d5BD28a5983bD42B3B` | 14400 / 1800 | 0 | false, 0; false, 0 |
| [polygon-mainnet](../../metadata/networks.json#L286) | `0xeF3cB64Ab9021E400f4331929d8d02A47b333Af1` | 14400 / 1800 | 0 | false, 0; false, 0 |
| [optimism-mainnet](../../metadata/networks.json#L348) | `0x91b577553B5390d47A1984eE500663EE7671DcE6` | 14400 / 1800 | 0 | false, 0; false, 0 |
| [arbitrum-one](../../metadata/networks.json#L411) | `0xD09302C533Ca020E02FF4F70BBa606e3C2b3F4a6` | 14400 / 1800 | 0 | false, 0; false, 0 |
| [avalanche-c](../../metadata/networks.json#L473) | `0xD226e7C591F6aE719079b8A31654221d980DB5ce` | 14400 / 1800 | 0 | unknown; unknown |
| [bsc-mainnet](../../metadata/networks.json#L535) | `0xAb6e2f343C1909258580e4E6A149E24CbB3D2AEd` | 14400 / 1800 | 0 | unknown; unknown |
| [eth-mainnet](../../metadata/networks.json#L597) | `0x8B5a2CF69a56d7F8Fa027edcA23594cdDF544dDc` | 14400 / 1800 | 0 | false, 0; false, 0 |
| [celo-mainnet](../../metadata/networks.json#L658) | `0x9bCa3a623e7b2e248510d88B2894F54898d88F91` | 14400 / 1800 | 0 | false, 0; false, 0 |
| [base-mainnet](../../metadata/networks.json#L698) | `0xA87F76e99f6C8Ff8996d14f550ceF47f193D9A09` | 14400 / 1800 | 0 | false, 0; false, 0 |
| [scroll-mainnet](../../metadata/networks.json#L758) | `0x1bF9D75d50fD828a93f69ECB06f2B85767792CEB` | 14400 / 1800 | 0 | false, 0; false, 0 |
| [arc-mainnet](../../metadata/networks.json#L797) | `0x1bF9D75d50fD828a93f69ECB06f2B85767792CEB` | 14400 / 1800 | 0 | false, 0; false, 0 |

## Table C — registered agreements and IDA policy

RPC source: on host, `getAgreementClass(bytes32)(address)` using `cast keccak` of `org.superfluid-finance.agreements.ConstantFlowAgreement.v1`, `org.superfluid-finance.agreements.InstantDistributionAgreement.v1`, `org.superfluid-finance.agreements.GeneralDistributionAgreement.v1`; on each returned proxy, `getCodeAddress()(address)`. These registered proxies match metadata CFA/IDA/GDA on all 16 networks. IDA getters on the registered proxy: `NEW_ACTIVITY_FROZEN()(bool)`, `MAX_NUM_SUBSCRIPTIONS()(uint32)`, `SLOTS_BITMAP_LIBRARY_ADDRESS()(address)`.

Freeze and cap are **separate immutables**, not inferred from the linked bitmap library: [InstantDistributionAgreementV1.sol:73–105](../contracts/agreements/InstantDistributionAgreementV1.sol#L73). Frozen networks reject new activity but keep unwind operations; existing bitmap entries above a reduced cap remain visible ([source:23–24](../contracts/agreements/InstantDistributionAgreementV1.sol#L23), [79–82](../contracts/agreements/InstantDistributionAgreementV1.sol#L79)). Legacy deploy enforces **no re-enabling** of a previously frozen network ([deploy-framework.js:89–131](deployment-tooling.md)).

| Network | CFA proxy → impl | IDA proxy → impl | GDA proxy → impl | IDA frozen | IDA max subscriptions | IDA bitmap library |
| --- | --- | --- | --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | `0x16843ac25Ccc58Aa7960ba05f61cBB17b36b130A` → `0xAfDa1Ae757219229fD7c9A0db85A4dd064791499` | `0xA44dEC7A0Dde1a56AeDe4143C1ef89cf5d956782` → `0x751FCAd138980eD006b9e90C4a645577dc03F327` | `0x51f571D934C59185f13d17301a36c07A2268B814` → `0x681b8480beAAf7BD4c2D23f71e9C2431dba68b02` | true | 256 | `0xC9422E9607218f7dFE80C5fA5Bd083A207B2808D` |
| [eth-sepolia](../../metadata/networks.json#L51) | `0x6836F23d6171D74Ef62FcF776655aBcD2bcd62Ef` → `0x0F7c741fA8014538B3b7925aA82284101BdB0370` | `0x9358C7dCCc6B8CA6F526311e8ac266F8C861B7ea` → `0xB157dAE213B499883F931088021De2702022afA4` | `0x9823364056BcA85Dc3c4a3b96801314D082C8Eb9` → `0x1511CA5D41abebB96828e20Ab96037f479Ac7034` | true | 256 | `0xC6082f0B0040809217f96C0aB946a556263042A0` |
| [optimism-sepolia](../../metadata/networks.json#L91) | `0x8a3170AdbC67233196371226141736E4151e7C26` → `0x803215C9BcEDFF702B5506B7805bc96fBE2410bF` | `0x51BDA2C5F627d456E282257710F4A4b6Eb094A52` → `0x172488835a194B56f32EA9F7625E2fAE02a9914c` | `0xd453d38A001B47271488886532f1CCeAbf0c7eF3` → `0xd8d640B64D9B319632919Eb9f22a581A64bFfB36` | false | 32 | `0x817514976F2E4436d4bA19C14F1d202b2080358F` |
| [base-sepolia](../../metadata/networks.json#L149) | `0x6836F23d6171D74Ef62FcF776655aBcD2bcd62Ef` → `0xcDD547Fd289883723d6B7534EcdB6B211477583D` | `0x9358C7dCCc6B8CA6F526311e8ac266F8C861B7ea` → `0xC6ec04c7b2f09E66aa50Ad9127dF6E0dC4B15DD3` | `0x53F4f44C813Dc380182d0b2b67fe5832A12B97f8` → `0x913dFb55Cd3F06A54BE58e7bd3Eac561F9206559` | true | 256 | `0x3c7fBf36758062aD1669CFf66e4e408397A17d7D` |
| [arc-testnet](../../metadata/networks.json#L185) | `0xa38Eb8Cd48178EbeaEe98aB2d2019969d3eC6CBF` → `0x8405c5Bb7292F5E181D0870DDCB4a51eFaf7E074` | `0x73a4A5B5CBa803D90f9cEE00F60523d48ddd53e2` → `0xEBbe9a6688be25d058C9469Ee4807E5eF192897f` | `0xC5428C0377A17d2Ec35f55B87632e5bb49dBA51A` → `0x07E4A282F8f20032F3e766fFFB73c8b86bA7e1f1` | true | 256 | `0x35aED9E37FC7b8030D4B643139Bfe63F15D12ead` |
| [xdai-mainnet](../../metadata/networks.json#L223) | `0xEbdA4ceF883A7B12c4E669Ebc58927FBa8447C7D` → `0xc2Ac51330c34363c34Bb284A0eca313594215491` | `0x7888ac96F987Eb10E291F34851ae0266eF912081` → `0x6282Fb9478de51395A1B74Ab452958a27EE1D6aa` | `0xd7992D358A20478c82dDEd98B3D8A9da46e99b82` → `0xBF35AA05681269a8E245Df66bb274145aAe1649B` | true | 256 | `0x099A32459841D2de0a28B861dBc30BfF20D16bb5` |
| [polygon-mainnet](../../metadata/networks.json#L286) | `0x6EeE6060f715257b970700bc2656De21dEdF074C` → `0x638b47790aF450bBF18400c027E9b41182f72FD9` | `0xB0aABBA4B2783A72C52956CDEF62d438ecA2d7a1` → `0xDAf7F83b142895eAeaBA64449A5dcef43C89bF6b` | `0x961dd5A052741B49B6CBf6759591f9D8576fCFb0` → `0x2476Bf660e0351992E1485ac18351eFacD09B6Df` | true | 256 | `0xcF5674dd984102DD15c9bb035B4F75df600c1857` |
| [optimism-mainnet](../../metadata/networks.json#L348) | `0x204C6f131bb7F258b2Ea1593f5309911d8E458eD` → `0x8c0C879133E2ffB8D8Ccf925D04B5139f784257A` | `0xc4ce5118C3B20950ee288f086cb7FC166d222D4c` → `0x0E1D40B9af3DEd67B78579fEdb486A8511C1af9F` | `0x68Ae17fa7a31b86F306c383277552fd4813b0d35` → `0x53d00397f03147A9bD9c40443A105A82780deAF1` | false | 32 | `0x2Dc25E221D493526Bf6A6FcE3076bA2C72b47678` |
| [arbitrum-one](../../metadata/networks.json#L411) | `0x731FdBB12944973B500518aea61942381d7e240D` → `0x658B882d41db5114587C4B1B46FDD43b2b87Dba6` | `0x2319C7e07EB063340D2a0E36709B0D65fda75986` → `0x602BCc6688324E31B0ffc6999448f04bE7201c2E` | `0x1e299701792a2aF01408B122419d65Fd2dF0Ba02` → `0xdCf916CF9d2a8184c3d8F62eFE5CFBD5Eb3Fcbe8` | true | 256 | `0xA97ab27b3ab6eED3B4699ad8a6378d6b7EC18042` |
| [avalanche-c](../../metadata/networks.json#L473) | `0x6946c5B38Ffea373b0a2340b4AEf0De8F6782e58` → `0xf7bA9A0c80d5136005A1Ec13010F4df8D611E715` | `0x1fA9fFe8Db73F701454B195151Db4Abb18423cf2` → `0xA97ab27b3ab6eED3B4699ad8a6378d6b7EC18042` | `0xA7b197cD5b0cEF6d62c4A0a851E3581f5E62e4D2` → `0x816509ECcCbFD2D00D3b9949f1077A3f2095f957` | true | 256 | `0x57897b796ece6633fc7C0c6490B4eb84D58509E5` |
| [bsc-mainnet](../../metadata/networks.json#L535) | `0x49c38108870e74Cb9420C0991a85D3edd6363F75` → `0x2C3ceBc644F9130B511C59e29Ce982618C71309B` | `0x594ed9Cd773584B645aC1F5B11020d3b32cDF07d` → `0x08e56c90A363363cE9eD30edBdC40FBd34Fd5499` | `0x3bbFA4C406719424C7f66CD97A8Fe27Af383d3e2` → `0x5D9c5144e6Ad5A7c86E7a67067827F78496009C6` | true | 256 | `0xB0adC0d2F68901640cF444632213ebC02EB19A32` |
| [eth-mainnet](../../metadata/networks.json#L597) | `0x2844c1BBdA121E9E43105630b9C8310e5c72744b` → `0xc3069bDE869912E3d9B965F35D7764Fc92BccE67` | `0xbCF9cfA8Da20B591790dF27DE65C1254Bf91563d` → `0x9D63E77E8f0e6397722da58aAb34cee2709b0FD3` | `0xAAdBB3Eee3Bd080f5353d86DdF1916aCA3fAC842` → `0x73Ca5F121dfA9d0ec36e9Ed7CE66feD187Ec312B` | true | 256 | `0xF26967f92151487f8c6642199c3441B02398D19E` |
| [celo-mainnet](../../metadata/networks.json#L658) | `0x9d369e78e1a682cE0F8d9aD849BeA4FE1c3bD3Ad` → `0x3284A030ACb314eC28bD7Ff6e47AD2Ab7ee9Ba77` | `0x26747Fe93fAC8bF28E1e24A558a2bC7E4d9846cA` → `0xdCf916CF9d2a8184c3d8F62eFE5CFBD5Eb3Fcbe8` | `0x308b7405272d11494716e30C6E972DbF6fb89555` → `0x4D11B0b59948d81EEAaF667CCDaA212f824949d4` | true | 256 | `0x1c971E8863c63E1F1BdaF7dBF4831EcA197C9508` |
| [base-mainnet](../../metadata/networks.json#L698) | `0x19ba78B9cDB05A877718841c574325fdB53601bb` → `0xc8bDd45A2b6A88303243F92b696E9BD6A9E93aA0` | `0x66DF3f8e14CF870361378d8F61356D15d9F425C4` → `0xE0eD76bB8bF1C2940C5885179B9046B56BbB11F1` | `0xfE6c87BE05feDB2059d2EC41bA0A09826C9FD7aa` → `0x7db964af7F1c5D5c27023B80a40C19454053Ff70` | true | 256 | `0x959653df67F6385eff01e38DE6b9e493C09Cd384` |
| [scroll-mainnet](../../metadata/networks.json#L758) | `0xB3bcD6da1eeB6c97258B3806A853A6dcD3B6C00c` → `0x7B836cB9A1B0EF8AadC18b74270E04F78a790399` | `0x4112557F0F228A18654d3C39599421DE9F61144d` → `0x1748479504a92d69dEb5f5ADd61a17b563d82C15` | `0x97a9f293d7eD13f3fbD499cE684Ed4F103295a28` → `0x492f66Bc88f8b882E4A6da21F49Bb344A71948aE` | true | 256 | `0x1BD3b6522102F9ea406807f8ecaeB2D96278a83f` |
| [arc-mainnet](../../metadata/networks.json#L797) | `0xFb60b139CD14262eC4FEe466B388Bb7f5A06Bf75` → `0x745877d39E02dFD242A0d44E1f7b2042122e02F9` | `0xBDa1B20e5deef07AA19C2Af5c8a3430642b2C366` → `0x788611085A65143A838A4BF3De726e130669E0Ea` | `0xE32790AC5e6aAA8416364551b5E1E6736c64e50D` → `0x27e8B0F481B4244f74668dd065be1E566C43B886` | true | 256 | `0x0E34Ac65ab770542afaa687c78c19A52Ad511A4E` |

## Table D — host dependencies, factory, NFTs, beacon and forwarders

### D.1 — remaining host constructor dependencies

RPC sources on host: `SIMPLE_FORWARDER()(address)`, `getERC2771Forwarder()(address)`, `getSimpleACL()(address)`. These three addresses complete the constructor immutable inventory from A. `isTrustedForwarder(address)(bool)` is a **governance-config** lookup, not an enumeration of those immutable dependencies ([Superfluid.sol:970–994](../contracts/superfluid/Superfluid.sol#L970)); do not conflate ERC-2771 batching infrastructure with the governance trust list.

| Network | SimpleForwarder | ERC2771Forwarder | SimpleACL |
| --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | `0xD5618B06E91A0593F60Df455281a8c9361e05014` | `0x3c09baE22CbbBe917C149b0D3264098f01704574` | `0x956AdEb34E637109EEc0bc6c4947D29EA8FbaE34` |
| [eth-sepolia](../../metadata/networks.json#L51) | `0x5547885781991278Ec7244cd356FE40B377cEe07` | `0xD776dFAdf94b8E51B527A4305A2540e4f1527478` | `0x4bfF86E83F4400DBf1f8cAEA1f955f959E605Ef1` |
| [optimism-sepolia](../../metadata/networks.json#L91) | `0x5943F705aBb6834Cad767e6E4bB258Bc48D9C947` | `0x4F267e58c6Fe3d9Ff45928f923e95BCAA323c279` | `0x87574bf2CD718A4521127cFCb4bCcbC6C095babf` |
| [base-sepolia](../../metadata/networks.json#L149) | `0xe346A6CDCe83ddA3f29C328B5BA3C2d26e32Db90` | `0x1AC2d0eC256F6Cfb24Fae29eF14B3a494EB75c2A` | `0x80f053d8Fe83819590A4715e968B21738d66Ba1D` |
| [arc-testnet](../../metadata/networks.json#L185) | `0x1eECE78F76843001039f5f4de41D68Ec9a80a1f7` | `0xb441a89acce1D0515d100fb6b07FD20606c8b601` | `0xbe49ac1EadAc65dccf204D4Df81d650B50122aB2` |
| [xdai-mainnet](../../metadata/networks.json#L223) | `0x497aa106Da00BFa8f8BC266EF0793131930Fa630` | `0x22bD0640d77c5D296cb43208B3956F0f3212BED4` | `0xD4F3D519b2c928e0F7182569f3E0988ee25b1549` |
| [polygon-mainnet](../../metadata/networks.json#L286) | `0x69c77B48fCDacF589B05808a4f29a520dC4f1467` | `0xc9AB8ddCD7aEA606e4a5a724fEd845788Bb7a475` | `0x88b614f8D7229c7Eed2c8B0F936cE7cAAb46A535` |
| [optimism-mainnet](../../metadata/networks.json#L348) | `0xB7A582646e83B81a9a65583762f52814f837D39F` | `0x580b3a32D679C62537dB9faC0B6C50356088abF8` | `0x3c1BCb2648C4b4c18c44F0Cc7088D09B94CbAb2e` |
| [arbitrum-one](../../metadata/networks.json#L411) | `0x7db964af7F1c5D5c27023B80a40C19454053Ff70` | `0x0742De30799351f892Dc7FaE8D76A265D6E772eA` | `0xf2C284f4CdDfe3edd0C526Dc1dBcA018C1Da31Ad` |
| [avalanche-c](../../metadata/networks.json#L473) | `0xEF8038C30925131e109F88d7A522D1D2aB6D6caa` | `0x0695462744904769db998D0cCE51e9d1b479f77A` | `0x3903df4F25d9099B15B0B868f5C9876b1013B3b6` |
| [bsc-mainnet](../../metadata/networks.json#L535) | `0x2be9D350Ad96793B8cF87d48D0a7c45e91E6b517` | `0x9539B21cC67844417E80aE168bc28c831E7Ed271` | `0x07efa4e436EE9c3a6ff1F0A3a7b4135aABB2FEcb` |
| [eth-mainnet](../../metadata/networks.json#L597) | `0x848497975f5757Aa1a48e13bbF46D330E62b19A7` | `0x7b9B7804dbcF7e6D0d0760f915617D31E54F8c6D` | `0xAeAca63A4034D287658584BB4A8bDb7A03729A18` |
| [celo-mainnet](../../metadata/networks.json#L658) | `0x17E0B9912D900982189d3D025e81D0dd57674640` | `0x658B882d41db5114587C4B1B46FDD43b2b87Dba6` | `0xF1Bc22c09f2D8C8F2aDa8874C0e6968D99EEd2Dc` |
| [base-mainnet](../../metadata/networks.json#L698) | `0x2525FACa97742f84eF259cACEdB5EC6b732ae520` | `0xC8D7A006d228Bc0d61Ed9BE6A670679E7cE044A2` | `0xA90E28d1D0eb9ff67018dBdD315eA3E7D28783e1` |
| [scroll-mainnet](../../metadata/networks.json#L758) | `0xFf208fDA150e55c8D805D7BD33d463B95778C212` | `0xb75bd19C682e62E6A0c35399bb3A2538fCC9cef6` | `0xE5E2421c5B9488C17E9e58E26A17b4f4Bb3F84A1` |
| [arc-mainnet](../../metadata/networks.json#L797) | `0x53acF296D4e1930322b8A41C39424d8AE2bc8aA5` | `0xf491893eEB19a57f48Ccce08AAca9dD622c5d08F` | `0x89932A6cc2910e3b807fEd8F82C60A6C0c8A9331` |

SimpleACL is non-enumerable AccessControl ([SimpleACL.sol:4–14](../contracts/utils/SimpleACL.sol#L4)). Supplemental cheap role samples, not a complete ACL inventory: let `R=cast keccak ACL_SUPERAPP_REGISTRATION_ROLE`, `RA=cast keccak ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN`, `P=cast keccak ACL_POOL_CONNECT_EXCLUSIVE_ROLE`, `PA=cast keccak ACL_POOL_CONNECT_EXCLUSIVE_ROLE_ADMIN`. Sources: `c ACL 'getRoleAdmin(bytes32)(bytes32)' ROLE`; `c ACL 'hasRole(bytes32,address)(bool)' ROLE ADDRESS`.

On the 14 networks serving supplemental historical calls, admin(R)=RA, admin(P)=PA, admin(RA)=admin(PA)=ROLE0. Of the three sampled addresses (governance owner, resolver admin, GDA), none holds R or P; only GDA holds PA. RA membership below; preserve ACL **address and state**, not these samples alone. Legacy upgrade explicitly forbids replacing the ACL to avoid lost state ([deploy-framework.js:936–938](deployment-tooling.md)).

| Network | RA held by governance owner? | RA held by resolver admin? | GDA holds PA? |
| --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | true | true | true |
| [eth-sepolia](../../metadata/networks.json#L51) | true | true | true |
| [optimism-sepolia](../../metadata/networks.json#L91) | true | true | true |
| [base-sepolia](../../metadata/networks.json#L149) | true | true | true |
| [arc-testnet](../../metadata/networks.json#L185) | true | true | true |
| [xdai-mainnet](../../metadata/networks.json#L223) | false | true | true |
| [polygon-mainnet](../../metadata/networks.json#L286) | false | true | true |
| [optimism-mainnet](../../metadata/networks.json#L348) | false | false | true |
| [arbitrum-one](../../metadata/networks.json#L411) | false | false | true |
| [avalanche-c](../../metadata/networks.json#L473) | unknown | unknown | unknown |
| [bsc-mainnet](../../metadata/networks.json#L535) | unknown | unknown | unknown |
| [eth-mainnet](../../metadata/networks.json#L597) | false | false | true |
| [celo-mainnet](../../metadata/networks.json#L658) | false | false | true |
| [base-mainnet](../../metadata/networks.json#L698) | false | false | true |
| [scroll-mainnet](../../metadata/networks.json#L758) | false | false | true |
| [arc-mainnet](../../metadata/networks.json#L797) | false | false | true |

### D.2 — factory, SuperToken and PoolAdmin NFT

RPC sources: host `getSuperTokenFactory()(address)`, `getSuperTokenFactoryLogic()(address)`; factory `getCodeAddress()(address)`, `getSuperTokenLogic()(address)`, `POOL_ADMIN_NFT_LOGIC()(address)`; SuperToken logic `POOL_ADMIN_NFT()(address)`; returned NFT proxy `getCodeAddress()(address)`. On every network, host factory matches metadata, host factory logic equals factory `getCodeAddress()`, and factory PoolAdmin NFT logic equals the NFT proxy's implementation. Source: [SuperTokenFactory.sol:26–34](../contracts/superfluid/SuperTokenFactory.sol#L26), [139–143](../contracts/superfluid/SuperTokenFactory.sol#L139); [Superfluid.sol:282–295](../contracts/superfluid/Superfluid.sol#L282).

| Network | Factory proxy → logic | SuperToken logic | PoolAdmin NFT proxy → logic |
| --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | `0x1C92042426B6bAAe497bEf461B6d8342D03aEc92` → `0x4ecca951f7fAeb4609CaB11D8269A8Cb891780b7` | `0x77eDdF503607921D7fb05CaBc9e652994A1df508` | `0xB746Bd803D6268D3F2494a64f874D0fD52968A8B` → `0x804f5D2FEB2034957D070a913FbF38C28f79E010` |
| [eth-sepolia](../../metadata/networks.json#L51) | `0x254C2e152E8602839D288A7bccdf3d0974597193` → `0x4E94D7DdF107451195Cf0803d68D12109AB6Afc0` | `0xcaD0F11a4BBB2331CF8bb37E17903e25e5a5C878` | `0x1BD3b6522102F9ea406807f8ecaeB2D96278a83f` → `0xD344A201F842C0d1f82EB363d664c56E241b887C` |
| [optimism-sepolia](../../metadata/networks.json#L91) | `0xfcF0489488397332579f35b0F711BE570Da0E8f5` → `0x5D8EC9309dDbC7736F5fd468fB0DEbA1eE7dc670` | `0x36446Ec9C7909608065dEB7f491701d815B880e5` | `0xaB4f083f4096a67813E5D6b05EC74282FA1C7a10` → `0xC46A8414b56287c9DdA25eC33Cf611516bee24Ab` |
| [base-sepolia](../../metadata/networks.json#L149) | `0x7447E94Dfe3d804a9f46Bf12838d467c912C8F6C` → `0xcCfe263531d91293c38807257322CDa07eE02769` | `0xA7F1E9448A1ceca74f138035ea95F7880c935e76` | `0xe64f81d5dDdA1c7172e5C6d964E8ef1BD82D8704` → `0x0D3776b4Ec843c83Edc80CD90Ace474E6E4fA24D` |
| [arc-testnet](../../metadata/networks.json#L185) | `0x8d1a3F66275F33209F3E823dE31537E4DdeE44Ce` → `0xdDc77Ec35A571c98c7465b51F152E4888835bee6` | `0xCb0Ff4D0cA186f0Fc0301258066Fe3fA258417a6` | `0x6C66e5c5D201A753ff497F2e9eC5D545631854d0` → `0xbFC8c07468aEea87A0A1d30a23804cF4fd73Eff1` |
| [xdai-mainnet](../../metadata/networks.json#L223) | `0x23410e2659380784498509698ed70E414D384880` → `0x87574bf2CD718A4521127cFCb4bCcbC6C095babf` | `0xe6C7025368ef0eEe7D2fB8172d682744664e9Cd2` | `0xA4806Df890e5212c2879628B4c3B07341F881ed5` → `0x6478393c766E342b011BFe08AD75C85fed7A689F` |
| [polygon-mainnet](../../metadata/networks.json#L286) | `0x2C90719f25B10Fc5646c82DA3240C76Fa5BcCF34` → `0xa3c80Ade7A9C75F586C0413EfBEd430cA500437b` | `0xDB5DD377C42F3f1bf4813028bCc910b4Ea89DFbc` | `0x4261010328af553aF4B28d55Bca61FA0715C6784` → `0x89659798eBB30E061355e34b8Aee2a51b080d8EB` |
| [optimism-mainnet](../../metadata/networks.json#L348) | `0x8276469A443D5C6B7146BED45e2abCaD3B6adad9` → `0x9F95F7B3e525e570D1E079a0A813B833d6bd7feF` | `0x4f0A3519AB110c123d8d646A4a38b132d6307628` | `0xa132a33bB6ED51085d376b3CC90c7723171ebb79` → `0x5CC856F692b4B6931c194c639A8d71236581f9e8` |
| [arbitrum-one](../../metadata/networks.json#L411) | `0x1C21Ead77fd45C84a4c916Db7A6635D0C6FF09D6` → `0x24e822D3dBf06F2d6FfF64F4452885F819e1e1c4` | `0x4D11B0b59948d81EEAaF667CCDaA212f824949d4` | `0xa132a33bB6ED51085d376b3CC90c7723171ebb79` → `0x58c472e412F382ac48B7904009331177fb03826c` |
| [avalanche-c](../../metadata/networks.json#L473) | `0x464AADdBB2B80f3Cb666522EB7381bE610F638b4` → `0xb0817050FA28a1577D90D441e95779b96a09D263` | `0x31D5847E2b7c43b90Aee696519465a8d9F75E9EC` | `0x07E4A282F8f20032F3e766fFFB73c8b86bA7e1f1` → `0xC899724F32859E8169e607A23448e4B487B4Dc04` |
| [bsc-mainnet](../../metadata/networks.json#L535) | `0x8bde47397301F0Cd31b9000032fD517a39c946Eb` → `0x1C7579Eec65D413bdd510AFFEc59dFe9A78d8048` | `0xC6082f0B0040809217f96C0aB946a556263042A0` | `0xD6CB236FAB27C4235cbDA9FE38fC2e902235F057` → `0xA6030b270Dd8337F37D4FacE06b40749DC92DA5e` |
| [eth-mainnet](../../metadata/networks.json#L597) | `0x0422689cc4087b6B7280e0a7e7F655200ec86Ae1` → `0x5a2362c459006836dE9Ef9De8C3a0180A2F6ed42` | `0x22b06D3eAD2d720A2A86c3fabe424cDdBBEBa5fA` | `0x0043d7c85C8b96a49A72A92C0B48CdC4720437d7` → `0xe75eaFe86C2bE20d8D0C4cCd520a8231c13CB53F` |
| [celo-mainnet](../../metadata/networks.json#L658) | `0x36be86dEe6BC726Ed0Cbd170ccD2F21760BC73D9` → `0x265FDF458B423935A3F3E44A0BecD96D6e32073D` | `0xB0adC0d2F68901640cF444632213ebC02EB19A32` | `0x94aE5f52E401A5766b0877d2f030cFb9C3792BD7` → `0x24e822D3dBf06F2d6FfF64F4452885F819e1e1c4` |
| [base-mainnet](../../metadata/networks.json#L698) | `0xe20B9a38E0c96F61d1bA6b42a61512D56Fea1Eb3` → `0x83fD14e2384E7b2F1BAe7Abacfacf66E33dd82d8` | `0x17E0B9912D900982189d3D025e81D0dd57674640` | `0x5487d078CA8933e83d91d5E7AFBe3A7bfC3412d6` → `0x5994cb25447265A3DdC4453Ffd7632a5f86Ad714` |
| [scroll-mainnet](../../metadata/networks.json#L758) | `0xacFBED2bC9344C158DD3dC229b84Bd7220e7c673` → `0x11198b84Bb8609E9F1a207a7364c0E6dF0802BD8` | `0x06469EF22425cae0C202F06dC6f7a578e97e61C6` | `0x348d8F7637b0dDA374a3D1340A4d0918d07F783E` → `0x1f73832d4d4992AE0fcc181139E4Bc88afB43694` |
| [arc-mainnet](../../metadata/networks.json#L797) | `0x583C78b9c93538FEfc56E49371A0dcc844027325` → `0x752f83899F6cCa2486EeF632d0a5b1AF70d35296` | `0x0625bD1e1D2D2fA153236726aFE541A35022b09A` | `0xDa2cF1aaFFc7C34E371a6b1C606ae455a8e3c7a0` → `0xb825C8e65ca7465046ad5ab430a0a9e071126789` |

All 16 `POOL_MEMBER_NFT()(address)` (SuperToken) and `POOL_MEMBER_NFT_LOGIC()(address)` (factory) return `ZERO`; no PoolMember NFT proxy implementation applies. All 16 ConstantOutflow/ConstantInflow NFT queries failed: factory `CONSTANT_OUTFLOW_NFT_LOGIC()(address)`, `CONSTANT_INFLOW_NFT_LOGIC()(address)` and token logic `CONSTANT_OUTFLOW_NFT()(address)`, `CONSTANT_INFLOW_NFT()(address)`. Fourteen networks returned execution-reverted/empty data on explicit re-read; Avalanche C/BSC re-reads hit historical-state errors. No address is invented for these removed APIs. Current factory only exposes pool NFT immutables and SuperToken only declares pool NFT addresses ([SuperTokenFactory.sol:26–34](../contracts/superfluid/SuperTokenFactory.sol#L26), [SuperToken.sol:63–67](../contracts/superfluid/SuperToken.sol#L63)); this is consistent with a **retired** constant-flow NFT surface, not proof that no historical NFT exists elsewhere.

### D.3 — pool beacon and linked GDA libraries

RPC sources on GDA: `superfluidPoolBeacon()(address)`, `SLOTS_BITMAP_LIBRARY_ADDRESS()(address)`, `SUPERFLUID_POOL_DEPLOYER_ADDRESS()(address)`, `MAX_POOL_AUTO_CONNECT_SLOTS()(uint32)`; on beacon: `implementation()(address)` and `owner()(address)`. All beacon owners equal the network host; all max auto-connect slots equal **4**. [GDA source:45–65](../contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol#L45); beacon compatibility/ownership guards: [SuperfluidUpgradeableBeacon.sol:14–29](../contracts/upgradability/SuperfluidUpgradeableBeacon.sol#L14).

| Network | Pool beacon → implementation | GDA bitmap library | GDA pool deployer library |
| --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | `0x3073dD4a041b77f547b649A1BA3947355c34682c` → `0x64Bc5574F9115f9E97a472Ee992A4CAE523Cccfc` | `0xC9422E9607218f7dFE80C5fA5Bd083A207B2808D` | `0x36cF3de0849DB7223FBf0e224EdcFBA23f41D984` |
| [eth-sepolia](../../metadata/networks.json#L51) | `0x712A3edF1fb9070695BF08Adf82C289fB1972E78` → `0x38DC281A7ee23151B3A610e85CfF133133c07539` | `0xC6082f0B0040809217f96C0aB946a556263042A0` | `0x334a28904456c7C1cf648A6936a82505e83961aC` |
| [optimism-sepolia](../../metadata/networks.json#L91) | `0x0FB7694c990CF19001127391Dbe53924dd7a61c7` → `0xF8fD3162D77DBCa1c34835226EFAc3Ac205e63A0` | `0x817514976F2E4436d4bA19C14F1d202b2080358F` | `0x18E3AE4eBe9D6a4D6c1fd7BAe95ae75DC386753c` |
| [base-sepolia](../../metadata/networks.json#L149) | `0x507c3a7C6Ccc253884A2e3a3ee2A211cC7E796a6` → `0x5547885781991278Ec7244cd356FE40B377cEe07` | `0x3c7fBf36758062aD1669CFf66e4e408397A17d7D` | `0x7a8b025d937E4189d22F2B14d653EE7e40fdD848` |
| [arc-testnet](../../metadata/networks.json#L185) | `0x9F9EEd9Bbc38E9e0514fD9dFcc0Bca9869A9c534` → `0xe3F6ec0676B9CE5D759580E1d526dee31678c283` | `0x35aED9E37FC7b8030D4B643139Bfe63F15D12ead` | `0xee34cB3AC309CE2C6b0bEaF403D89db0E635fE85` |
| [xdai-mainnet](../../metadata/networks.json#L223) | `0x9a19773eBe33c5917012c2Bb982bc683d91Ec600` → `0xeEDe00A8A77595D9b30EeE801e0B50CBC785f04a` | `0x099A32459841D2de0a28B861dBc30BfF20D16bb5` | `0x42f85B01B2F2929BB5f0c944E0Bb6897fB03C80e` |
| [polygon-mainnet](../../metadata/networks.json#L286) | `0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9` → `0xCEc4de78a8379E5d99A75C330ba773e740344522` | `0xcF5674dd984102DD15c9bb035B4F75df600c1857` | `0x218AaB69Dd72156d32641bcc44eB87d0FD34d326` |
| [optimism-mainnet](../../metadata/networks.json#L348) | `0xA7F9eEaA46fa7E1Af2c4bdAF7acB9Fd89fA46FbD` → `0x7370970504E0bc013b9fa1d9cA0a3409Dcdb0208` | `0x2Dc25E221D493526Bf6A6FcE3076bA2C72b47678` | `0x5377C701D05bB7947d961f71C8cf1983E9A52435` |
| [arbitrum-one](../../metadata/networks.json#L411) | `0xA7F9eEaA46fa7E1Af2c4bdAF7acB9Fd89fA46FbD` → `0x130F449DF824F7721995292128Df6e3d5cD70520` | `0xA97ab27b3ab6eED3B4699ad8a6378d6b7EC18042` | `0xE49c89f4324E48F39b5376d69ca7f862c6710138` |
| [avalanche-c](../../metadata/networks.json#L473) | `0xDD5462a7dB7856C9128Bc77Bd65c2919Ee23C6E1` → `0x0FcDDF2d5023219145e902Cb3b0c44159ab59d61` | `0x57897b796ece6633fc7C0c6490B4eb84D58509E5` | `0x9956Ffa4c8d5142214432071226b6F248786bC42` |
| [bsc-mainnet](../../metadata/networks.json#L535) | `0x2DD77061791D229705D67ccB92be1a7739c4A196` → `0x38bfdf60f9061FCAC55e4170AB082dbC73A45619` | `0xB0adC0d2F68901640cF444632213ebC02EB19A32` | `0xB5CA2D51Ab91F4ff98B6BFA595B3eD496d8d30bC` |
| [eth-mainnet](../../metadata/networks.json#L597) | `0xD48317ccdac2ca3fd5E3c58c32Da3A7c517937B6` → `0xC02d95c3Df22639A3920CD6079991AE80eBfBB42` | `0xF26967f92151487f8c6642199c3441B02398D19E` | `0x658aAcE714e6307f89b7740e07aA0838416C9aBd` |
| [celo-mainnet](../../metadata/networks.json#L658) | `0x882703DC8239e2Ba167e06CE1FcF654E17A0bd06` → `0x32aE3c86bd1BD97b56944f477BD3711801Fa325c` | `0x1c971E8863c63E1F1BdaF7dBF4831EcA197C9508` | `0x58c472e412F382ac48B7904009331177fb03826c` |
| [base-mainnet](../../metadata/networks.json#L698) | `0xdE62033F32B1D0b5911290105f39E006cffC7a9e` → `0x658B882d41db5114587C4B1B46FDD43b2b87Dba6` | `0x959653df67F6385eff01e38DE6b9e493C09Cd384` | `0x3c7fBf36758062aD1669CFf66e4e408397A17d7D` |
| [scroll-mainnet](../../metadata/networks.json#L758) | `0xF37BF0ed756FE0398983EB2b45154c942510740A` → `0xB9B8cDb05aD60e98a13a0F4b5E9d73Bc31557E61` | `0x1BD3b6522102F9ea406807f8ecaeB2D96278a83f` | `0xB0B9B7D90e60242DBc76A190b898Cb7286D636bD` |
| [arc-mainnet](../../metadata/networks.json#L797) | `0xe7C51A3a46F543931EB1d98205a21B75CF863991` → `0xa6Fd6af572948F9D3B504106632415AddC71d4FE` | `0x0E34Ac65ab770542afaa687c78c19A52Ad511A4E` | `0x9FD6837A8adA9D183DbBC4e9c18dFc4CF41149eA` |

### D.4 — metadata forwarders and host trust

Addresses below are metadata inputs independently code-checked on each chain; trust source is `c HOST 'isTrustedForwarder(address)(bool)' FORWARDER`. **All four named forwarders have code on all 16 networks**. This table separates presence from activation.

| Alias | Metadata field | Full address |
| --- | --- | --- |
| F1 | cfaV1Forwarder | `0x2CDd45c5182602a36d391F7F16DD9f8386C3bD8D` |
| F2 | gdaV1Forwarder | `0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08` |
| F3 | macroForwarder | `0xFD0268E33111565dE546af2675351A4b1587F89F` |
| F4 | clearMacroForwarderV1WithPermit2 | `0xC1EaB73855155D4e021f7EB4f866996Bac2fe25e` |
| F5 | cfaV1Forwarder | `0xcfA132E353cB4E398080B9700609bb008eceB125` |

| Network | CFA address / trusted | GDA address / trusted | Macro address / trusted | Clear Macro Permit2 address / trusted |
| --- | --- | --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | F1 / true | F2 / true | F3 / true | F4 / false |
| [eth-sepolia](../../metadata/networks.json#L51) | F5 / true | F2 / true | F3 / true | F4 / false |
| [optimism-sepolia](../../metadata/networks.json#L91) | F5 / true | F2 / true | F3 / true | F4 / false |
| [base-sepolia](../../metadata/networks.json#L149) | F5 / true | F2 / true | F3 / true | F4 / false |
| [arc-testnet](../../metadata/networks.json#L185) | F5 / true | F2 / true | F3 / true | F4 / false |
| [xdai-mainnet](../../metadata/networks.json#L223) | F5 / true | F2 / true | F3 / true | F4 / true |
| [polygon-mainnet](../../metadata/networks.json#L286) | F5 / true | F2 / true | F3 / true | F4 / true |
| [optimism-mainnet](../../metadata/networks.json#L348) | F5 / true | F2 / true | F3 / true | F4 / true |
| [arbitrum-one](../../metadata/networks.json#L411) | F5 / true | F2 / true | F3 / true | F4 / true |
| [avalanche-c](../../metadata/networks.json#L473) | F5 / true | F2 / true | F3 / true | F4 / true |
| [bsc-mainnet](../../metadata/networks.json#L535) | F5 / true | F2 / true | F3 / true | F4 / true |
| [eth-mainnet](../../metadata/networks.json#L597) | F5 / true | F2 / true | F3 / true | F4 / true |
| [celo-mainnet](../../metadata/networks.json#L658) | F5 / true | F2 / true | F3 / true | F4 / true |
| [base-mainnet](../../metadata/networks.json#L698) | F5 / true | F2 / true | F3 / true | F4 / true |
| [scroll-mainnet](../../metadata/networks.json#L758) | F5 / true | F2 / true | F3 / true | F4 / true |
| [arc-mainnet](../../metadata/networks.json#L797) | F5 / true | F2 / true | F3 / true | F4 / true |

Additional metadata trustedForwarders exist only on Avalanche Fuji: source [networks.json:44–47](../../metadata/networks.json#L44), `cast code ADDRESS` and host `isTrustedForwarder(address)(bool)` at **60846313**:

| Address | Code bytes | Host trusted |
| --- | --- | --- |
| `0x6271Ca63D30507f2Dcbf99B52787032506D75BBF` | 5363 | true |
| `0xb539068872230f20456CF38EC52EF2f91AF4AE49` | 0 | true |
| `0xd8253782c45a12053594b9deB72d8e8aB2Fca54c` | 0 | true |

### D.5 — metadata code-presence sanity

Source for each row: recursively enumerate all `contractsV1` address leaves, `nativeTokenWrapper` if present, and `trustedForwarders` from that row's linked metadata, then `cast code ADDRESS --rpc-url "$RPC" --block B`. Counts are address fields, not necessarily distinct addresses. All checked fields had nonzero code **except the explicit zero-code exceptions below**; all nonzero discovered host/governance implementations, agreements, factory, SuperToken logic, PoolAdmin NFT, beacon, libraries and host dependencies in A–D also had code. Governance/resolver EOA authorities are intentionally not required to have code.

| Network | Metadata address fields read | Zero-code exceptions |
| --- | --- | --- |
| [avalanche-fuji](../../metadata/networks.json#L3) | 19 | trustedForwarder1 = `0xb539068872230f20456CF38EC52EF2f91AF4AE49` (0 bytes); trustedForwarder2 = `0xd8253782c45a12053594b9deB72d8e8aB2Fca54c` (0 bytes) |
| [eth-sepolia](../../metadata/networks.json#L51) | 15 | none |
| [optimism-sepolia](../../metadata/networks.json#L91) | 19 | none |
| [base-sepolia](../../metadata/networks.json#L149) | 14 | none |
| [arc-testnet](../../metadata/networks.json#L185) | 13 | none |
| [xdai-mainnet](../../metadata/networks.json#L223) | 22 | wrapManager = `0x7a2899D179a8F205C8EDAd2e52954cA5f6d48D1A` (0 bytes) |
| [polygon-mainnet](../../metadata/networks.json#L286) | 21 | none |
| [optimism-mainnet](../../metadata/networks.json#L348) | 22 | none |
| [arbitrum-one](../../metadata/networks.json#L411) | 21 | none |
| [avalanche-c](../../metadata/networks.json#L473) | 21 | none |
| [bsc-mainnet](../../metadata/networks.json#L535) | 21 | none |
| [eth-mainnet](../../metadata/networks.json#L597) | 20 | none |
| [celo-mainnet](../../metadata/networks.json#L658) | 16 | none |
| [base-mainnet](../../metadata/networks.json#L698) | 22 | none |
| [scroll-mainnet](../../metadata/networks.json#L758) | 15 | none |
| [arc-mainnet](../../metadata/networks.json#L797) | 14 | none |

## Differences versus getConfig.js and legacy defaults

Comparison assumes **no operator environment/option overrides**, release `v1`. `getConfig` is policy for future deployments, not proof of current state. Evidence below is A–D at the recorded blocks plus the linked source.

| Setting | Observed versus default | Explanation / disposition |
| --- | --- | --- |
| Upgradeability | 16/16 `NON_UPGRADABLE_DEPLOYMENT=false`, each host has a nonzero implementation. Legacy optional `NON_UPGRADABLE` is off absent an override. | No difference; **simplified** to upgradeable persistent frameworks. Legacy branch: [deploy-framework.js:242–248](deployment-tooling.md), [469](deployment-tooling.md). Production non-upgradeable mode is **retired**; local fixture modes are **covered by devchain tooling**, not justified by these deployments. |
| Callback gas | Fuji and Avalanche C 7,500,000; xDai 8,500,000; Ethereum/Scroll 3,000,000; remaining 11 networks 12,000,000. | Exact match to current defaults/overrides, not one universal value. [getConfig.js:38–71](deployment-tooling.md), [99–100](deployment-tooling.md) explain cost/solvency, half-block-budget and Scroll circuit constraints; current generic 12M reflects EIP-7825. **supported** per-chain policy; preserve the existing decrease guard ([deploy-framework.js:941–953](deployment-tooling.md)). |
| App whitelisting | Five testnets false, ten mainnets true, **arc-mainnet false**. getConfig would set every mainnet true. | **Unexplained exception: arc-mainnet**. There is no arc override ([getConfig.js:5–73](deployment-tooling.md), [83](deployment-tooling.md)). Celo is true, consistent with the commented-out permissionless override ([61–65](deployment-tooling.md)). **supported**: preserve the actual chain value; do not silently enable Arc permissioning on upgrade. |
| IDA policy | Optimism mainnet + Sepolia: unfrozen/32. Other 14: frozen/256. | Exact match to [getConfig.js:27–36](deployment-tooling.md), [101–104](deployment-tooling.md). **supported** per-chain policy, with one-way freeze preflight ([deploy-framework.js:346–364](deployment-tooling.md)). Do not infer a 32 cap or freeze from the library address. |
| Liquidation / PPP | Testnets 3,600 / 720, matching default; **all 11 mainnets 14,400 / 1,800**, versus default 14,400 / **2,880** (20%). | **Unexplained historical value**: mainnet patrician periods are 12.5%, not the current default 20%. Source defines defaults ([getConfig.js:79–82](deployment-tooling.md)) but does not explain deployed 1,800. **supported**: preserve governance state; upgrades must not reinitialize defaults. |
| Reward / minimum deposit | Test reward equals the shared EOA; mainnet rewards are per-chain B.1 values. Minimum deposit is zero on all 16. | Test reward matches bootstrap's `accounts[0]` pattern, but deployment signer identity is **inferred**, not reconstructed ([deploy-framework.js:539–548](deployment-tooling.md)). getConfig has no reward-address/minimum-deposit default. Production loads existing governance ([509–515](deployment-tooling.md)); **supported**, preserve values rather than selecting a new operator's account. Mainnet historical reward-selection rationale is unknown. |
| Governance authority | Testnets direct EOA; all mainnets Safe 2-of-4 except Arc 2-of-3. Resolver authority is different on every mainnet. | Owner/admin addresses are not defaults in getConfig. Historical script already loads Ownable, Safe, multisig and enumerable ACL interfaces ([deploy-framework.js:384–391](deployment-tooling.md)). **supported** direct EOA, Safe and legacy multisig routes; resolver authority cannot be derived from host governance. |
| Resolver / factory / agreements | All current host, registered CFA/IDA/GDA and factory proxies match metadata; every resolver `Superfluid.v1` matches host. | No difference. getConfig resolver matches metadata unless explicitly overridden ([getConfig.js:92–98](deployment-tooling.md)). **supported** explicit discovery and mismatch rejection, not a copied address fallback. |
| Host dependencies / ACL | All have nonzero SimpleForwarder, ERC2771Forwarder, SimpleACL. Sampled role authority is not generally the governance owner or resolver admin. | Chain-specific state, not fresh defaults. Source explains preserving existing ACL ([deploy-framework.js:936–938](deployment-tooling.md)); role setup is [1027–1049](deployment-tooling.md). **supported** preservation of all three dependencies and ACL state; no ACL reset in upgrade mode. Full ACL membership is unknown, not a fixed empty/default set. |
| Standard forwarders | CFA/GDA/Macro exist and are trusted on 16/16; Fuji CFA differs from generic canonical address. | Matches metadata-backed defaults ([getConfig.js:92–94](deployment-tooling.md)); fresh TestGovernance initialization adds metadata extras plus these three ([deploy-framework.js:520–548](deployment-tooling.md)). **supported** deploy → code-check → activate; do not substitute generic CFA on Fuji. |
| Clear Macro Permit2 | Code on all 16; trusted on 11 mainnets, **not trusted on five testnets**. | Partly source-explained: getConfig and legacy bootstrap do **not** include this fourth forwarder in their standard activation list ([getConfig.js:92–98](deployment-tooling.md), [deploy-framework.js:520–548](deployment-tooling.md)). Why activation differs operationally is **unexplained**. Current forwarding base calls host forwarding with appended sender ([ForwarderBase.sol:40–46](../contracts/utils/ForwarderBase.sol#L40)); presence is not activation. **supported** explicit trust inspection, not automatic trust changes. |
| Extra metadata / code sanity | Fuji lists three extra trusted addresses, two with no code despite host trust=true. xDai `wrapManager` has no code. | **Unexplained metadata/code discrepancies**; addresses and blocks in D.4/D.5. Do not treat metadata membership as code-presence proof, or silently deploy/enable a substitute. No requirement to remove unrelated metadata follows from this discovery. |
| NFT surface | PoolAdmin NFT proxy/logic present on all 16. PoolMember zero; ConstantInflow/Outflow APIs fail. | Consistent with current pool-admin-focused source ([SuperToken.sol:121–133](../contracts/superfluid/SuperToken.sol#L121), [SuperTokenFactory.sol:26–34](../contracts/superfluid/SuperTokenFactory.sol#L26)) and legacy deployment checks ([deploy-framework.js:1175–1188](deployment-tooling.md)). PoolAdmin **supported**; reinstating removed constant-flow NFTs is **retired**, not a migration requirement. Unknown historical NFTs are not treated as nonexistent. |
| Pool beacon | Beacon owner is host; implementation and linked GDA libraries are per-chain values in D.3. | Matches host-governed upgrade design ([Superfluid.sol:340–352](../contracts/superfluid/Superfluid.sol#L340), [deploy-framework.js:1296–1313](deployment-tooling.md)). **supported** preserve beacon identity/ownership and use compatible pool logic. |

## Conclusions for deployment-tooling design

| Question | Conclusion | Evidence / disposition |
| --- | --- | --- |
| Can persistent/production deployment be upgradeable-only? | **Observed:** all 16 hosts, including all 11 mainnets, report false for NON_UPGRADABLE and expose nonzero UUPS implementations. **Inferred:** yes, supporting only the upgradeable framework shape for maintained persistent deployments is justified by this inventory. This does not mean every component itself is proxied: five testnet governance contracts have no discovered UUPS implementation. | A/B; **simplified** persistent model, production non-upgradeable option **retired**. Fresh upgradeable deployments remain **supported** by the binding scope decision; onchain inspection alone does not validate a new deployer implementation. |
| Which governance routes are needed? | **Observed:** five direct EOA governance owners; eleven Safe governance owners (ten 2-of-4, Arc 2-of-3); zero legacy-multisig governance owners. **Inferred:** direct EOA and Safe execution/proposal paths are both necessary. | B wallet getters and code reads; both **supported**. Counts are per chain, not distinct global addresses. |
| Can legacy multisig support be removed? | **Observed:** resolver admin is direct EOA on seven networks (all five testnets, xDai, Polygon) and legacy Gnosis multisig on nine mainnets; no resolver Safe admin observed. Legacy requirements range 1-of-3 through 1-of-6. **Inferred:** no, legacy multisig remains necessary for resolver operations even though governance moved to Safe. | B; legacy multisig **supported**. Resolver admin equals governance owner only on the five testnets; **never assume equality** for production. A signer of a multisig is not the resolver-role holder. |
| Which values must survive an upgrade? | **Observed:** A–D record exact host/factory/agreement/NFT/beacon identities, all host immutables, governance pointers/owners, resolver role members, PPP/rewards/deposit defaults, sampled app permissions, trust settings, IDA freeze/cap and linked libraries. **Inferred:** keep storage-bearing proxies, resolver/governance authority and ACL state; preserve chain-specific callback/whitelist/IDA policy unless deliberately approved; pass existing dependency addresses into new logic. Preserve NFT/beacon linkage and compatible layouts. | A–D; **supported** preservation. Do not replace Arc's false whitelist with mainnet default true, 1,800-second mainnet PPP with 2,880, or a frozen IDA with unfrozen logic. Source guards: [deploy-framework.js:89–131](deployment-tooling.md), [936–953](deployment-tooling.md). |
| Does a matching metadata address establish readiness? | **Observed:** two trusted Fuji extras and xDai wrapManager have no code; Clear Macro exists but is untrusted on every testnet. **Inferred:** no; discovery must separate metadata, code, protocol registration and host trust. | D.4/D.5; code/trust checks **supported**. No surprise activation, broadcast or metadata repair is authorized by this inventory. |
| Which old modes follow from this evidence? | **Inferred:** supported persistent deployment/upgrade, EOA/Safe/legacy resolver administration, standard forwarder operations and required verification should be kept; mocks/devchain-only flags are **covered by devchain tooling**. A concrete operation outside confirmed scope must be **not implemented** with a pre-side-effect failure, not a successful no-op. | Inventory establishes deployment shapes, not all callers. Caller/workflow disposition is the companion inventory's responsibility; this document does not retire manual-only operations. |

## Unknowns / unreachable values

| Scope | Unknown / limitation | Exact evidence / consequence |
| --- | --- | --- |
| RPC reachability | None of the 16 chains was unreachable for initial core discovery; chain IDs matched metadata. Historical retention is limited. | Observation table and A–D. All initial getter/code observations used the single recorded B, not a moving latest tag. |
| Avalanche C supplemental calls | App key samples and ACL role-admin/membership samples unknown at **99956603**. | `c GOVERNANCE 'verifyAppRegistrationKey(address,address,string)(bool,uint256)' HOST OWNER_OR_ADMIN k1` and `c ACL 'getRoleAdmin(bytes32)(bytes32)' ROLE` / `hasRole(bytes32,address)(bool)` returned `-32000: missing trie node ... state ... is not available, not found`. No newer block substituted. |
| BSC supplemental calls | Same app/ACL samples unknown at **132818450**. | Same calls returned `-32000: not supported`. This is an RPC historical-state limitation, not a false/zero permission result. |
| Failed legacy getter re-reads | On Avalanche C/BSC, retrying failed ConstantInflow/Outflow and Safe `required()` / resolver Safe-detection calls hit the above historical errors; their exact initial failure reason was not retained. | Initial calls exited unsuccessfully; no value assigned. Positive `VERSION/getOwners/getThreshold` on governance Safe and `required/getOwners` on resolver multisig were captured in the initial probe. Fourteen other chains returned explicit empty-data reverts for removed NFT getters. |
| Testnet governance implementation | No UUPS/EIP-1967 implementation found; a hypothetical custom proxy is not ruled out. | Five failed `getCodeAddress()(address)` calls and zero EIP-1967 slots at respective Bs; direct TestGovernance classification is **inferred** from source, not bytecode/explorer verification. |
| Full trust/config enumeration | Only metadata forwarders were queried; other governance-trusted addresses, token-specific reward/PPP/deposit/forwarder overrides, registration keys and app-factory authorizations are not enumerated. | Governance is keyed storage without an enumerable key getter ([SuperfluidGovernanceBase.sol:231–260](../contracts/gov/SuperfluidGovernanceBase.sol#L231), [472–543](../contracts/gov/SuperfluidGovernanceBase.sol#L472)). Defaults and two `k1` samples do not imply all other state is empty. An in-place upgrade must preserve storage rather than rebuilding it from this inventory. |
| Full SimpleACL membership | Unknown; only the named roles and three candidate members were sampled where RPC allowed. | SimpleACL inherits non-enumerable AccessControl, not AccessControlEnumerable ([SimpleACL.sol:4–14](../contracts/utils/SimpleACL.sol#L4)). No RoleGranted/RoleRevoked log range was searched for ACL; unlike resolver membership, a complete ACL reconstruction was not claimed. Preserve the existing ACL. |
| Historical configuration rationale | Arc permissionless host, mainnet 1,800-second patrician period, reward selection, removed/code-empty metadata entries and Clear Macro activation chronology are not explained by current defaults. | Differences table identifies each as unexplained or partially source-explained. No deployment transactions, historic proposals or signer identities were inferred as facts. |
| Wallet reachability beyond listed owners | Safe modules/guards and nested contract-signer authority were not enumerated; multisig-owner getter results establish the requested owner route, not every possible module route. | B records direct `owner`, role-holder and threshold/getOwners responses; EOA classification applies only where code was actually checked and absent. |

No transactions were sent and no state was changed. This evidence document makes no claim that deployment/upgrade simulations, build checks or tests were exercised.
