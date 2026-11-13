#!/usr/bin/env bash
set -Eeuo pipefail
SESSION_BACKUP_KEY="${SESSION_BACKUP_KEY:-}"
export SESSION_BACKUP_KEY

if (( ${#SESSION_BACKUP_KEY} < 32 )); then
  echo 'SESSION_BACKUP_KEY secret must contain at least 32 characters.' >&2
  exit 1
fi

compose=(docker compose -f docker-compose.yml -f docker-compose.rustdesk.yml)
artifact="$(gh api "repos/$GITHUB_REPOSITORY/actions/artifacts?name=browser-state&per_page=30" \
  --jq '[.artifacts[] | select(.expired == false and .name == "browser-state")] | sort_by(.created_at) | last | if . == null then "" else (.workflow_run.id | tostring) end')"

if [[ -z "$artifact" ]]; then
  echo 'No previous browser state found; starting with an empty profile.'
  exit 0
fi

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT
gh run download "$artifact" --name browser-state --dir "$state_dir"
test -s "$state_dir/browser-state.tar.gz.enc"

"${compose[@]}" build browser
"${compose[@]}" create browser
container_id="$("${compose[@]}" ps -aq browser | head -1)"
volume_name="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$container_id")"
test -n "$volume_name"

openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:SESSION_BACKUP_KEY \
  -in "$state_dir/browser-state.tar.gz.enc" \
  | docker run --rm -i -v "$volume_name:/data" alpine:3.20 tar -C /data -xzf -

echo "Restored browser state from workflow run $artifact."
