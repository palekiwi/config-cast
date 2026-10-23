# Headless browser CLI for agents (vercel-labs/agent-browser), bundles
# its own Chromium. Defaults make it work in the sandbox:
# - fontconfig: without it Chromium aborts on first render;
# - host-resolver MAP: localhost resolves to the docker host, so
#   http://localhost:<port> reaches host-published app ports while the
#   Host header stays "localhost" (passes Rails/Vite host checks, and
#   hard-coded http://localhost:8080 Vite assets load);
# - /dev/shm is 64M in the sandbox.
# Both are --set-default, so callers can override them.
{ pkgs, agent-browser }:
pkgs.symlinkJoin {
  name = "agent-browser";
  paths = [ agent-browser ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/agent-browser \
      --set-default FONTCONFIG_FILE ${pkgs.makeFontsConf {
        fontDirectories = [ pkgs.dejavu_fonts pkgs.liberation_ttf ];
      }} \
      --set-default AGENT_BROWSER_ARGS \
        "--host-resolver-rules=MAP localhost host.docker.internal,--disable-dev-shm-usage"
  '';
}
