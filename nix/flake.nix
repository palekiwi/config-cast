{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    mem.url = "github:palekiwi-labs/mem";
    nvf.url = "github:NotAShelf/nvf";
  };

  outputs = { nixpkgs, flake-utils, nvf, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        customNeovim = nvf.lib.neovimConfiguration {
          inherit pkgs;
          modules = [
            {
              config.vim = {
                theme = {
                  enable = true;
                  name = "github";
                  style = "dark_default";
                };
                treesitter.enable = true;
                autocomplete.nvim-cmp = {
                  enable = true;
                  sourcePlugins = [ "cmp-path"];
                  sources = { path = "[Path]"; };
                  mappings = {
                    confirm = "<C-e>";
                    close = null;
                  };
                };
                languages.markdown.enable = true;
              };
            }
          ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "cast-default";
          buildInputs = with pkgs; [
            ast-grep
            fd
            gh
            jq
            ripgrep
            tree
            customNeovim.neovim

            inputs.mem.packages.${system}.default
          ];

          shellHook = ''
            echo "CAST Global Nix Environment Loaded"

            export EDITOR=nvim
          '';
        };
      }
    );
}
