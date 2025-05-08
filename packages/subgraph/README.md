<h1 align="center">Welcome to Superfluid Subgraph 👋
</h1>
<div align="center">
<img  width="300" padding="0 0 10px" alt="Superfluid logo" src="https://github.com/superfluid-finance/protocol-monorepo/raw/dev/sf-logo.png" />
<p>
  <a href="#" target="_blank">
    <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-yellow.svg" />
  </a>
  <a href="https://twitter.com/Superfluid_HQ/status/" target="_blank">
    <img alt="Twitter: Superfluid_HQ" src="https://img.shields.io/twitter/follow/Superfluid_HQ.svg?style=social" />
  </a>
</p>
</div>

> Official subgraph for the Superfluid Protocol

# 📖 Docs

Get started using the Subgraphs with an introduction and query examples:

https://docs.superfluid.finance/superfluid/docs/subgraph

# 🤓 Local development

🛑 **STOP - Do not pass Go** 🛑 You probably don't need this repo. If you need data for a supported Superfluid deployment, we already deployed them for you!
Head over to the **Docs** to get started.

In this section we will cover the following:

0. Deploy the subgraph to a `docker container`.
1. Deploy the Superfluid contracts to a local Hardhat node.
2. Check that your setup is correct by running some `tests`.

If you get stuck, see The Graph [docs](https://thegraph.com/docs/quick-start#local-development).

## Initial setup

First install these dependencies:

-   [docker](https://docs.docker.com/install/)
-   [docker compose](https://docs.docker.com/compose/install/)

Now install the necessary node packages with the following commands:

```bash
yarn install
```

### Hardhat node

Start hardhat node.

```bash
npx hardhat node --hostname 0.0.0.0
```

### Setting up a local Subgraph node instance

Run `docker compose up` in `packages/subgraph`. There is a `docker-compose.yml` file which sets up a local graph node container.

You should see logs start coming in on the same terminal window once everything is set up:

```
Listening on 0.0.0.0:8545
web3_clientVersion
net_version
eth_getBlockByNumber
eth_getBlockByNumber
```

If there is some connection issue between graph-node and your local hardhat node, it may be caused by docker network issues.

## Deploy the contracts

> Note: If you're returning from an earlier work session, skip down to [Testing](#testing).

Open another terminal window and navigate to `packages/ethereum-contracts` and run the build command - this compiles the ethereum contracts and creates the artifacts required in the next steps.

```bash
yarn build
```

Now go to `packages/ethereum-contracts` and run the following command to deploy contracts:

```bash
npx hardhat run dev-scripts/run-deploy-contracts-and-token.js
```

This deploys the SuperFluid framework and tokens to your local hardhat node.

Then you want to prepare the necessary files for testing using: `yarn prepare-local`.

The breakdown for the different commands which are encapsulated by the above command:

```bash
# Generate `subgraph.yaml` using the subgraph.template.yaml
yarn prepare-manifest-local

# Generate `addresses.ts` using the addresses.template.ts file
yarn set-network-local

# Get the ABIs
yarn getAbi

# Generate the SFMeta file (this is used internally to generate an internally used entity in prod, but still necessary for building/deploying the subgraph even for testing).
yarn generate-sf-meta-local

```

## Deploy the Subgraph

Once the contracts and token have been deployed, you can run the following one liner or go step by step and run through the commands below.

```bash
# To build and deploy the Subgraph in a single line:
yarn build-and-deploy-local

# Step by step breakdown
# Generate the subgraph schema
yarn codegen

# Create the namespace for the subgraph (only run once)
# This builds the subgraph as well
yarn create-local

# Deploy the subgraph
yarn deploy-local

> Deployed to http://localhost:8000/subgraphs/name/superfluid-test/graphql
```

> If you see "NetworkNotSupported" error, make sure the network name in your docker-compose matches the one in subgraph.yaml.
> Note: The network must be mainnet when testing locally.

Navigate to the url in the console output, and let's try a test query so we know the deployment worked. It should return an empty `flowUpdatedEvents` array.

```
{
  flowUpdatedEvents {
    id
  }
}
```

:tada: Congrats! In the next section we will show you how to run tests and redeploy the subgraph with a clean slate.

## Running Tests

To run the unit tests, you first need to build the ethereum-contracts, then you can run: `yarn matchstick`. This prepares the manifest file (`subgraph.yaml`), the networks file (`addresses.ts`), gets the abi files required to run `yarn codegen` and runs the tests.

You only need to do this the first time (unless you make changes in the contracts which impact the ABI or changes to `schema.graphql`).

## Re-deployments

To re-deploy the subgraph and contracts (for a clean slate), you need to kill the hardhat node and graph node processes (`ctrl + c` usually does it) and restart these and run through the previous steps again.

## Troubleshooting

### Docker

Sometimes docker container won't stop

`Cannot kill container d28... signaling init process caused "permission denied"`

Try running

```
sudo killall containerd-shim
```

### Subgraph

Another way to perform a sanity check is using a http query with the following:

| Property     | value                                                  |
| ------------ | ------------------------------------------------------ |
| URL          | `http://localhost:8000/subgraphs/name/superfluid-test` |
| Request type | POST                                                   |
| body         | GraphQL                                                |

```graphql
query {
    accounts(
        first: 1000
        where: { id_not: "0x0000000000000000000000000000000000000000" }
    ) {
        id
    }
}
```

You should get a response like this

```js
{
    "data": {
        "accounts": [
            {
                "balance": "0",
                "hat": null,
                "id": "0x0000000000000000000000000000000000000000"
            },
            {
                "balance": "90.001030003030003391",
                "hat": null,
                "id": "0xbf44e907c4b6583d2cd3d0a0c403403bb44c4a3c"
            },
            ...
        ]
    }
}
```

### Schema Overview

For the V1 Subgraph design, there are three "levels" of entities: event, higher order level (HOL) and aggregate. A brief explanation of each below:

## Event Entities

These entities are for the most part a 1-to-1 mapping with the raw events from the contract, however for some of them, we have added data, this is noted clearly in the `schema.graphql` file and will be viewable in the playground as well. These entities are created once and never updated.

## Higher Order Level Entities

The higher order level entities are an abstraction of the events is not ephemeral in the same way the event entities are. They contain data on an entity over its "lifetime" and therefore may be updated over time.

## Aggregate Entities

Aggregate entities are exactly what the name suggests - they are entities that store aggregate data. More specifically, we do this at an account-token level and also at a global token level.

### Test Structure
This section is intended for those who are interested in understanding the structure of our two test suites:

- Unit Tests which test the mapping logic and asserts that the properties on the entities are what is expected
- Integration Tests which ensure that a local blockchain and subgraph instance can index events via transactions and query the created entities.

#### Unit Tests
Our unit tests utilize [Matchstick](https://github.com/LimeChain/matchstick) to test our mapping logic.

We have helper files which create the mock events and the actual test files which contain the actual tests.

The tests look something like this:

- you create a mock event with the desired parameters for a specific entity
- you pass this event to its complementary event handler
- you assert that the values on the created entity in the graph store have been created

#### Integration Tests
The integration tests have been scaled down drastically and are no longer responsible for validating the mapping logic as this is handled in the unit tests. This solely serves to ensure that transactions executed against a local blockchain connected to a local subgraph instance will index events and create entities which can be retrieved by querying the exposed API endpoint from the local subgraph. At its core, we are testing the full lifecycle from transaction => event => indexed event => entity => entity is queryable. In addition, we still need these tests to ensure that new changes made to our schema won't break the SDK's query feature.

# Production

## Graph Network

Coming soon. Let The Graph team know you want Superfluid available on the Network >> https://discord.gg/7eXTnPKYV4

## Hosted Service

Log in to the explorer at https://thegraph.com/explorer/. Then go to your dashboard. IMPORTANT: select the Superfluid-Finance account- don't use your your personal account. Copy the auth token to use in this command:

```
graph auth https://api.thegraph.com/deploy/ <ACCESS_TOKEN>
```

If the subgraph has not been created yet, you must create it first using the dashboard.

## Release Process

-   Bump minor or patch version for the subgraph package: `yarn manage-versions && git commit packages/subgraph/package.json`.
-   Select the appropriate Subgraph LTS branch: `release-subgraph-v1`.
-   Merge `origin/dev` to the LTS branch.
-   Create a new release in github.

## Developer Notes

When adding new networks, we must do the following:

-   NOTE: The `network` field in the `/config/*.json` file must match the official naming of the network name from the [subgraph docs](https://thegraph.com/docs/developer/create-subgraph-hosted#supported-networks). This name can deviate from the name of the file itself. e.g. `avalanche-c.json` must have field: `"network": "avalanche"`.
-   Add a new file to `./config`, the name of the file should be derived from the canonical network name in `packages/ethereum-contracts/truffle-config.js`. e.g. adding network `avalanche-c` to the array in `./hosted-service-networks.json` and then adding `avalanche-c.json` to `/config`. The name of the network specific file in `/config` will dictate our subgraph endpoint, e.g. `protocol-dev-avalanche-c`.
-   We also need to add the host and resolver addresses to the `addresses.template.ts` file. NOTE: the `network` we are comparing in the `addresses.template.test` file should match the `"network"` field in `/config/*.json`.

# Contributing

Contributions, suggestions, and issues are welcome. At the moment, there are no strict guidelines to follow.
