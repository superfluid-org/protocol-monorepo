{
  halfBoardModule = {
    dependencies = [ ../.. ];
    outputs = [ "out" ];
    includedFiles = [
      ./package.json
      ./foundry.toml
      ./src
      ./test
      ./.solhint.json
      ./Makefile
    ];
  };
}
