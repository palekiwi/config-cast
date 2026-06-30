# https://nvf.notashelf.dev/options.html

{ pkgs, nvf, ... }:
let
  customNeovim = nvf.lib.neovimConfiguration {
    inherit pkgs;
    modules = [
      {
        config.vim = {
          utility.motion.hop = {
            enable = true;
          };
          lineNumberMode = "none";
          autocmds = [
            {
              event = [ "VimEnter" ];
              pattern = [ "*" ];
              command = "startinsert";
            }
          ];
          options = {
            scrolloff = 5;
          };
          luaConfigPost = ''
            vim.g.clipboard = {
              name = 'OSC 52',
              copy = {
                ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
                ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
              },
              paste = {
                ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
                ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
              },
            }
          '';
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
              next = "<Down>";
              previous = "<Up>";
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
              key = "<C-c>";
              mode = [ "v" ];
              silent = true;
              action = ''"+y'';
            }
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
            {
              key = "s";
              mode = [ "n" "v" ];
              silent = true;
              action = "<cmd>HopChar1<CR>";
            }
            {
              key = "l";
              mode = [ "n" "v" ];
              silent = true;
              action = "<cmd>HopLineStart<CR>";
            }
          ];
          languages.json.enable = true;
          languages.json.treesitter.enable = true;
          languages.nix.enable = true;
          languages.nix.treesitter.enable = true;
          languages.ruby.enable = true;
          languages.ruby.treesitter.enable = true;
          languages.markdown.enable = true;
          languages.markdown.treesitter.enable = true;
          languages.markdown.extensions.render-markdown-nvim = {
            enable = true;
            setupOpts = {};
          };
        };
      }
    ];
  };
in
customNeovim.neovim
