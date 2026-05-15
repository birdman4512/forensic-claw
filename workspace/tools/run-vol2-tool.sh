#!/usr/bin/env bash
# Volatility 2 wrapper. Runs `vol2` directly in the gateway container.
# The Dockerfile installs a stub at /usr/local/bin/vol2 that exits 1 with a
# clear "vol2 unavailable in this image" message; replace the stub if you
# need real Volatility 2 support.

set -uo pipefail

LOG_DIR="${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}"
LOG_FILE="$LOG_DIR/tool-command-history.md"

if [ "$1" = "vol2" ]; then shift; fi

mkdir -p "$LOG_DIR"

ts="$(date -Iseconds)"
cwd="$(pwd)"

vol2 "$@"
rc=$?

printf -- '- %s  cwd=%s  `vol2 %s`  exit=%d\n' "$ts" "$cwd" "$*" "$rc" >> "$LOG_FILE"

exit "$rc"
