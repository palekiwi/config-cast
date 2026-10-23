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
    cue-platform = {
      url = "git+file:///home/pl/code/palekiwi-labs/cue-platform";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.follows = "cue-platform/llm-agents";
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
        # blocked red, working yellow, finished-unseen green. Review
        # windows (cue-review) colour by @review_state, show their cue
        # context dimmed, and preview PR title, context and run id.
        tmuxWindowPicker = pkgs.writeShellApplication {
          name = "tmux-window-picker";
          runtimeInputs = [ pkgs.fzf pkgs.gawk ];
          text = ''
            # Rows: id, coloured label (hidden id field used for preview).
            tmux list-windows -F \
              '#{window_id}	#{@pi_state}	#{@pi_unseen}	#{window_active}	#{@pi_ctx}	#W	#{@review_state}	#{@review_context}	#{@pi_desc}' \
              | awk -F '\t' '{
                  c = "";
                  if ($7 == "failed") c = "\033[31m";
                  else if ($7 == "running") c = "\033[33m";
                  else if ($7 == "ok") c = "\033[32m";
                  else if ($2 == "blocked") c = "\033[31m";
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
                  rv = ($8 != "") ? sprintf("  \033[2m%s\033[0m", $8) : "";
                  # Session description from the pi /describe command,
                  # dimmed right after the window name when present.
                  dv = ($9 != "") ? sprintf("  \033[2m%s\033[0m", substr($9, 1, 60)) : "";
                  printf "%s\t%s %s%s\033[0m%s%s%s\n", $1, mark, c, $6, dv, pct, rv;
                }' \
              | fzf --ansi --reverse --no-sort --delimiter '\t' \
                  --with-nth 2 --nth 1 \
                  --prompt "$(tmux display-message -p '#S')> " \
                  --preview "tmux display-message -p -t {1} '#{?@review_context,#{@review_title} | #{@review_context} | run #{?@review_run,#{@review_run},pending} | #{?@review_state,#{@review_state},pending},#{@pi_desc}}'" \
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

        # Headless browser CLI for agents (vercel-labs/agent-browser),
        # bundles its own Chromium. Defaults make it work in the sandbox:
        # - fontconfig: without it Chromium aborts on first render;
        # - host-resolver MAP: localhost resolves to the docker host, so
        #   http://localhost:<port> reaches host-published app ports while
        #   the Host header stays "localhost" (passes Rails/Vite host
        #   checks, and hard-coded http://localhost:8080 Vite assets load);
        # - /dev/shm is 64M in the sandbox.
        # Both are --set-default, so callers can override them.
        agentBrowser = pkgs.symlinkJoin {
          name = "agent-browser";
          paths = [ agents.agent-browser ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/agent-browser \
              --set-default FONTCONFIG_FILE ${pkgs.makeFontsConf {
                fontDirectories = [ pkgs.dejavu_fonts pkgs.liberation_ttf ];
              }} \
              --set-default AGENT_BROWSER_ARGS \
                "--host-resolver-rules=MAP localhost host.docker.internal,--disable-dev-shm-usage"
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
          nushell
          python3
          ripgrep
          tree
          tree-sitter
        ]) ++ [
          castTmux
          agentBrowser
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
          export JIRA_TOKEN=$JIRA_TOKEN_READONLY
          export ATLASSIAN_CLI_TOKEN_SPABREAKS=$JIRA_TOKEN_READONLY
          export ATLASSIAN_CLI_CONFIG_DIR="$HOME/.config/cast/nix/atlassian-cli"
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
              inputs.cue-platform.packages.${system}.pi
              agents.claude-code
            ];
            shellHook = commonShellHook;
          });
        };
      }
    );
}
