#!/usr/bin/env bash
# Optional RustDesk control channel, launched next to Selkies.
# - Installs the official RustDesk .deb on first start (.deb cached on /data).
# - Runs RustDesk on display :99 as user "browser" (service + GUI).
# - Persists the RustDesk identity (device ID) under /data/rustdesk.
# - Prints RUSTDESK_ID=<id> to stdout so callers can grep it from the logs.
# - Permanent password = WEB_PASSWORD (same secret as the web login).
set -u

RD_VERSION="1.5.1"
RD_DEB_URL="https://github.com/rustdesk/rustdesk/releases/download/${RD_VERSION}/rustdesk-${RD_VERSION}-x86_64.deb"
PKG_DIR=/data/pkg
CFG_DIR=/data/rustdesk
BROWSER_HOME=/home/browser

log() { echo "[rustdesk] $*"; }

# Wait for the X display started by start.sh
for _ in $(seq 1 80); do
  if runuser -u browser -- env DISPLAY=:99 xdpyinfo > /dev/null 2>&1; then break; fi
  sleep 0.5
done

# Install once per container filesystem; the .deb itself is cached on /data.
if ! command -v rustdesk > /dev/null 2>&1; then
  mkdir -p "$PKG_DIR"
  DEB="$PKG_DIR/rustdesk-${RD_VERSION}-x86_64.deb"
  if [ ! -s "$DEB" ]; then
    log "Downloading RustDesk $RD_VERSION ..."
    if ! curl -fL --retry 3 -o "$DEB" "$RD_DEB_URL"; then
      log "Download failed; RustDesk disabled for this session."
      exit 0
    fi
  fi
  log "Installing RustDesk (first start takes a bit) ..."
  apt-get update -qq > /dev/null 2>&1
  if ! apt-get install -y -qq "$DEB" > /dev/null 2>&1; then
    log "Install failed; RustDesk disabled for this session."
    exit 0
  fi
fi

# Persistent identity/config on the data volume
mkdir -p "$CFG_DIR" "$BROWSER_HOME/.config"
if [ ! -L "$BROWSER_HOME/.config/rustdesk" ]; then
  rm -rf "$BROWSER_HOME/.config/rustdesk"
  ln -s "$CFG_DIR" "$BROWSER_HOME/.config/rustdesk"
fi
chown -R browser:browser "$CFG_DIR" "$BROWSER_HOME/.config"

# Start the RustDesk service and the GUI inside the desktop session
runuser -u browser -- env DISPLAY=:99 HOME="$BROWSER_HOME" rustdesk --service > /tmp/rustdesk-service.log 2>&1 &
sleep 3
runuser -u browser -- env DISPLAY=:99 HOME="$BROWSER_HOME" rustdesk > /tmp/rustdesk-gui.log 2>&1 &

# Set the permanent password (trimmed WEB_PASSWORD) once the service is up
PW="$(printf '%s' "${WEB_PASSWORD:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [ -n "$PW" ]; then
  for _ in $(seq 1 30); do
    if runuser -u browser -- env HOME="$BROWSER_HOME" rustdesk --password "$PW" > /dev/null 2>&1; then
      log "Permanent password set."
      break
    fi
    sleep 2
  done
fi

# Report the device ID (also kept on the volume)
for _ in $(seq 1 30); do
  ID="$(runuser -u browser -- env HOME="$BROWSER_HOME" rustdesk --get-id 2>/dev/null | tr -dc '0-9')"
  if [ -n "$ID" ]; then
    echo "$ID" > /data/rustdesk-id.txt
    chown browser:browser /data/rustdesk-id.txt 2>/dev/null || true
    echo "RUSTDESK_ID=$ID"
    log "Ready. ID: $ID"
    break
  fi
  sleep 2
done

# Supervise: keep the control channel alive for the whole session
while true; do
  if ! pgrep -u browser -x rustdesk > /dev/null 2>&1; then
    log "RustDesk process gone; restarting."
    runuser -u browser -- env DISPLAY=:99 HOME="$BROWSER_HOME" rustdesk --service > /tmp/rustdesk-service.log 2>&1 &
    sleep 3
    runuser -u browser -- env DISPLAY=:99 HOME="$BROWSER_HOME" rustdesk > /tmp/rustdesk-gui.log 2>&1 &
  fi
  sleep 30
done
