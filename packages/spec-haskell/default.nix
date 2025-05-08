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
      ./cabal.project.freeze
      ./Makefile
      ./pkgs
    ];
  };
}
