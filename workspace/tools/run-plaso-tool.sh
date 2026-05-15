#!/usr/bin/env bash
# Plaso (log2timeline / psort) wrapper.
# Spawns an ephemeral container from FORENSIC_CLAW_PLASO_IMAGE
# (default: log2timeline/plaso:latest), bind-mounts the host case root
# at /cases inside the tool container, and logs the invocation.
#
# Requires: /var/run/docker.sock mounted into the gateway, and
# FORENSIC_CLAW_CASES_HOST_DIR set to the absolute host path of cases/.

set -uo pipefail

IMAGE="${FORENSIC_CLAW_PLASO_IMAGE:-log2timeline/plaso:latest}"
CASES_HOST_DIR="${FORENSIC_CLAW_CASES_HOST_DIR:-}"
LOG_DIR="${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}"
LOG_FILE="$LOG_DIR/tool-command-history.md"

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <plaso-tool> [args...]" >&2
  echo "examples: $0 log2timeline.py --help ; $0 psort.py --help" >&2
  exit 2
fi

if [ -z "$CASES_HOST_DIR" ]; then
  echo "error: FORENSIC_CLAW_CASES_HOST_DIR is not set." >&2
  echo "       Set OPENCLAW_CASES_HOST_PATH in .env to the absolute host path of ./cases" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"

ts="$(date -Iseconds)"
cwd="$(pwd)"

docker run --rm -i \
  --network bridge \
  -v "$CASES_HOST_DIR:/cases" \
  -w /cases \
  "$IMAGE" "$@"
rc=$?

printf -- '- %s  cwd=%s  image=%s  `%s`  exit=%d\n' "$ts" "$cwd" "$IMAGE" "$*" "$rc" >> "$LOG_FILE"

exit "$rc"
