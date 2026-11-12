#!/usr/bin/env bash
set -euo pipefail
# Usage: ./scripts/show-link.sh
# If the quick tunnel is not ready, show the last logs instead.
logs="$(docker compose --profile quick logs --no-color tunnel-quick 2>&1 || true)"
url="$(printf '%s\n' "$logs" | grep -Eo 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' | tail -1 || true)"
if [[ -n "$url" ]]; then
  printf '\nBrowser URL: %s\n' "$url"
  echo 'Sign in with WEB_USER / WEB_PASSWORD from your .env file.'
else
  echo 'No quick tunnel URL found. Check tunnel status:'
  printf '%s\n' "$logs" | tail -35
  exit 1
fi
