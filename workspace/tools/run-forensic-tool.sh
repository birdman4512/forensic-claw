#!/usr/bin/env bash
# Forensic Claw tool wrapper.
# Runs the requested tool directly in the gateway container (tools are baked
# into the image by the project Dockerfile) and appends a one-line entry
# (timestamp + cwd + command + exit code) to the command history log.

set -uo pipefail

LOG_DIR="${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}"
LOG_FILE="$LOG_DIR/tool-command-history.md"

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <tool> [args...]" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"
if [ ! -f "$LOG_FILE" ]; then
  cat > "$LOG_FILE" <<'EOF'
# Tool Command History

Append-only log written by `tools/run-forensic-tool.sh`.
Format: `- <iso-timestamp>  cwd=<dir>  `<tool> <args>`  exit=<code>`
EOF
fi

ts="$(date -Iseconds)"
cwd="$(pwd)"

"$@"
rc=$?

printf -- '- %s  cwd=%s  `%s`  exit=%d\n' "$ts" "$cwd" "$*" "$rc" >> "$LOG_FILE"

exit "$rc"
