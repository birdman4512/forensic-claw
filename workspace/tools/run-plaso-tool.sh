#!/usr/bin/env bash
# Plaso (log2timeline / psort) wrapper. Runs the requested Plaso tool directly
# in the gateway container. Plaso is installed via the pip block in the project
# Dockerfile.

set -uo pipefail

LOG_DIR="${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}"
LOG_FILE="$LOG_DIR/tool-command-history.md"

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <plaso-tool> [args...]" >&2
  echo "examples: $0 log2timeline.py --help ; $0 psort.py --help" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"

ts="$(date -Iseconds)"
cwd="$(pwd)"

"$@"
rc=$?

printf -- '- %s  cwd=%s  `%s`  exit=%d\n' "$ts" "$cwd" "$*" "$rc" >> "$LOG_FILE"

exit "$rc"
