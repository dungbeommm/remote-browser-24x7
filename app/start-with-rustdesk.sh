#!/usr/bin/env bash
# Wrapper entrypoint: start the RustDesk channel in the background,
# then run the original start.sh as the container's main process.
set -u
if [ -f /app/rustdesk-launch.sh ]; then
  bash /app/rustdesk-launch.sh &
fi
exec /app/start.sh
