#!/usr/bin/env bash
set -euo pipefail
curl --fail --silent --show-error --max-time 3 http://127.0.0.1:8080/healthz > /dev/null
pgrep -u browser -f '/usr/lib/chromium/chromium' > /dev/null
