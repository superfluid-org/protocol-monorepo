
# Truffle migration disposition — frozen 2026-11-12

This is a migration record, not maintained operator instructions. Use [deployment tooling](../deployment-tooling.md) for current commands and safety policy.

## Complete legacy operation and caller disposition

Paths in the old column are package-relative historical identifiers, **not live
links**. Every top-level legacy operation, task wrapper and deployment option is
accounted for. **Supported** preserves the capability; **simplified** preserves
an outcome with a smaller explicit interface; **retired** removes it with no shim;
**not implemented** is an explicit unsuccessful path, never a successful no-op;
**devchain** means covered by dedicated local/test tooling. Manual operator use
remains a requirement even without CI callers.

Here `framework` = `bash new-ops-scripts/framework.sh NETWORK`, `resolver-token` =
`bash new-ops-scripts/resolver-token.sh NETWORK`, `gov-action` =
`bash new-ops-scripts/gov-action.sh NETWORK`.

### All 30 legacy operations

| Old `ops-scripts/` entry | New command / disposition | Reason |
| --- | --- | --- |
| `deploy-framework.js` | `framework fresh` / `framework upgrade` — simplified | Separate new deployment from implementation upgrade; no reset/conditional bytecode matrix. |
| `deploy-aux-contracts.js` | Included in fresh plus explicit handover — simplified | GovernanceII, PPP, TOGA/reward, BatchLiquidator belong to bootstrap; no separate community-deployment matrix. |
| `deploy-deterministically.js` | `deploy-deterministic-forwarder.sh NETWORK CONTRACT`; Loader in fresh — simplified | Retain supported deterministic forwarders; no force/deterministic Loader replacement. |
| `deploy-erc1820.js` | `deploy-erc1820.sh NETWORK [--broadcast]` — supported | Canonical presigned registry funding/publication is explicit. |
| `deploy-mfa.ts` | `dev-scripts/deploy-mfa.ts` — devchain | Already ethers; hardcoded local tester is not production. |
| `deploy-super-token.js` | ERC20 factory `cast send` or custom native helper, then resolver list — simplified | Deploy/list/logic upgrade are separate; do not reset an existing wrapper implicitly. |
| `deploy-test-environment.js` | `yarn testenv:deploy`, local JS/Solidity fixture — devchain | Local framework/default tokens/ETHx remain; persistent testnet is fresh + optional faucet. |
| `deploy-test-token.js` | Fixture helpers; `framework provision-test-token NAME SYMBOL DECIMALS MINT_LIMIT` — simplified | Explicit persistent testnet faucet; refuses occupied keys, no production mintable-token toggle. |
| `deploy-unlisted-super-token.js` | Permissionless factory `createERC20Wrapper` call — simplified | Listing is optional and independent; no new deploy SDK layer. |
| `deploy-unlisted-pure-super-token.js` | `deploy-custom-super-token.sh NETWORK pure NAME SYMBOL SUPPLY_BASE_UNITS` — simplified | Atomic custom initialization; explicit supply in base units. |
| `gov-authorize-app-deployer.js` | `gov-action setAppRegistrationKey DEPLOYER [EXPIRATION] [KEY]` — supported | Legacy host fallback remains live; default uint64-max expiry and `k1` preserved. SimpleACL grant is not equivalent. |
| `gov-set-3Ps-config.js` | `gov-action set3PsConfig TOKEN LIQUIDATION PATRICIAN` / `clear3PsConfig TOKEN` — supported | Explicit clear replaces special both-zero interpretation. |
| `gov-set-reward-address.js` | `gov-action setRewardAddress TOKEN REWARD` / `clearRewardAddress TOKEN` — supported | Explicit set/clear, zero token still means default scope. |
| `gov-set-token-min-deposit.js` | `gov-action setTokenMinimumDeposit TOKEN VALUE` — supported | Existing routed governance action. |
| `gov-set-trusted-forwarder.js` | `gov-action enableTrustedForwarder TOKEN FORWARDER` / `disableTrustedForwarder` — supported | No truthy 1/0 ambiguity; preserve default/token scope and execution gate. |
| `gov-transfer-framework-ownership.js` | `framework handover-governance OWNER`, `grant-resolver-admin ADMIN`, `revoke-resolver-admin OLD NEW` — simplified | Separate authorities, grant must execute before revoke. |
| `gov-upgrade-governance.js` | `framework upgrade-governance` — supported | GovernanceII implementation only, not direct TestGovernance. |
| `gov-upgrade-super-token-logic.js` | `framework upgrade-tokens '[0xA,0xB]'` — simplified; `ALL` not implemented | Separate action after framework execution; canonical host-governed proxies only. |
| `info-inspect-account.js` | `cast call`, sdk-core, explorer — retired | No maintained report CLI; removed runner/path is the deliberate failure. |
| `info-list-apps.js` | Query `AppRegistered` logs/subgraph — retired | No duplicate report layer. |
| `info-print-contract-addresses.js` | `bash new-ops-scripts/info-print-contract-addresses.sh NETWORK` — simplified | JSON snapshot, not sourced shell assignments. |
| `info-scan-deployments.js` | `cast logs`, explorer/subgraph event queries — retired | Metadata is not discovery of unknown deployments; no automatic scanner promised. |
| `info-show-protocol.js` | Address JSON plus cast/sdk-core/explorer — retired | Full legacy report not reproduced. |
| `resolver-list-super-token.js` | `RELEASE_VERSION=v1 resolver-token list TOKEN [SYMBOL]` — simplified | Exact release/symbol namespace, explicit overwrite. |
| `resolver-register-token.js` | `resolver-token register NAME TOKEN` — supported | `tokens.NAME` via existing resolver setter. |
| `resolver-reset-deployment.js` | `resolver-token reset RELEASE CONFIRM_RELEASE` — simplified | Two explicit zero writes, matching confirmation; not atomic. |
| `resolver-set-key-value.js` | `resolver-set-key.sh NETWORK KEY ADDRESS` — supported | Existing admin routing and overwrite guard. |
| `resolver-unlist-super-token.js` | `RELEASE_VERSION=v1 resolver-token unlist SYMBOL` — supported | Explicit release-qualified clearing. |
| `tmp-trigger-token-transfer.js` | None — retired | Temporary indexer-refresh helper deliberately removed; automatic refresh is not promised. |
| `validate-deployment.ts` | `new-ops-scripts/info-print-contract-addresses.sh NETWORK --validate` — supported | Explicit resolver/release; no fixed metadata-v1 target or Truffle globals. |

