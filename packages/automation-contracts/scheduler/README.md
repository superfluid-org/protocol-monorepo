# Scheduler

Set of contracts that allow to schedule a Superfluid tasks related to be executed in the future.

## Flow Scheduler

If you have an intended end date and/or start date for a stream, instead of having to manually trigger the action, you could use the Stream Scheduler to automatically trigger the action at the desired time. This is especially useful in the case of streaming payroll, subscriptions and token vesting.

## Vesting Scheduler

The Vesting Scheduler allows you to schedule the vesting of tokens to a receiver account. The Vesting Scheduler does not hold the tokens, rather it simply uses permissions to move them for you.

## Getting Started

### Prerequisites

- Scheduler uses [Foundry](https://github.com/gakonst/foundry#installation) as the development framework.
- [Yarn](https://github.com/yarnpkg/yarn) is used as the package manager.

### Environment Variables

- Use `.env-example` as a template for your .env file

```bash
# .env-example

POLYGON_PRIVATE_KEY=
BSC_PRIVATE_KEY=

POLYGON_URL=
BSC_URL=

ETHERSCAN_API_KEY=
```

#### Run tests

```bash
forge test --vvv
```

#### Deploy

Create a `.env` file using example above and run:

Deployment script will deploy all contracts and verify them on Etherscan.

```bash
npx hardhat deploy --network <network>
```

#### Deployed Contracts

Contract addresses can be found in https://explorer.superfluid.finance/protocol, with the data source being `networks.json` in the metadata package.
All current production deployments are based on the codebase found in version 1.2.0 of the scheduler package.

In package version 1.3.0 VestingScheduler (v1) was removed, as it's not gonna be used for new production deployments.
VestingSchedulerV2 and FlowScheduler were modified to use the SuperTokenV1Library instead of the deprecated CFAv1Library.
