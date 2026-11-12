#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
mkdir -p backups
archive="browser-backup-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
volume='remote-browser_browser-data'
if ! docker volume inspect "$volume" >/dev/null 2>&1; then
  echo "Volume $volume does not exist yet. Start the browser first." >&2
  exit 1
fi

# Stop running Chromium first to avoid copying open SQLite databases.
was_running="$(docker compose ps -q browser || true)"
if [[ -n "$was_running" ]] && [[ "$(docker inspect -f '{{.State.Running}}' "$was_running")" == true ]]; then
  docker compose stop browser
  trap 'docker compose start browser >/dev/null' EXIT
fi

docker run --rm \
  -v "${volume}:/data:ro" \
  -v "$(pwd)/backups:/backup" \
  alpine:3.21 sh -c \
    'tar -czf "/backup/$1" -C /data . && chown "$2:$3" "/backup/$1" && chmod 600 "/backup/$1"' \
    -- "$archive" "$(id -u)" "$(id -g)"
chmod 700 backups
echo "Backup created: backups/$archive"
