# Auto Wrap

Auto Wrap is an automated token wrapping system that automatically wraps ERC20 tokens to Super Tokens just in time to keep your streams running.

When your Super Token balance reaches a certain lower threshold, Auto Wrap steps in and wraps enough tokens into the needed Super Token on your behalf to ensure you never run out of balance, as that would make all streams stop.

## Getting Started

### Prerequisites

- Auto Wrap uses [Foundry](https://github.com/gakonst/foundry#installation) as the development framework.
- [Yarn](https://github.com/yarnpkg/yarn) is used as the package manager.
- [Hardhat v2](https://v2.hardhat.org/) is used for deployment

### Environment Variables

- Use .env-example as a template for your .env file

```bash
# .env-example

PRIVATE_KEY=

POLYGON_PRIVATE_KEY=
BSC_PRIVATE_KEY=

ETHERSCAN_API_V2_KEY=
```

#### Run tests

```bash
forge test --vvv
```

#### Deploy

Create a `.env` file using example above and run:

Deployment script will deploy all contracts and verify them on Etherscan.
Deploy script also calls `addStrategy` task to add the strategy to the Scheduler.

```bash
npx hardhat deploy --network <network>
```

The deploy script effectively burns the owner keys by calling `renounceOwnership()` on both contracts after deployment.

#### Deployed Contracts

See [metadata/networks.json](../../metadata/networks.json)
