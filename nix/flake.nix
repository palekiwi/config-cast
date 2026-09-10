{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    cue = {
      url = "github:palekiwi-labs/cue/data-model-spike";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pre-central-store cue, exposed as `cue-legacy` so the nine legacy
    # `.cue/` stores stay readable while the plugins, skills and prompts
    # migrate one at a time. Pinned to an exact rev so it cannot drift.
    # Removed at cutover.
    cue-legacy = {
      url =
        "github:palekiwi-labs/cue/6748aa3a8a4386fbff90d7aea63443aeb2bfcee7";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-pr-sync = {
      url = "github:palekiwi-labs/git-pr-sync";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cast = {
      url = "github:palekiwi-labs/cast/v0.2.0-rc.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

        # Both cue generations ship during the migration. Only the spike
        # build owns the `cue` name; the legacy build is renamed rather
        # than added directly, since both provide `bin/cue`.
        cuePkgs = [
          inputs.cue.packages.${system}.cue
          (pkgs.writeShellScriptBin "cue-legacy" ''
            exec ${inputs.cue-legacy.packages.${system}.cue}/bin/cue "$@"
          '')
        ];

        # Shared tooling available in every cast shell.
        commonInputs = (with pkgs; [
          ast-grep
          curl
          customNeovim
          fd
          gh
          go-task
          herdr
          jq
          python3
          ripgrep
          tree
          tree-sitter
        ]) ++ cuePkgs ++ [
          inputs.git-pr-sync.packages.${system}.git-pr-sync
          inputs.cast.packages.${system}.cast-mcp-client
        ];

        commonShellHook = ''
          export TZ="Asia/Taipei";
          export TZDIR="${pkgs.tzdata}/share/zoneinfo";

          export GH_TOKEN=$GH_TOKEN_READONLY
          export GEMINI_API_KEY=$GOOGLE_GENERATIVE_AI_API_KEY
          export ZAI_API_KEY=$ZAI_CODING_PLAN_API_KEY

          # Central cue store. Required rather than convenient: a sandbox
          # does not reproduce the host home layout, so the default
          # (~/cue) is not safe to rely on here.
          export CUE_STORE="$HOME/cue"

          echo "CAST Default Nix Environment Loaded" >&2
        '';
      in
      {
        devShells = {
          default = pkgs.mkShell (envVars // {
            name = "cast-default";
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