### Task wrappers, internal helpers and package commands

| Old surface | Replacement / disposition | Reason |
| --- | --- | --- |
| `tasks/deploy-cfa-forwarder.sh` | Same path + phases — simplified | Deterministic CFA deploy → verify → activate → execution → register. |
| `tasks/deploy-gda-forwarder.sh` | Same path + phases — simplified | Same GDA sequence, independent vanity signer. |
| `tasks/deploy-macro-forwarder.sh` | Same path + phases — simplified | Same sequence for **BlindMacroForwarder**, not ClearMacro substitution. |
| `tasks/etherscan-verify-framework.sh` | `new-ops-scripts/verify-framework.sh NETWORK [--plan]` — simplified | Native forge constructors/libraries/proxies, aggregate failure; no Truffle JSON mutation. |
| `tasks/etherscan-verify-proxies.sh` | Proxy source included in framework verifier; association `--verify-proxy` explicitly not implemented | Old plugin interface already unsupported; no successful placeholder wrapper. |
| `ops-scripts/libs/common.js`, `truffleScriptRunnerFactory.js`, `.eslintrc.js` | Removed — retired | No SDK loader, eval runner, stack detection, artifact/web3 globals or runtime compatibility mode. |
| `ops-scripts/libs/getConfig.js` | `ChainPolicy.sol` for fresh, current-chain getters for upgrades — simplified | Preserve real chain policy, discard Truffle/fixture default precedence. |
| Contracts `run-truffle`, `build:contracts:truffle`, disabled Truffle deployment test | Hardhat/Foundry builds/tests — retired | No disabled aliases or dormant Truffle entry points. |
| `test:deployment:scripts-js-hardhat`, `test:deployment:scripts-bash` | Maintained Foundry/Node/local-fork regressions — simplified | Port real deployment/admin/immutable/proxy/recovery safety, not native/injected runner smoke tests. |
| Root `build-essentials:js-sdk`, `build-for-contracts-dev:js-sdk`; js-sdk build/test/dev/watch/coverage/testenv wrappers | sdk-core workspace, explicit local deployer — retired | js-sdk is not active workspace/build/test/publication; no drop-in API shim. |
| `truffle-config.js`, SDK configs, Truffle/Web3 Hardhat plugins | Hardhat/Foundry config and explicit providers — retired | No HDWalletProvider/Truffle CLI/plugin/runtime dependency. Supported sdk-core Web3 providers remain. |

