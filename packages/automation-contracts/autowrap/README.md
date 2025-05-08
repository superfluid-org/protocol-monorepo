# Auto Wrap

Auto Wrap is an automated token wrapping system that automatically wraps ERC20 tokens to Super Tokens just in time to keep your streams running.

When your Super Token balance reaches a certain lower threshold, Auto Wrap steps in and wraps enough tokens into the needed Super Token on your behalf to ensure you never run out of balance, as that would make all streams stop.

## Getting Started

### Prerequisites

- Auto Wrap uses [Foundry](https://github.com/gakonst/foundry#installation) as the development framework.
- [Yarn](https://github.com/yarnpkg/yarn) is used as the package manager.

### Environment Variables

- Use .env-example as a template for your .env file

```bash
# .env-example

PRIVATE_KEY=

POLYGON_PRIVATE_KEY=
BSC_PRIVATE_KEY=

ETHERSCAN_API_KEY=
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

#### Task - Add Approved Strategies to Manager contract

If you need to add strategies to the Scheduler, you can use the `addStrategy` task.

```bash
npx hardhat addStrategy --manager <manager_address> --strategy <strategy_address> --network <network>
```


#### Deployed Contracts

#### Testnets
|          | Manager                                                                                                                              | WrapStrategy                                                                                                                         |
|----------|--------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| OP Sepolia   | [0xe567b32C10B0dB72d9490eB1B9A409C5ADed192C](https://sepolia-optimism.etherscan.io/address/0xe567b32C10B0dB72d9490eB1B9A409C5ADed192C) | [0xf232f1fd34CE12e24F4391865c2D6E374D2C34d9](https://sepolia-optimism.etherscan.io/address/0xf232f1fd34CE12e24F4391865c2D6E374D2C34d9) |

#### Mainnets

|         | Manager                                                                                                                        | WrapStrategy                                                                                                                  |
|---------|--------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Polygon | [0x2581c27E7f6D6AF452E63fCe884EDE3EDd716b32](https://polygonscan.com/address/0x2581c27E7f6D6AF452E63fCe884EDE3EDd716b32#code)  | [0xb4afa36BAd8c76976Dc77a21c9Ad711EF720eE4b](https://polygonscan.com/address/0xb4afa36BAd8c76976Dc77a21c9Ad711EF720eE4b#code) |
| BSC     | [0x2AcdD61ac1EFFe1535109449c31889bdE8d7f325](https://bscscan.com/address/0x2AcdD61ac1EFFe1535109449c31889bdE8d7f325#code)      | [0x9e308cb079ae130790F604b1030cDf386670f199](https://bscscan.com/address/0x9e308cb079ae130790F604b1030cDf386670f199#code)     |

