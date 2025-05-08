{
  halfBoardModule = {
    dependencies = [
      ../..
      ../ethereum-contracts
    ];
    outputs = [
      "dist"
      "coverage"
    ];
    includedFiles = [
      # source code
      ./tasks
      ./src
      ./test
      ./previous-versions-testing
      ./scripts
      # configurations
      ./package.json
      ./hardhat.config.ts
      ./subgraph-codegen.yml
      ./tsconfig.json
      ./tsconfig.module.json
      ./tsconfig.test.json
      ./tsconfig.typechain.json
      ./typedoc.js
    ];
  };
}
