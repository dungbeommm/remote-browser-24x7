#!/usr/bin/env bash
set -Eeuo pipefail
SESSION_BACKUP_KEY="${SESSION_BACKUP_KEY:-}"
export SESSION_BACKUP_KEY

if (( ${#SESSION_BACKUP_KEY} < 32 )); then
  echo 'SESSION_BACKUP_KEY secret must contain at least 32 characters.' >&2
  exit 1
fi

compose=(docker compose -f docker-compose.yml -f docker-compose.rustdesk.yml)
container_id="$("${compose[@]}" ps -q browser)"
test -n "$container_id"

# Stop Chromium so SQLite databases and session files are consistent.
"${compose[@]}" stop browser
volume_name="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$container_id")"
test -n "$volume_name"

docker run --rm -v "$volume_name:/data:ro" alpine:3.20 tar -C /data -czf - . \
  | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
      -pass env:SESSION_BACKUP_KEY -out browser-state.tar.gz.enc
test -s browser-state.tar.gz.enc
echo 'Encrypted browser profile and downloads for the next run.'
