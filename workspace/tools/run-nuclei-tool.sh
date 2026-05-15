#!/usr/bin/env bash
# Nuclei wrapper.
# Spawns an ephemeral container from FORENSIC_CLAW_NUCLEI_IMAGE
# (default: projectdiscovery/nuclei:latest) so the bundled detection
# templates stay current without rebuilding the gateway image.
#
# Requires: /var/run/docker.sock mounted into the gateway, and
# FORENSIC_CLAW_CASES_HOST_DIR set to the absolute host path of cases/.

set -uo pipefail

IMAGE="${FORENSIC_CLAW_NUCLEI_IMAGE:-projectdiscovery/nuclei:latest}"
CASES_HOST_DIR="${FORENSIC_CLAW_CASES_HOST_DIR:-}"
LOG_DIR="${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}"
LOG_FILE="$LOG_DIR/tool-command-history.md"

if [ -z "$CASES_HOST_DIR" ]; then
  echo "error: FORENSIC_CLAW_CASES_HOST_DIR is not set." >&2
  echo "       Set OPENCLAW_CASES_HOST_PATH in .env to the absolute host path of ./cases" >&2
  exit 2
fi

if [ "${1:-}" = "nuclei" ]; then shift; fi

mkdir -p "$LOG_DIR"

ts="$(date -Iseconds)"
cwd="$(pwd)"

docker run --rm -i \
  --network bridge \
  -v "$CASES_HOST_DIR:/cases" \
  -w /cases \
  "$IMAGE" "$@"
rc=$?

printf -- '- %s  cwd=%s  image=%s  `nuclei %s`  exit=%d\n' "$ts" "$cwd" "$IMAGE" "$*" "$rc" >> "$LOG_FILE"

exit "$rc"
