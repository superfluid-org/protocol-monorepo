{
  halfBoardModule = {
    includedFiles = [
      # development tooling defined in nix
      ./flake.nix
      ./flake.lock
      # managing the npm dependencies with yarna
      ./package.json
      ./.yarnrc
      ./yarn.lock
    ];
  };
}
