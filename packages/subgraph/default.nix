{
  halfBoardModule = {
    dependencies = [
      ../ethereum-contracts
      ../sdk-core
    ];
    outputs = [
      "abi"
      "generate"
    ];
    includedFiles = [
      ./package.json
      ./config
      ./schema.graphql
      ./tsconfig.json
      ./types
      ./src
      ./scripts
      # for testing
      ./docker-compose.yml
      ./matchstick.yaml
      ./tests
      ./tasks
    ];
  };
}
