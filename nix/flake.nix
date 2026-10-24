{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    git-pr-sync = {
      url = "github:palekiwi-labs/git-pr-sync";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cue-platform = {
      url = "git+file:///home/pl/code/palekiwi-labs/cue-platform?ref=dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.follows = "cue-platform/llm-agents";
  };

  outputs = { nixpkgs, flake-utils, llm-agents, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        envVars = import ./env.nix { inherit pkgs; };
        agents = llm-agents.packages.${system};
      in
      {
        devShells.default = pkgs.mkShell (envVars // {
          name = "cast-default";
          buildInputs = (with pkgs; [
            ast-grep
            curl
            fd
            go-task
            nushell
            python3
            ripgrep
            tree
            tree-sitter
          ]) ++ [
            inputs.cue-platform.packages.${system}.default
            (import ./agent-browser.nix {
              inherit pkgs;
              inherit (agents) agent-browser;
            })
            inputs.git-pr-sync.packages.${system}.git-pr-sync
            agents.claude-code
          ];
          shellHook = ''
            export TZ="Asia/Taipei";
            export TZDIR="${pkgs.tzdata}/share/zoneinfo";

            export GH_TOKEN=$GH_TOKEN_READONLY
            export JIRA_TOKEN=$JIRA_TOKEN_READONLY
            export ATLASSIAN_CLI_TOKEN_SPABREAKS=$JIRA_TOKEN_READONLY
            export ATLASSIAN_CLI_CONFIG_DIR="$HOME/.config/cast/nix/atlassian-cli"
            export GEMINI_API_KEY=$GOOGLE_GENERATIVE_AI_API_KEY
            export ZAI_API_KEY=$ZAI_CODING_PLAN_API_KEY

            export CUE_STORE="$HOME/cue"

            echo "CAST Default Nix Environment Loaded" >&2
          '';
        });
      }
    );
}
