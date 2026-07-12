#!/usr/bin/env bash
# Delegates one bounded investigative sub-task to the local-analyst gateway
# (a separate, always-local OpenClaw agent - see docker-compose.yml service
# "openclaw-gateway-local", container name forensic-claw-local-analyst).
#
# local-analyst shares this workspace (tools/, cases/) but has its own,
# curated skill set (skills-local-analyst/: vol, vol2, memprocfs, tshark,
# pyshark, log2timeline.py, psort.py) and runs entirely on a local Ollama
# model. It can run one of those tools itself and/or reason over the
# output; only its final text answer comes back here, so no raw tool
# output and no frontier tokens are spent on the sub-task.
#
# Usage:
#   delegate-to-local-analyst.sh "<task message>" [timeout-seconds]
#
# The task message should be self-contained: what to run (if anything,
# with exact tools/ invocation) and what question to answer about it.
# Small local models on CPU are slow - a real tool-calling turn can take
# several minutes. Default timeout is 480s; pass a larger value for
# heavier tools (e.g. log2timeline.py over a large source).

set -uo pipefail

CONTAINER="${FORENSIC_CLAW_LOCAL_ANALYST_CONTAINER:-forensic-claw-local-analyst}"
LOG_DIR="${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}"
LOG_FILE="$LOG_DIR/tool-command-history.md"

if [ "$#" -lt 1 ]; then
  echo "usage: $0 \"<task message>\" [timeout-seconds]" >&2
  exit 2
fi

task="$1"
timeout_s="${2:-480}"

mkdir -p "$LOG_DIR"
ts="$(date -Iseconds)"

response="$(docker exec "$CONTAINER" node /app/dist/index.js agent \
  --agent main --message "$task" --json --timeout "$timeout_s" 2>&1)"
rc=$?

printf -- '- %s  cwd=%s  `delegate-to-local-analyst: %s`  exit=%d\n' \
  "$ts" "$(pwd)" "$(printf '%s' "$task" | tr '\n' ' ' | cut -c1-200)" "$rc" >> "$LOG_FILE"

if [ $rc -ne 0 ]; then
  echo "delegate-to-local-analyst failed (docker exec exit $rc): $response" >&2
  exit 1
fi

echo "$response" | python3 -c '
import json, sys
try:
    r = json.loads(sys.stdin.read())
except json.JSONDecodeError as e:
    print(f"delegate-to-local-analyst: could not parse response: {e}", file=sys.stderr)
    sys.exit(1)
if r.get("status") != "ok":
    status = r.get("status")
    summary = r.get("summary")
    print(f"delegate-to-local-analyst: run did not complete (status={status}, summary={summary})", file=sys.stderr)
    sys.exit(1)
payloads = r.get("result", {}).get("payloads", [])
text = "\n".join(p.get("text", "") for p in payloads if p.get("text"))
print(text if text else "(local-analyst returned no text)")
'
