## SuperToken Deployer

This is a single-file Dapp for deploying SuperToken wrappers of existing ERC20 tokens.
Requires a browser with injected web3 provider (e.g. Metamask) and a local webserver.
If you have python installed, you can start a webserver with the document root set to the current directory with
```python
python -m SimpleHTTPServer 1337
```
Then navigate to http://localhost:1337/supertoken-deployer.html

Alternatively, [you can also find it on IPFS](https://cloudflare-ipfs.com/ipns/k2k4r8mh72qtu8510x7okj8c78nijugxr53edj7nxs8yecqy7zlyh4rz/supertoken-deployer.html)

## Stream Closer

This is a single-file Dapp for closing streams / deleting flows.
The flow parameters _token_, _sender_ and _receiver_ can be set either in the UI or provided as URL parameters.
If you have python installed, you can start a webserver with the document root set to the current directory with
```python
python -m SimpleHTTPServer 1337
```

Then navigate to http://localhost:1337/stream-closer.html

Alternatively, [you can also find it on IPFS](https://cloudflare-ipfs.com/ipns/k2k4r8mh72qtu8510x7okj8c78nijugxr53edj7nxs8yecqy7zlyh4rz/stream-closer.html)

In order to set the parameter in the URL, use this format:
stream-closer.html?chainId=<chainId>&token=<tokenAddress>&sender=<senderAddress>&receiver=<receiverAddress>

### Optimism L1 Stream Closer

For Optimism, there's a dedicated Dapp at `optimism-l1-stream-closer.html` which transacts directly to L1, providing a mechanism not dependent on the centralized sequencer.
For more details for how this works, see [the Optimism docs](https://github.com/ethereum-optimism/optimism/blob/develop/specs/deposits.md).

It can be used the same way as the conventional Stream Closer. [IPFS link](https://cloudflare-ipfs.com/ipns/k2k4r8mh72qtu8510x7okj8c78nijugxr53edj7nxs8yecqy7zlyh4rz/optimism-l1-stream-closer.html)

## MFA Tester

This is a single-file dApp for testing the MultiFlowTesterApp contract.

There are a few steps to complete to get everything up and running:
1. Open a terminal window and start a hardhat node instance: `npx hardhat node` in `packages/ethereum-contracts`
2. Open another terminal window and deploy contracts and token: `npx hardhat run dev-scripts/deployContractsAndToken.js` in `packages/ethereum-contracts`
3. Deploy MFA contract: `npx hardhat run dev-scripts/deploy-mfa.ts` in `packages/ethereum-contracts`
4. Build SDK-Core: `yarn build` in `packages/sdk-core` and copy `packages/sdk-core/dist/index.umd.js` into `packages/ethereum-contracts/utils/dist`.

> NOTE: There are hardcoded addresses for the resolver and MFA in mfa-tester.html, make sure that these addresses are in sync with what is deployed otherwise it won't work.

If you have python installed, you can start a webserver with the document root set to the current directory with
```python
python -m SimpleHTTPServer 1337
```
Then navigate to http://localhost:1337/mfa-tester.html
