{
  description = "Cast devshell with cue";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    cue = {
      url = "github:palekiwi-labs/cue";
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
            export CUE_PLUGINS_PATH="$HOME/.config/opencode/plugin/palekiwi-labs/cue-plugins"
            export OPENCODE_CONFIG="$HOME/.config/cast/nix/opencode.json"

            if [ ! -d "$CUE_PLUGINS_PATH/node_modules/@opencode-ai/plugin" ]; then
              echo "ERROR: cue-plugins not installed. Run:" >&2
              echo "  git clone git@github.com:palekiwi-labs/cue-plugins.git $CUE_PLUGINS_PATH" >&2
              echo "  (cd $CUE_PLUGINS_PATH && bun install)" >&2
              return 1 2>/dev/null || exit 1
            fi

            echo "Cast Cue Environment Loaded" >&2
          '';
        };
      }
    );
}
