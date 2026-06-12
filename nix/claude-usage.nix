{ pkgs }:

pkgs.writeShellScriptBin "claude-usage" ''
  # Fetch Claude usage information using OAuth token.
  # The "anthropic-beta: oauth-2025-04-20" header is required for OAuth-based usage tracking.
  # This version string was captured from the official Claude CLI's internal usage requests.
  # If the API changes, check Anthropic API versioning docs or the CLI's debug logs.

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
