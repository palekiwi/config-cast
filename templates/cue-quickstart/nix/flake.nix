{
  description = "Cast devshell with cue";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    cue = {
      url = "github:palekiwi-labs/cue";
    };
    cue-plugins = {
      url = "github:palekiwi-labs/cue-plugins";
    };
  };

  outputs = { nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "cast-cue";
          buildInputs = [
            inputs.cue.packages.${system}.cue
          ];

          shellHook = ''
            export CUE_PLUGINS_PATH="${inputs.cue-plugins}"
            export OPENCODE_CONFIG="$HOME/.config/cast/nix/opencode.json"

            echo "Cast Cue Environment Loaded" >&2
          '';
        };
      }
    );
}
