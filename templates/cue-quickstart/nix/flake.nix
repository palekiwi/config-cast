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
            export OPENCODE_CONFIG_CONTENT='{
              "$schema": "https://opencode.ai/config.json",
              "plugin": [
                "{env:CUE_PLUGINS_PATH}/src/opencode/cue-add.ts",
                "{env:CUE_PLUGINS_PATH}/src/opencode/cue-log.ts",
                "{env:CUE_PLUGINS_PATH}/src/opencode/cue-plan.ts",
                "{env:CUE_PLUGINS_PATH}/src/opencode/cue-task.ts",
                "{env:CUE_PLUGINS_PATH}/src/opencode/cue-todo.ts"
              ],
              "skills": {
                "paths": ["{env:CUE_PLUGINS_PATH}/skills/"]
              },
              "permission": {
                "bash": {
                  "cue *": "allow"
                },
                "cue-add": "allow",
                "cue-log": "allow",
                "cue-plan": "allow",
                "cue-task": "allow",
                "cue-todo": "allow",
                "todowrite": "deny"
              }
            }'

            if [ ! -d "$CUE_PLUGINS_PATH/node_modules/@opencode-ai/plugin" ]; then
              echo "ERROR: cue-plugins not installed. Run:" >&2
              echo "  git clone git@github.com:palekiwi-labs/cue-plugins.git $CUE_PLUGINS_PATH" >&2
              echo "  nix develop $CUE_PLUGINS_PATH -c bun install --cwd $CUE_PLUGINS_PATH" >&2
              return 1 2>/dev/null || exit 1
            fi

            echo "Cast Cue Environment Loaded" >&2
          '';
        };
      }
    );
}