### Every framework option and shared environment family

Old JS option names and their env spelling are listed together where equivalent.
Old programmatic options, env selectors and removed scripts have no compatibility
entry point. No retired-env tombstone parser is retained; use the explicit CLI.

| Old option / env | New surface / disposition | Reason |
| --- | --- | --- |
| `isTruffle`, `DISABLE_NATIVE_TRUFFLE` | None — retired | No runtime detection/native/injected mode. |
| `web3`, common `ethers` injection | Explicit RPC/provider; fixture provider locally — simplified | No generic client/options bag. |
| `from` | `DEPLOYER` for simulation; keystore/`PRIVATE_KEY` for supported broadcast wrappers — simplified | Explicit sender; no first-unlocked-account assumption. |
| `newTestResolver`, `CREATE_NEW_RESOLVER` | `fresh` creates new resolver — simplified | No random existing-resolver replacement. |
| `useMocks`, `USE_MOCKS` | Local contract fixture — devchain | Production mocks rejected. |
| `nonUpgradable`, `NON_UPGRADABLE` | Local contract fixture — devchain; production retired | 16/16 persistent hosts upgradeable. |
| `appWhiteListing`, `ENABLE_APP_WHITELISTING` | Fresh chain policy; upgrades preserve onchain value — simplified | Preserve observed Arc exception, not boolean coercion. |
| `appCallbackGasLimit`, `APP_CALLBACK_GAS_LIMIT` | Fresh chain policy; upgrades preserve onchain value — simplified | Numeric immutable, not old unreliable boolean env coercion. |
| `ALLOW_DECREASE_APP_CALLBACK_GAS_LIMIT` | None — retired | Immutable changes are unsupported; upgrades always preserve deployed callback/whitelist/IDA values. |
| `resetSuperfluidFramework`, `RESET_SUPERFLUID_FRAMEWORK` | Separate `fresh`/`upgrade`; local fixture reset — retired production knob | No destructive reset disguised as repeat deployment. |
| `protocolReleaseVersion`, `RELEASE_VERSION` | `RELEASE_VERSION` / discovery `--release` — supported | Framework defaults `v1`; list/unlist require explicit release, never runner default `test`. |
| `outputFile`, `OUTPUT_FILE` | Native broadcast/cache, logs, JSON discovery, `SAFE_PAYLOADS_FILE` — simplified | No executable shell-assignment output. |
| `newSuperfluidLoader`, `NEW_SUPERFLUID_LOADER` | Loader included only in fresh — retired force knob | Forced/deterministic Loader replacement not retained; existing resolver entries can be explicitly administered. |
| `WITHOUT_ERC1820` | Fresh preflight + prerequisite command — retired | ERC777 registry functionality required for full fresh deployment; no new upgrade prerequisite. |
| `NO_NEW_GOVERNANCE`, `DISABLE_TEST_GOVERNANCE` | Fresh GovernanceII, fixture locally — retired production knobs | No production TestGovernance selector. |
| `IS_HARDHAT` | Normal local fixture/config — retired | No linking/gas runtime branches. |
| `RESOLVER_ADDRESS` | Explicit resolver operations/discovery/validator — supported; not a fresh override | Fresh creates its own resolver; existing operations must target actual authority. |
| `IS_TESTNET` | Canonical chain policy — retired override | No env truthiness determines deployment owner/type. |
| `GOVERNANCE_ADMIN_TYPE` | Onchain owner autodetection — simplified | Safe vs EOA determined from actual owner, no forced legacy-multisig mainnet assumption. |
| `RESOLVER_ADMIN_TYPE` | Onchain role/admin autodetection, authorized `RESOLVER_ADMIN` if ambiguous — simplified | No last-role-member fallback; independent governance/resolver authority. |
| `SAFE_API_KEY` | Safe proposer service auth — supported | Operator credential, not required for keyless payload generation. |
| `PROVIDER_URL_OVERRIDE` | Same override, below `RPC_URL` priority — supported | Real operator RPC override remains. |
| `PROVIDER_URL_TEMPLATE` | Same `{{NETWORK}}` template — supported | Canonical network interpolation. |
| Network/alias/`DEFAULT_` `PROVIDER_URL` | `RPC_URL` or shared RPC helper — simplified | Truffle aliases/prefix matrix removed. |
| Network/alias/`DEFAULT_` `MNEMONIC` | Encrypted Foundry keystore — retired mnemonic interface | No mnemonic compatibility shim or dependence on manual CI signing secret. |
| Network/alias/`DEFAULT_` `PRIVATE_KEY` | `WALLET_NAME` or plain `PRIVATE_KEY` — simplified | No HDWalletProvider alias lookup; prefer encrypted account. |
| Network/alias/`DEFAULT_` `GAS_PRICE` | Native Foundry fee configuration — simplified | No Truffle-prefixed aliases or arbitrary extra framework flags. |
| Network/alias/`DEFAULT_` `MAX_FEE_PER_GAS` | Native Foundry fee configuration; deterministic deployer `MAX_FEE_PER_GAS` — simplified | No alias inheritance; operator controls supported native interface. |
| Network/alias/`DEFAULT_` `MAX_PRIORITY_FEE_PER_GAS` | Native Foundry fee configuration; deterministic deployer `MAX_PRIORITY_FEE_PER_GAS` — simplified | No blanket translation of old env to framework argv. |
| `PRIVATE_PROVIDER_PORT` | Explicit local `RPC_URL` — devchain | No production private-provider network preset. |
| `SOLC` | Pinned Hardhat/Foundry compiler settings; verifier `--compiler-version` where appropriate — retired Truffle knob | Compiler pin remains, no native Truffle compilation selector. |
| `ETHERSCAN_API_V2_KEY`, `ETHERSCAN_API_KEY` | Framework verifier Etherscan auth — supported | Keyless Sourcify is default; V2 key works without alias matrix. |
| `POLYGONSCAN_API_KEY`, `SNOWTRACE_API_KEY`, `OPTIMISTIC_API_KEY`, `BSCSCAN_API_KEY`, `ARBISCAN_API_KEY`, `GNOSISSCAN_API_KEY`, `CELOSCAN_API_KEY`, `BASESCAN_API_KEY`, `ZKEVM_POLYGONSCAN_API_KEY`, `SCROLLSCAN_API_KEY` | Unified framework verifier key or explicit verifier/URL — simplified | Old Truffle per-explorer key aliases not automatically translated. |
| `DRY_RUN` / `dryRun` | Default simulation; explicit `--broadcast` — simplified | One convention for every wrapper and Safe proposal CLI; no environment alias. |

