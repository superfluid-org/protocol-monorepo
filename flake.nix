{
  description = "Overlay for working with Superfluid protocol monorepo";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    foundry = {
      url = "github:shazow/foundry.nix/stable";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    solc = {
      url = "github:hellwolf/solc.nix";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mk-cache-key = {
      url = "github:hellwolf/mk-cache-key.nix/master";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, foundry, solc, mk-cache-key } :
  flake-utils.lib.eachDefaultSystem (system:
  let
    minDevSolcVer = "solc_0_8_11"; # minimum solidity version used for external development
    solcVer = "solc_0_8_26";
    ghcVer92 = "ghc928";
    ghcVer94 = "ghc948";

    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        foundry.overlay
        solc.overlay
      ];
    };

    mk-cache-key-pkg = mk-cache-key.packages.${system}.default;

    # ghc ecosystem
    ghc = pkgs.haskell.compiler.${ghcVer94};
    ghcPkgs = pkgs.haskell.packages.${ghcVer94};

    # common dev inputs
    commonDevInputs = with pkgs; [
      mk-cache-key-pkg
      gnumake
      # for shell script linting
      shellcheck
      # used by some scripts
      jq
      yq
      # test utilities
      lcov
      actionlint
      git
    ];

    # solidity dev inputs
    ethDevInputs = with pkgs; [
      foundry-bin
      pkgs.${minDevSolcVer}
      pkgs.${solcVer}
      (solc.mkDefault pkgs pkgs.${solcVer})
    ];

    # nodejs ecosystem
    nodeDevInputsWith = nodejs: [
      nodejs
      nodejs.pkgs.yarn
      nodejs.pkgs.nodemon
    ];
    node18DevInputs = nodeDevInputsWith pkgs.nodejs_18;
    node20DevInputs = nodeDevInputsWith pkgs.nodejs_20;
    node22DevInputs = nodeDevInputsWith pkgs.nodejs_22;
    defaultNodeDevInputs = node22DevInputs;

    # CI inputs
    ciInputs = with pkgs; [
      # codecov requries gnupg binary
      gnupg
    ];

    # minimem development shell
    minimumDevInputs = commonDevInputs ++ ethDevInputs ++ defaultNodeDevInputs;

    # additional tooling for whitehat hackers
    whitehatInputs = with pkgs; [
      slither-analyzer
      echidna
    ];

    # spec developing specification
    specInputs = with pkgs; [
      # for nodejs ecosystem
      yarn
      gnumake
      # for haskell spec
      cabal-install
      ghc
      hlint
      stylish-haskell
      # sage math
      sage
      # testing tooling
      gnuplot
      # yellowpaper pipeline tooling
      ghcPkgs.lhs2tex
      python312Packages.pygments
      (texlive.combine {
        inherit (texlive)
        scheme-basic metafont
        collection-latex collection-latexextra
        collection-bibtexextra collection-mathscience
        collection-fontsrecommended collection-fontsextra;
      })
    ];

    # mkShell wrapper, to expose additional environment variables
    mkShell = o : pkgs.mkShell ({
      SOLC = pkgs.lib.getExe pkgs.${solcVer};
      FOUNDRY_OFFLINE = "true";
      FOUNDRY_SOLC_VERSION = pkgs.lib.getExe pkgs.${solcVer};
    } // o);
    mkShellForNodeCI = nodeDevInputs : mkShell {
      buildInputs = ciInputs ++ commonDevInputs ++ ethDevInputs ++ nodeDevInputs;
    };
    mkShellForSpecCI = ghcVer : mkShell {
      buildInputs = with pkgs; [
        cabal-install
        haskell.compiler.${ghcVer}
        hlint
      ];
    };
  in {
    # local development shells
    devShells.default = mkShell {
      buildInputs = minimumDevInputs;
    };
    devShells.whitehat = mkShell {
      buildInputs = minimumDevInputs
        ++ whitehatInputs;
    };
    devShells.spec = mkShell {
      buildInputs = minimumDevInputs
        ++ specInputs;
    };
    devShells.full = mkShell {
      buildInputs = minimumDevInputs
        ++ whitehatInputs
        ++ specInputs;
    };

    # CI shells
    devShells.mk-cache-key = mkShell {
      buildInputs = [ mk-cache-key-pkg ];
    };

    devShells.ci-minimum = mkShell {
      buildInputs = with pkgs; ciInputs ++ [ actionlint shellcheck ];
    };

    devShells.ci-default = mkShellForNodeCI defaultNodeDevInputs;
    devShells.ci-node18 = mkShellForNodeCI node18DevInputs;
    devShells.ci-node20 = mkShellForNodeCI node20DevInputs;
    devShells.ci-node22 = mkShellForNodeCI node22DevInputs;

    devShells.ci-spec-ghc92 = mkShellForSpecCI ghcVer92;
    devShells.ci-spec-ghc94 = mkShellForSpecCI ghcVer94;

    devShells.ci-hot-fuzz = mkShell {
      buildInputs = with pkgs; ciInputs ++ commonDevInputs ++ ethDevInputs ++ [
        slither-analyzer
        echidna
      ];
    };
  });
}
