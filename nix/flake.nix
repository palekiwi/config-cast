{
  description = "Global CAST development environment";

  # Declare the numtide binary cache so prebuilt harness packages are fetched
  # rather than built from source. cast's dev container enables
  # `accept-flake-config = true`, so these are honoured non-interactively.
  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "cache.numtide.com-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    cue.url = "github:palekiwi-labs/cue";
    cast.url = "github:palekiwi-labs/cast";
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
          inputs.cast.packages.${system}.cast-mcp-client
        ];

        commonShellHook = ''
          export TZ="Asia/Taipei";
          export TZDIR="${pkgs.tzdata}/share/zoneinfo";

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
