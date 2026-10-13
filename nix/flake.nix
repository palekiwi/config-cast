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
            # Rows: id, coloured label (hidden id field used for preview).
            tmux list-windows -F \
              '#{window_id}	#{@pi_state}	#{@pi_unseen}	#{window_active}	#{@pi_ctx}	#W' \
              | awk -F '\t' '{
                  c = "";
                  if ($2 == "blocked") c = "\033[31m";
                  else if ($2 == "working") c = "\033[33m";
                  else if ($3 == "1") c = "\033[32m";
                  mark = ($4 == "1") ? "*" : " ";
                  # Context tokens, formatted and coloured like the pi
                  # footer (cue thresholds: 80k caution, 100k soft, 140k hard).
                  pct = "";
                  if ($5 != "") {
                    n = $5 + 0;
                    if (n < 1000) t = n;
                    else if (n < 10000) t = sprintf("%.1fk", n / 1000);
                    else if (n < 1000000) t = sprintf("%dk", int(n / 1000 + 0.5));
                    else t = sprintf("%.1fM", n / 1000000);
                    pc = "\033[37m";
                    if (n >= 140000) pc = "\033[1;31m";
                    else if (n >= 100000) pc = "\033[31m";
                    else if (n >= 80000) pc = "\033[33m";
                    pct = sprintf("  %s%s\033[0m", pc, t);
                  }
                  printf "%s\t%s %s%s\033[0m%s\n", $1, mark, c, $6, pct;
                }' \
              | fzf --ansi --reverse --no-sort --delimiter '\t' \
                  --with-nth 2 --nth 1 \
                  --prompt "$(tmux display-message -p '#S')> " \
                  --preview "tmux display-message -p -t {1} '#{@pi_prompt}'" \
                  --preview-window 'down,3,wrap' \
              | cut -f1 \
              | xargs -r tmux select-window -t
          '';
        };

        # Multi-agent code review driving cue-agent (nushell prototype).
        # nu has no signal trap: on Ctrl-C it aborts with exit 1, so a
        # bash wrapper records SIGINT and maps the exit to 130; it also
        # publishes @review_state on its tmux window (running/ok/failed)
        # for the statusline. cue-agent receives the same SIGINT and
        # cleans up its own runs.
        cueReviewNu = pkgs.writers.writeNuBin "cue-review-nu"
          ./cue-review/cue-review.nu;
        cueReview = pkgs.writeShellApplication {
          name = "cue-review";
          text = ''
            set_review_state() {
              if [ -n "$TMUX" ] && command -v tmux >/dev/null 2>&1; then
                tmux set -q -w "@review_state=$1" 2>/dev/null || true
              fi
            }
            set_review_state running
            interrupted=0
            trap 'interrupted=1' INT TERM
            rc=0
            ${cueReviewNu}/bin/cue-review-nu "$@" || rc=$?
            if [ "$interrupted" = 1 ]; then
              echo "cue-review: interrupted; no further phases started" >&2
              set_review_state failed
              exit 130
            fi
            state=$([ "$rc" = 0 ] && echo ok || echo failed)
            set_review_state "$state"
            exit "$rc"
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
          cueReview
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
