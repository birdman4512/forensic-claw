#!/usr/bin/env bash
# MemProcFS wrapper.
# Spawns an ephemeral container from FORENSIC_CLAW_MEMPROCFS_IMAGE and runs
# memprocfs inside it. There is no canonical upstream MemProcFS image - you
# must point FORENSIC_CLAW_MEMPROCFS_IMAGE at one you build or trust.
#
# Note: MemProcFS typically needs FUSE access to expose its virtual filesystem.
# If your usage requires that, the upstream image has to be built with FUSE
# support and you may need to add `--cap-add SYS_ADMIN --device /dev/fuse` to
# the docker run line below.
#
# Requires: /var/run/docker.sock mounted into the gateway, and
# FORENSIC_CLAW_CASES_HOST_DIR set to the absolute host path of cases/.

set -uo pipefail

IMAGE="${FORENSIC_CLAW_MEMPROCFS_IMAGE:-}"
CASES_HOST_DIR="${FORENSIC_CLAW_CASES_HOST_DIR:-}"
LOG_DIR="${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}"
LOG_FILE="$LOG_DIR/tool-command-history.md"

if [ -z "$IMAGE" ]; then
  echo "error: FORENSIC_CLAW_MEMPROCFS_IMAGE is not set." >&2
  echo "       Set it in .env to a MemProcFS docker image (build locally or use a community image you trust)." >&2
  exit 2
fi

if [ -z "$CASES_HOST_DIR" ]; then
  echo "error: FORENSIC_CLAW_CASES_HOST_DIR is not set." >&2
  echo "       Set OPENCLAW_CASES_HOST_PATH in .env to the absolute host path of ./cases" >&2
  exit 2
fi

if [ "${1:-}" = "memprocfs" ]; then shift; fi

mkdir -p "$LOG_DIR"

ts="$(date -Iseconds)"
cwd="$(pwd)"

docker run --rm -i \
  --network bridge \
  -v "$CASES_HOST_DIR:/cases" \
  -w /cases \
  "$IMAGE" memprocfs "$@"
rc=$?

printf -- '- %s  cwd=%s  image=%s  `memprocfs %s`  exit=%d\n' "$ts" "$cwd" "$IMAGE" "$*" "$rc" >> "$LOG_FILE"

exit "$rc"
