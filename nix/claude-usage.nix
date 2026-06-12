{ pkgs }:

pkgs.writeShellScriptBin "claude-usage" ''
  AUTH_FILE="$HOME/.local/share/opencode/auth.json"

  if [ ! -f "$AUTH_FILE" ]; then
    echo "Error: Auth file not found at $AUTH_FILE" >&2
    exit 1
  fi

  TOKEN=$(${pkgs.jq}/bin/jq -r '.anthropic.access // empty' "$AUTH_FILE")

  if [ -z "$TOKEN" ]; then
    echo "Error: Could not find access token in $AUTH_FILE" >&2
    exit 1
  fi

  ${pkgs.curl}/bin/curl -sS --max-time 15 \
       -H "Authorization: Bearer $TOKEN" \
       -H "anthropic-beta: oauth-2025-04-20" \
       -H "Accept: application/json" \
       "https://api.anthropic.com/api/oauth/usage" | ${pkgs.jq}/bin/jq .
''
