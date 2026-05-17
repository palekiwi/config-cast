{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    mem.url = "github:palekiwi-labs/mem";
    nvf.url = "github:NotAShelf/nvf";
  };

  outputs = { nixpkgs, flake-utils, nvf, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        customNeovim = import ./nvim.nix { inherit pkgs nvf; };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "cast-default";
          buildInputs = with pkgs; [
            ast-grep
            fd
            gh
            jq
            ripgrep
            tree
            customNeovim

            inputs.mem.packages.${system}.default
          ];

          shellHook = ''
            echo "CAST Global Nix Environment Loaded"

            export EDITOR=nvim
          '';
        };
      }
    );
}
