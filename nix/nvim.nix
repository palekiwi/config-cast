{ pkgs, nvf, ... }:
let
  customNeovim = nvf.lib.neovimConfiguration {
    inherit pkgs;
    modules = [
      {
        config.vim = {
          lineNumberMode = "none";
          options = {
            scrolloff = 5;
          };
          theme = {
            enable = true;
            name = "github";
            style = "dark_default";
          };
          treesitter.enable = true;
          autocomplete.nvim-cmp = {
            enable = true;
            mappings = {
              confirm = "<C-e>";
              close = null;
            };
            setupOpts = {
              sources = pkgs.lib.mkForce [
                {
                  name = "path";
                  option = {
                    get_cwd = pkgs.lib.generators.mkLuaInline "function() return vim.fn.getcwd() end";
                  };
                }
              ];
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
