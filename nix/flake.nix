{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    mem.url = "github:palekiwi-labs/mem/f26675a35f592e561dbc4c61a4299c2b35af8db0";
    cast.url = "github:palekiwi-labs/cast/dev";
    nvf.url = "github:NotAShelf/nvf";
  };

  outputs = { nixpkgs, flake-utils, nvf, cast, ... }@inputs:
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
            inputs.cast.packages.${system}.cast-mcp-client
          ];

          shellHook = ''
            echo "CAST Global Nix Environment Loaded"

            export EDITOR=nvim
          '';
        };
      }
    );
}
