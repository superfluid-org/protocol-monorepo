<h1 align="center">Welcome to Superfluid Hot Fuzz 👋
</h1>
<div align="center">
<img  width="300" padding="0 0 10px" alt="Superfluid logo" src="https://github.com/superfluid-finance/protocol-monorepo/raw/dev/sf-logo.png" />
</div>

> Testing Superfluid protocol and Super Apps like Simon Pegg.

<center>
    <img src="hot-fuzz-simon.jpg" width="61.803%" />
</center>

Hot-fuzz is a wrapper of [Echidna](https://github.com/crytic/echidna/) with additional helper for fuzzing
your Superfluid smart contracts applications, including [Super Apps](https://docs.superfluid.finance/superfluid/protocol-developers/super-apps).

How To Use
==========

## Setup

1. Download the latest echidna binary from: https://github.com/crytic/echidna/releases

2. Add `@superfluid-finance/hot-fuzz` to your project `devDependencies`.

`hot-fuzz` does not have a package yet, you should install it through:

```
yarn add --dev 'https://gitpkg.now.sh/api/pkg?url=superfluid-finance/protocol-monorepo/packages/hot-fuzz&commit=dev'
```

> Check out how this works:
>
> - https://github.com/yarnpkg/yarn/issues/4725
> - https://gitpkg.vercel.app/

Also make sure the dependency `@superfluid-finance/ethereum-contracts` is from the latest dev branch, since it is still
under active development.

3. Make sure you use foundry and configure it properly:

(TODO.)

> :warning: there is no truffle or hardhat support at the moment

:star: Congrats! Now you should be all set!

## Develop A New Hot Fuzzer

1. Create a new hot fuzz contract inheriting `HotFuzzBase`.
```solidity
contract YouSuperAppHotFuzz is HotFuzzBase {

    YourApp immutable private _app;

    constructor() HotFuzzBase(10 /* nTesters */ ) {
        // ... setup your app
        _app = new YourApp(sf.host, sf.cfa, superToken);
        _initTesters();
        ...
        _addAccount(address(_app));
    }
```
As a convention, the contract file name should be `YourApp.hott.sol`.

2. Create an Echidna yaml configuration file with at least this content:
```
testMode: "property"
```
Check the [Echidna documentation](https://github.com/crytic/echidna/) for more configuration options.

3. Write a list of possible actions how the testers can interact with your app, for example:
```
function participateLottery(uint8 a, int64 flowRate) public {
    LotteryPlayer player = getOnePlayer(a);
    require(flowRate >= _app.MINIMUM_FLOW_RATE());

    player.play(flowRate);
}
```
When run, Echidna will call this functions with random values set for its parameters.

4. Write additional [Echidna invariants](https://github.com/crytic/echidna#writing-invariants) which need to be true at all times, regardless of the order and parametrization of actions during the fuzzing.
A typical invariant for Super Apps is that you don't want your App jailed:
```
function echidna_app_is_free() public view returns (bool) {
    return sf.host.isApp(_app) && !sf.host.isAppJailed(_app);
}
```

> :bulb: Checkout the [flowlottery example](https://github.com/superfluid-finance/protocol-monorepo/tree/dev/examples/archive/flowlottery/solidity-contracts) and the [tradeable cashflow example](https://github.com/superfluid-finance/protocol-monorepo/tree/dev/examples/tradeable-cashflow/tradeable-cashflow-truffle).

## Hot Fuzz It

```
$ npx hot-fuzz contracts/YourAppHotFuzz.yaml
```

Once it is running, what is going on is that your list of actions in addition to a preset of actions defined in
`HotFuzzBase` are randomized as many sequences of instructions as you configured for, are being executed.

While executing these sequences of instructions, all echidna invariants are checked each time a transaction is made.
Any violation of these invariants is considered a bug somewhere in the app.

That's it, let the tool discover cases for you, have fun hot-fuzzing!

Contribution ✨
===============

The tool is still in early development, there may be breaking changes.

All contributions are welcome through new issue reports or pull requests.

Let's make smart contracts development safer by testing more.
