{
  halfBoardModule = {
    dependencies = [ ../ethereum-contracts];
    outputs = [
      "build"
      "crytic-export"
    ];
    includedFiles = [
      ./package.json
      ./foundry.toml
      ./contracts
      ./scripts
      ./hot-fuzz
      ./Makefile
    ];
  };
}
