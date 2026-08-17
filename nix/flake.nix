{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    cue.url = "github:palekiwi-labs/cue";
    cast.url = "github:palekiwi-labs/cast/2b25028b6cdcb4ff1a8d8dbb1624276fb2656a8d";
    nvf.url = "github:NotAShelf/nvf";
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, flake-utils, nvf, llm-agents, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        customNeovim = import ./nvim.nix { inherit pkgs nvf; };
        envVars = import ./env.nix { inherit pkgs; };
        agents = llm-agents.packages.${system};

        # Shared tooling available in every cast shell.
        commonInputs = with pkgs; [
          ast-grep
          curl
          customNeovim
          fd
          gh
          go-task
          jq
          ripgrep
          tree
          tree-sitter

          inputs.cue.packages.${system}.cue
          inputs.cast.packages.${system}.cast-agent
          inputs.cast.packages.${system}.cast-mcp-client
        ];

        commonShellHook = ''
          export TZ="Asia/Taipei";
          export TZDIR="${pkgs.tzdata}/share/zoneinfo";

          export GH_TOKEN=$GH_TOKEN_READONLY
          export GEMINI_API_KEY=$GOOGLE_GENERATIVE_AI_API_KEY
          export ZAI_API_KEY=$ZAI_CODING_PLAN_API_KEY

          echo "CAST Global Nix Environment Loaded" >&2
        '';
      in
      {
        devShells = {
          default = pkgs.mkShell (envVars // {
            name = "cast-default";
            buildInputs = commonInputs;
            shellHook = commonShellHook;
          });

          opencode = pkgs.mkShell (envVars // {
            name = "cast-opencode";
            buildInputs = commonInputs ++ [
              agents.opencode
            ];
            shellHook = commonShellHook;
          });

          # Universal shell exposing every harness in one environment.
          # Selected via `global_shell = "universal"` in cast.json.
          universal = pkgs.mkShell (envVars // {
            name = "cast-universal";
            buildInputs = commonInputs ++ [
              agents.opencode
              agents.pi
              agents.claude-code
            ];
            shellHook = commonShellHook;
          });
        };
      }
    );
}
