{
  description = "Global CAST development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    mem.url = "github:palekiwi-labs/mem/2a49ad52189ed96930765fc9d117268f7a2970c8";
    cast.url = "github:palekiwi-labs/cast/dev";
    nvf.url = "github:NotAShelf/nvf";
  };

  outputs = { nixpkgs, flake-utils, nvf, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        customNeovim = import ./nvim.nix { inherit pkgs nvf; };
        claudeUsage = import ./claude-usage.nix { inherit pkgs; };
        envVars = import ./env.nix { inherit pkgs; };
      in
      {
        devShells.default = pkgs.mkShell (envVars // {
          name = "cast-default";
          buildInputs = with pkgs; [
            ast-grep
            claudeUsage
            curl
            customNeovim
            fd
            gh
            jq
            ripgrep
            tree

            inputs.mem.packages.${system}.default
            inputs.cast.packages.${system}.cast-mcp-client
          ];

          shellHook = ''
            export TZ="Asia/Taipei";
            export TZDIR="${pkgs.tzdata}/share/zoneinfo";

            echo "CAST Global Nix Environment Loaded"
          '';
        });
      }
    );
}
