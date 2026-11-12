#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 2 || "$1" != '--confirm' || ! -f "$2" ]]; then
  echo 'Usage: ./scripts/restore.sh --confirm backups/browser-backup-YYYYMMDDTHHMMSSZ.tar.gz' >&2
  echo 'WARNING: This REPLACES all current browser history, cookies and downloads.' >&2
  exit 2
fi
archive="$(realpath "$2")"
if [[ "${archive##*/}" != browser-backup-*.tar.gz ]]; then
  echo 'Expected a browser-backup-*.tar.gz file.' >&2
  exit 2
fi
volume='remote-browser_browser-data'
docker compose stop browser
# Docker volume persists regardless of container shutdown; erase it explicitly before restore.
docker run --rm \
  -v "${volume}:/data" \
  -v "$(dirname "$archive"):/backup:ro" \
  alpine:3.21 sh -c \
    'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -xzf "/backup/$1" -C /data' \
    -- "$(basename "$archive")"
docker compose start browser
echo 'Browser profile restored and started.'