### Other legacy script/task options

| Old surface | Replacement / disposition | Reason |
| --- | --- | --- |
| `GOV_LIQUIDATION_PERIOD`, `GOV_PATRICIAN_PERIOD`, `TOGA_MIN_BOND_DURATION` | Fixed fresh chain PPP / seven-day TOGA bond; governance PPP set/clear separately — simplified | Bootstrap not an arbitrary policy bag; upgrades preserve deployed settings. |
| Deterministic `NONCE` | Nonce-zero vanity deployer — simplified | No arbitrary nonce branch; expected address/code checks remain. |
| `DETERMINISTIC_DEPLOYER_PK`, `CFAFWD_DEPLOYER_PK`, `GDAFWD_DEPLOYER_PK`, `MACROFWD_DEPLOYER_PK` | Generic deterministic helper / distinct task keys — supported | Preserve deterministic identity, independent funder/admin `WALLET_NAME`. |
| Deterministic `GAS_PRICE`, `GAS_LIMIT`, `EST_TX_COST` | Auto-estimation, optional `GAS_LIMIT`, `MAX_FEE_PER_GAS`, `MAX_PRIORITY_FEE_PER_GAS`, `EST_TX_COST` — simplified | EIP-1559 funding/fee overrides replace legacy gas-price calculation. |
| `VERIFIERS`, `SKIP_VERIFY` | Forwarder verifier selection/skip; framework `--verifier`/`--verifier-url` — simplified | No Truffle verification plugin; simulation skips explorer verification. |
| `RESET_TOKEN`, `resetToken` | Existing state read + deliberate `ALLOW_UPDATE=1` for resolver replacement — simplified | No implicit wrapper replacement/logic upgrade. |
| `NATIVE_TOKEN_SYMBOL` | Explicit native helper `NAME SYMBOL` — simplified | No implicit network-symbol deployment branch. |
| `REGISTRATION_KEY`, missing expiration | `gov-action setAppRegistrationKey DEPLOYER [EXPIRATION] [KEY]` — supported | `k1` and uint64-max defaults preserved; SimpleACL is separate. |
| Token `SUPER_TOKEN_LOGIC` / `superTokenLogic`, `EXTRA_PAST_SUPER_TOKEN_LOGICS` | Current canonical factory logic only — retired | No arbitrary logic selection/history filtering inside upgrade command. |
| Token `BATCH_SIZE`, `MAX_ITEMS`, `SKIP_ITEMS` | Operator-reviewed explicit bounded arrays — retired | No hidden discovery/pagination/batch selection. |
| `skipTokensFile`, documented `SKIP_TOKENS_FILE` but actual `SKIP_OUTPUT_FILE`, token `outputFile`/`OUTPUT_FILE` | Reviewed arrays, native/Safe artifacts — retired | Do not reproduce old naming bug or file-driven discovery state. |
| Address report `skipTokens`/`SKIP_TOKENS`, `OUTPUT_FILE` | `--skip-tokens`; capture JSON stdout explicitly — simplified | No sourced env output; release and target are explicit. |
| `TESTENV_SNAPSHOT_VARS`, comma-separated fixture token symbols | Dedicated local deployer/test snapshot APIs — devchain | No production filesystem snapshot contract; persistent faucet is explicit. |
| Old `npx truffle exec ... : ARGS`, callback argv/options | Named bash/Node/Foundry commands — retired | No colon separator, global mutation, programmatic compatibility alias. |

