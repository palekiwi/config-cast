# `cast` configuration

This is configuration for `cast`, a coding agent sandbox tool that
allows users to run AI agent harnesses safely iinside docker containers
and define the agent's development environments with `nix`.

## Architecture:

- `nix/`: auto-mounted into the agent dev container
  * `nix/flake.nix`: defines the global cast devshell for the container
  * `nix/env.nix`: defines env variables for the devshell
  * `nix/nvim.nix`: defines nvim configuration which is used as prompt editor in agent harnesses
  * `nix/gitconfig`: git config loaded by the global devshell
  * `nix/gitignore`: gitignore loaded by the global devshell

- `cast.json`: global user configuration of `cast`
- `cast.env`: environment variables injected into the container
