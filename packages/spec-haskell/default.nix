{
  halfBoardModule = {
    dependencies = [ ];
    outputs = [
      "dist-test"
      "dist-docs"
    ];
    includedFiles = [
      ../../flake.nix
      ../../flake.lock
      ./cabal.project
      ./all.ghc94.cabal.project.freeze
      ./Makefile
      ./pkgs
    ];
  };
}