## Consolidation in this PR

- `gov-safe-add-owner.ts` was a duplicate implementation; use `gov-safe-add-owner.sh`. Safe SDK use stays in `safe-ops.ts`.
- The two ACL grant wrappers and duplicate task/Solidity macro-role implementation became `acl-grant-role.sh NETWORK ROLE GRANTEE`.
- Forwarder entry points share `new-ops-scripts/lib/forwarders.json`; phase is positional for all five entry points.
- Solidity action parameters use typed `--sig` arguments; there is no action-specific environment API.
- Obsolete deployment override guards and version-string helpers were removed rather than retained as shims.
- Live fork tests are opt-in (`yarn deployment-forks`); local-Anvil recovery runs automatically in contracts CI.

## Known external consumers (2026-11-10 discovery)

Indexed public GitHub research was not exhaustive: a broad query hit its result
cap, and private/unindexed usage was unobservable. These consumers need their own
dependency/import migration before using contracts 1.16.0; this PR does not modify them.

| Evidence | Required migration |
| --- | --- |
| [superfluid-sentinel](https://github.com/superfluid-org/superfluid-sentinel/blob/06fae457c42914bcf813916a90a6c004d152965d/src/web3client/contracts.js#L1) | Replace flat resolver/host/token/governance/agreement/BatchLiquidator/TOGA/pool artifact imports with qualified Hardhat `.abi` imports. Web3 itself can remain. |
| [kasparkallas/superapi](https://github.com/kasparkallas/superapi/blob/42d7946f3e07b8e9d53a6eccd2e37d4f461cb00e/wagmi.config.ts) | Replace flat SuperfluidPool artifact path; bundled ABI stays supported. |
| [d10r/gda-activity](https://github.com/d10r/gda-activity/blob/034839d30b431f8cdb5f761b7b0e6ba88b02089a/app.js) | Migrate GDAv1Forwarder, IGeneralDistributionAgreementV1, ISuperfluidPool and TestToken paths. |
| [d10r/sf-macro-forwarder-demo](https://github.com/d10r/sf-macro-forwarder-demo/blob/4f9eaa81bc0ca8af390a84641538e6b727c2325a/app.js) | Review stale MacroForwarder contract identity as well as artifact paths; do not silently substitute another forwarder. |
| [Philotheephilix/computepool](https://github.com/Philotheephilix/computepool/blob/902de50d167bb2df0de2f079f1aff0d3ce96de1d/scripts/finish_superfluid_demo.py) | Update Python artifact-directory/schema assumptions. Installed package version/runtime was unknown. |

