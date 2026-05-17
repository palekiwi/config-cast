{ pkgs, nvf, ... }:
let
  customNeovim = nvf.lib.neovimConfiguration {
    inherit pkgs;
    modules = [
      {
        config.vim = {
          lineNumberMode = "none";
          theme = {
            enable = true;
            name = "github";
            style = "dark_default";
          };
          treesitter.enable = true;
          autocomplete.nvim-cmp = {
            enable = true;
            sourcePlugins = [ "cmp-path" ];
            sources = { path = "[Path]"; };
            mappings = {
              confirm = "<C-e>";
              close = null;
            };
          };
          keymaps = [
            {
              key = "<Find>";
              mode = [ "n" "i" "v" "c" "x" ];
              silent = true;
              action = "<Home>";
            }
            {
              key = "<Select>";
              mode = [ "n" "i" "v" "c" "x" ];
              silent = true;
              action = "<End>";
            }
          ];
          languages.ruby.enable = true;
          languages.ruby.treesitter.enable = true;
          languages.markdown.enable = true;
          languages.markdown.extensions.render-markdown-nvim = {
            enable = true;
            setupOpts = {
              anti_conceal = {
                enabled = false;
              };
            };
          };
        };
      }
    ];
  };
in
customNeovim.neovim
