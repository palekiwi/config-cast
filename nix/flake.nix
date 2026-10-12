{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    cue = {
      url = "github:palekiwi-labs/cue/cue-agent-prototype";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-pr-sync = {
      url = "github:palekiwi-labs/git-pr-sync";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cast = {
      url = "github:palekiwi-labs/cast/v0.2.0-rc.2";
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

        # tmux that always loads ./tmux.conf from the store, so the config
        # ships with this flake instead of a bind mount.
        castTmux = pkgs.symlinkJoin {
          name = "tmux-cast";
          paths = [ pkgs.tmux ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/tmux --add-flags "-f ${./tmux.conf}"
          '';
        };

        # Fuzzy window picker for the container tmux (prefix w). Lists
        # windows coloured by pi state (tmux-state extension):
        # blocked red, working yellow, finished-unseen green.
        tmuxWindowPicker = pkgs.writeShellApplication {
          name = "tmux-window-picker";
          runtimeInputs = [ pkgs.fzf pkgs.gawk ];
          text = ''
            tmux list-windows -F \
              '#{window_id}	#{@pi_state}	#{@pi_unseen}	#{window_active}	#W' \
              | awk -F '\t' '{
                  c = "";
                  if ($2 == "blocked") c = "\033[31m";
                  else if ($2 == "working") c = "\033[33m";
                  else if ($3 == "1") c = "\033[32m";
                  mark = ($4 == "1") ? "*" : " ";
                  printf "%s\t%s %s%s\033[0m\n", $1, mark, c, $5;
                }' \
              | fzf --ansi --reverse --no-sort --delimiter '\t' \
                  --with-nth 2 --prompt 'window> ' \
              | cut -f1 \
              | xargs -r tmux select-window -t
          '';
        };

        # Shared tooling available in every cast shell.
        commonInputs = (with pkgs; [
          ast-grep
          curl
          customNeovim
          fd
          gh
          go-task
          jq
          python3
          ripgrep
          tree
          tree-sitter
        ]) ++ [
          castTmux
          tmuxWindowPicker
          inputs.cue.packages.${system}.cue
          inputs.cue.packages.${system}.cue-agent
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
