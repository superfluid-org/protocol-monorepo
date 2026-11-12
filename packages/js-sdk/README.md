# Migrate from js-sdk to sdk-core

`@superfluid-finance/js-sdk` is retired from the monorepo's active workspaces,
builds, tests and package publication. Its implementation and tests are removed;
Git history retains them. Only this migration note and the original MIT license
remain here, not an archived runnable package.

This repository change does **not** deprecate or unpublish any npm release.
Previously published js-sdk versions depend on Truffle tooling and artifacts;
do not combine them with `@superfluid-finance/ethereum-contracts` 1.16.0, which
removes `build/truffle` and the Truffle configuration/runtime.

## Initialize sdk-core

Replace `new SuperfluidSDK.Framework({web3, isTruffle, version, ...})` followed
by `initialize()` with `Framework.create`. Install `@superfluid-finance/sdk-core`
and its peer dependencies (`ethers` v5 and `graphql`); remove js-sdk and any
application-owned Truffle dependencies once their remaining uses are migrated.

```js
const {Framework} = require("@superfluid-finance/sdk-core");
const {ethers} = require("ethers");

const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const {chainId} = await provider.getNetwork();
const sf = await Framework.create({
    chainId,
    provider,
    protocolReleaseVersion: "v1",
    // resolverAddress: "0x...", // required for custom/unsupported networks
});
const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
const token = await sf.loadSuperToken("fDAIx"); // or a SuperToken address
const operation = sf.cfaV1.createFlow({
    superToken: token.address,
    receiver: "0x...", // your receiver's address
    flowRate: "3858024691358", // token base units per second
});
const transaction = await operation.exec(signer);
const receipt = await transaction.wait();
```

Use a token that exists on the selected network; `fDAIx` is a testnet example.
The provider is for reads; pass an authorized signer explicitly to writes.
sdk-core still accepts Web3 providers and Web3 instances: existing Web3
applications need not rewrite their whole connection layer. Do not rely on
Hardhat injecting `global.web3`, `artifacts`, or Truffle accounts.

## API and data-model changes

| js-sdk | sdk-core replacement / migration action |
| --- | --- |
| `tokens`, `superTokens`, `loadToken` | `await sf.loadSuperToken(symbolOrAddress)` returns a token helper. Keep references explicitly rather than expecting mutable SDK token registries. |
| `createERC20Wrapper` | Call the deployed SuperTokenFactory's `createERC20Wrapper` with ethers/viem/Web3 using its Hardhat ABI, then load the created address with `sf.loadSuperToken`. sdk-core has no drop-in wrapper-deployment helper. |
| `cfa`, `ida` | `sf.cfaV1`, `sf.idaV1`; sdk-core also exposes `sf.gdaV1`. Reads and Operation-building writes are separate. IDA remains subject to each network's freeze policy. |
| `user(...)` convenience objects | Use explicit token/agreement helper methods with sender/receiver addresses and a signer; there is no drop-in User wrapper. |
| `batchCall` | Build Operations and pass them to `sf.batchCall(operations)`, then `.exec(signer)`. Review operation support rather than passing old encoded js-sdk batch tuples. |
| Truffle methods, `{from: ...}` | Use ethers contracts/token helpers; connect or pass a signer. An address alone cannot authorize a write. |
| Truffle receipts and decoded `logs` | Operation `.exec` returns an ethers transaction response; `await tx.wait()` returns a receipt. Decode logs with the relevant ethers Interface. |
| BN values / gas metering | Use sdk-core's documented string/ethers BigNumber values and convert explicitly; do not mix BN arithmetic with BigNumber. Legacy gas-report helpers have no supported equivalent. |
| Legacy event/subgraph helpers | Use sdk-core Query/subgraph APIs or ethers filters and `queryFilter`; review pagination and event result shapes. |
| Custom Truffle contract loader | No replacement compatibility layer. Instantiate ethers/viem/Web3 contracts from the supported Hardhat artifacts or bundled ABI. |

Handle sdk-core `SFError` categories and transaction errors explicitly; old
Truffle error strings and automatically decoded events are not compatibility
contracts. See [sdk-core documentation](../sdk-core/README.md) and its
[Framework API](../sdk-core/src/Framework.ts) for complete method signatures.

## Contracts 1.16.0 artifact paths

ABI-only consumers can change, for example:

```js
// Before: require("@superfluid-finance/ethereum-contracts/build/truffle/ISuperToken.json")
const {abi} = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/interfaces/superfluid/ISuperToken.sol/ISuperToken.json");
```

The bundled `build/bundled-abi.js` and `build/bundled-abi.json` exports retain
their names and shapes. Hardhat JSON provides ABI/bytecode, not Truffle
`networks`, `deployed()`, `at()`, receipt or library-linking abstractions. Read
addresses from deployment metadata, the resolver or onchain state and use
ethers, viem or Foundry for deployment/linking. Web3 contracts can still be
constructed from `.abi` without a Truffle dependency.
