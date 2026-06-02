{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    mem.url = "github:palekiwi-labs/mem/8f190c989743ead53009b3e610cfd791a04555b0";
    cast.url = "github:palekiwi-labs/cast/dev";
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
            inputs.cast.packages.${system}.cast-mcp-client
          ];

          shellHook = ''
            # Wire up git configuration
            export GIT_CONFIG_COUNT=2
            export GIT_CONFIG_KEY_0="include.path"
            export GIT_CONFIG_VALUE_0="${./.gitconfig}"
            export GIT_CONFIG_KEY_1="core.excludesFile"
            export GIT_CONFIG_VALUE_1="${./.gitignore}"

            echo "CAST Global Nix Environment Loaded"

            export EDITOR=nvim

            export MEM_ARTIFACT_TYPES='["spec", "plan", "trace", "doc", "todo", "bin", "tmp", "ref"]'
            export MEM_IGNORED_TYPES='["tmp", "ref"]'
          '';
        };
      }
    );
}
