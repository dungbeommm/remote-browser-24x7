#!/usr/bin/env bash
set -Eeuo pipefail

WEB_USER="${WEB_USER:-admin}"
WEB_PASSWORD="${WEB_PASSWORD:-}"
SCREEN_RESOLUTION="${SCREEN_RESOLUTION:-1365x768x24}"
SESSION_ROTATE_HOURS="${SESSION_ROTATE_HOURS:-0}"

if [[ ! "$WEB_USER" =~ ^[a-zA-Z0-9_-]{1,40}$ ]]; then
  echo 'WEB_USER must contain 1-40 letters/numbers/_/-.' >&2
  exit 1
fi
if (( ${#WEB_PASSWORD} < 12 )); then
  echo 'WEB_PASSWORD must contain at least 12 characters.' >&2
  exit 1
fi
if [[ ! "$SCREEN_RESOLUTION" =~ ^[0-9]{3,4}x[0-9]{3,4}x(16|24|32)$ ]]; then
  echo 'Invalid SCREEN_RESOLUTION. Example: 1365x768x24' >&2
  exit 1
fi
if [[ ! "$SESSION_ROTATE_HOURS" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo 'Invalid SESSION_ROTATE_HOURS. Example: 5.5 or 0' >&2
  exit 1
fi

# Keep downloaded files and browser profile across container restarts.
mkdir -p /data/profile /data/downloads /home/browser/.config
chown -R browser:browser /data /home/browser
if [[ -e /home/browser/Downloads && ! -L /home/browser/Downloads ]]; then
  echo 'Unexpected Downloads directory instead of symlink.' >&2
  exit 1
fi
ln -sfn /data/downloads /home/browser/Downloads

# Generate a BCrypt password file. Neither the password nor its hash is logged.
printf '%s\n' "$WEB_PASSWORD" | htpasswd -i -B -C 10 -c /etc/nginx/.htpasswd "$WEB_USER" > /dev/null
chmod 600 /etc/nginx/.htpasswd
nginx -t > /dev/null

pids=()
cleanup() {
  trap - TERM INT EXIT
  echo '[browser] Shutting down gracefully...'
  # Chromium may have multiple processes. Allow it time to flush its profile DB.
  pkill -TERM -u browser -f '/usr/lib/chromium/chromium' || true
  for pid in "${pids[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 3
  for pid in "${pids[@]}"; do
    kill -KILL "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT TERM INT

# VNC only listens on loopback INSIDE the container. Nginx is the authenticated entrypoint.
runuser -u browser -- Xvfb :99 -screen 0 "$SCREEN_RESOLUTION" -nolisten tcp -ac &
pids+=("$!")

for _ in $(seq 1 40); do
  if runuser -u browser -- env DISPLAY=:99 xdpyinfo > /dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
if ! runuser -u browser -- env DISPLAY=:99 xdpyinfo > /dev/null 2>&1; then
  echo 'Xvfb did not start' >&2
  exit 1
fi

runuser -u browser -- env DISPLAY=:99 openbox &
pids+=("$!")

runuser -u browser -- env DISPLAY=:99 x11vnc \
  -display :99 -forever -shared -rfbport 5900 -localhost -nopw -quiet -noxdamage &
pids+=("$!")

# Debian's novnc package installs its web client at /usr/share/novnc.
websockify --web=/usr/share/novnc 127.0.0.1:6080 127.0.0.1:5900 &
pids+=("$!")

runuser -u browser -- env DISPLAY=:99 HOME=/home/browser chromium \
  --user-data-dir=/data/profile \
  --no-sandbox \
  --disable-dev-shm-usage \
  --password-store=basic \
  --no-first-run \
  --no-default-browser-check \
  --restore-last-session \
  --start-maximized \
  about:blank &
pids+=("$!")

nginx -g 'daemon off;' &
pids+=("$!")

if [[ "$SESSION_ROTATE_HOURS" != 0 && "$SESSION_ROTATE_HOURS" != 0.0 ]]; then
  rotation_seconds="$(awk -v hours="$SESSION_ROTATE_HOURS" 'BEGIN {printf "%.0f", hours*3600}')"
  if (( rotation_seconds < 60 )); then
    echo 'Session rotation must be >= 1 minute or 0 (off).' >&2
    exit 1
  fi
  echo "[browser] Periodic restart enabled: every ${rotation_seconds}s."
  sleep "$rotation_seconds" &
  pids+=("$!")
fi

echo '[browser] Ready. Local URL: http://127.0.0.1:8080 (protected by password).'
# On abnormal process exit OR timer expiry, fail this container so Docker restarts it.
wait -n "${pids[@]}" || true
echo '[browser] A process finished or rotation timer elapsed. Restart requested.'
exit 1
