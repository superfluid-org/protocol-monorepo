{
  halfBoardModule = {
    dependencies = [ ../ethereum-contracts ];
    outputs = [
      "autowrap/out"
      "scheduler/out"
    ];
    includedFiles = [
      # autowrap
      ./autowrap/foundry.toml
      ./autowrap/package.json
      ./autowrap/contracts
      ./autowrap/test
      ./autowrap/script
      ./autowrap/.solhint.json
      # scheduler
      ./scheduler/foundry.toml
      ./scheduler/package.json
      ./scheduler/contracts
      ./scheduler/test
      ./scheduler/.solhint.json
    ];
  };
}
