# Contributing

Interested in contributing, or just troubleshooting? Great! Let's get this party started.

Before interacting with the Superfluid community, please read and understand our [Code of Conduct](code_of_conduct.md).

## Local Development

### Setup Tooling

At minimum, you will need to have these available in your development environment:

- Yarn, sufficiently recent version, the actual yarn version is locked in `.yarnrc`.
- Node.js 18.x.

Additionally recommended:
- jq
- shellcheck

**More Options Using Nix**

The recommended way is to use the [nix package manager](https://nixos.org/download.html) to get a reproducible, declarative and reliable development environment.
The Nix shell provides a complete environment, with all tooling included.

After installing Nix, you may also need to add this to `nix.conf` (located in `.config/nix` in single-user installs and in `/etc/nix` in multi-user installs):
```
experimental-features = nix-command flakes
```

Development shells options are available as different devShells commands in ([nix flakes](https://nixos.wiki/wiki/Flakes) required):

- minimum, minimum development environment for building monorepo.
- whitehat, additional ethereum development toolings including slither, echidna, etc.
- spec, for developing of Superfluid haskell spec,
- full, everything included.

To use them:

- `nix develop .` or `npm run shell`
- `nix develop .#whitehat` or `npm run shell:whitehat`
- `nix develop .#spec` or `npm run shell:spec`
- `nix develop .#full` or `npm run shell:full`

### Installing Dependencies

Before you do anything, you should run `yarn install && yarn build` in the root directory of your local-copy of the protocol-monorepo to install and build the necessary dependencies.

```bash
cd protocol-monorepo
yarn install && yarn build
```

You'll also want to upgrade your Superfluid App to the canary, so you have the most recent changes.

```bash
cd superfluid-app # wherever your superfluid-app happens to be
yarn upgrade @superfluid-finance/ethereum-contracts@dev @superfluid-finance/sdk-core@dev
```

### Copy and Watch

Now you are ready. If you're editing the Superfluid contracts, start the auto-compiler:

```bash
cd packages/ethereum-contracts
npx truffle watch
```

Then, copy-and-watch the changes into your Superfluid App.

```bash
nodemon --watch ../path/to/superfluid/packages -ext js,ts,tsx,sol --exec rsync --archive --delete ../path/to/superfluid/packages ./node_modules/@superfluid-finance/
```

For example, if your Superfluid App and protocol-monorepo are located in the same directory:

```bash
📦projects
 ┣ 📂superfluid-app
 ┗ 📂protocol-monorepo
   ┗ 📂packages

cd superfluid-app
nodemon --watch ../protocol-monorepo/packages --ext js,ts,tsx,sol --exec rsync --archive --delete ../protocol-monorepo/packages/ ./node_modules/@superfluid-finance/
```

See our [examples repo](https://github.com/superfluid-finance/super-examples) if you want to see more examples of this method.

## Code Coverage

We are using `solidity-coverage`. Use this command to run the coverage tests in the contracts package:

```bash
truffle run test-coverage
```

> Note: This step is not integrated with the unit test because of the time it consumes to execute.

## Testing

See the individual packages for specific details on testing or run all the tests from the root `yarn test` (smart contract tests can run over an hour).

## Linting

We are using [eslint](https://eslint.org/) for Javascript, [solhint](https://protofire.github.io/solhint/) for Solidity and [shellcheck](https://www.shellcheck.net/) for shell scripts.

## Releases

### Master `@latest`

To publish a new version of Superfluid to NPM run the following command:

```bash
yarn lerna:version
```

Packages are versioned independently, so you can choose which packages to release, and commit only those changes. Now its time to publish:

```bash
scripts/publish-master.sh
```

There should already be a draft release created in Github for each package. Add in your changes and publish it.

### Canary `@dev`

Whenever anything is merged to `dev`, new packages are automatically published to our [Github packages](https://github.com/orgs/superfluid-finance/packages?repo_name=protocol-monorepo). A Github release should not be created.

Canary packages can be install using the `@dev` tag

```bash
yarn install @superfluid-finance/ethereum-contracts@dev

# or specify the version
yarn install @superfluid-finance/ethereum-contracts@0.2.4-dev.265
```

### Pull Request `@PRxxx`

Pull request packages are automatically published to our [Github packages](https://github.com/orgs/superfluid-finance/packages?repo_name=protocol-monorepo). A Github release should not be created.

See the bot message in the PR for how to install these packages.

## Known Local Development Issues

### `node-jq` error when Node.js is installed through Snap Store
#### Problem
Error message when running `yarn install`:
```
error /protocol-monorepo/node_modules/node-jq: Command failed.
Exit code: 243
Command: npm run install-binary
Arguments:
```
* [Relevant StackOverflow question](https://stackoverflow.com/questions/67475457/why-cant-i-just-run-npm-install-via-a-child-process-exec-call-npm-exit-243-wit)

## Signing Git commits
In order to protect us from impersonation attacks and prove that you were the author of a specific code change we require signed commits.

[GitHub - Signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)

## Git Submodule Workflow Helpers

Git submodule is required for external dependences such as `lib/forge-std`.

These workflow helpers are included for the ease of its learning curve:

- `yarn git:submodule:init`: a clean checkout the repo should always do this first.
  - Note that it is triggered as part of the [npm prepare life cycle script](https://docs.npmjs.com/cli/v6/using-npm/scripts).
    So you don't need to worry about it usually.
- `yarn git:submodule:update`: an updated code may require you to update the submodule too.
  This command help you to keep your code base and its submodules in sync with everyone else.
- `yarn git:submodule:sync`: should you want to sync with the upstream of the submodule, do this.
- `yarn git:submodule:deinit`: starting over, this should be the last resort for you to try to reset and resync things.

#### Solutions
* Use Nix (see section "Setup Tooling")
* Re-install Node.js through other means than Snap Store.
