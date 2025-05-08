{
  halfBoardModule = {
    dependencies = [
      ../..
      ../solidity-semantic-money
    ];
    outputs = [
      "build"
      "coverage"
    ];
    includedFiles = [
      # source code
      ./tasks
      ./contracts
      ./dev-scripts
      ./test
      ./testsuites
      # configurations
      ./package.json
      ./truffle-config.js
      ./hardhat.config.ts
      ./foundry.toml
      ./tsconfig.json
      ./tsconfig.scripts.json
    ];
  };
}
