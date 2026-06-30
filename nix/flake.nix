{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    cue.url = "github:palekiwi-labs/cue";
    cast.url = "github:palekiwi-labs/cast";
    nvf.url = "github:NotAShelf/nvf";
  };

  outputs = { nixpkgs, flake-utils, nvf, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        customNeovim = import ./nvim.nix { inherit pkgs nvf; };
        envVars = import ./env.nix { inherit pkgs; };
      in
      {
        devShells.default = pkgs.mkShell (envVars // {
          name = "cast-default";
          buildInputs = with pkgs; [
            ast-grep
            curl
            customNeovim
            fd
            gh
            jq
            ripgrep
            tree
            tree-sitter

            inputs.cue.packages.${system}.cue
            inputs.cast.packages.${system}.cast-mcp-client
          ];

          shellHook = ''
            export TZ="Asia/Taipei";
            export TZDIR="${pkgs.tzdata}/share/zoneinfo";

            echo "CAST Global Nix Environment Loaded" >&2
          '';
        });
      }
    );
}
