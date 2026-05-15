#!/usr/bin/env bash
# MemProcFS wrapper.
# Spawns an ephemeral container from FORENSIC_CLAW_MEMPROCFS_IMAGE
# (default: forensic-claw-memprocfs:latest, build with
# `docker build -t forensic-claw-memprocfs:latest tools-images/memprocfs/`).
#
# Adds --cap-add SYS_ADMIN, --device /dev/fuse, and --security-opt
# apparmor:unconfined so the FUSE mount mode (`-mount /mnt/memprocfs`) works.
# These caps are only granted to this one ephemeral container, not to the
# gateway itself.
#
# Requires: /var/run/docker.sock mounted into the gateway, and
# FORENSIC_CLAW_CASES_HOST_DIR set to the absolute host path of cases/.

set -uo pipefail

IMAGE="${FORENSIC_CLAW_MEMPROCFS_IMAGE:-forensic-claw-memprocfs:latest}"
CASES_HOST_DIR="${FORENSIC_CLAW_CASES_HOST_DIR:-}"
LOG_DIR="${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}"
LOG_FILE="$LOG_DIR/tool-command-history.md"

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
  --cap-add SYS_ADMIN \
  --device /dev/fuse \
  --security-opt apparmor:unconfined \
  -v "$CASES_HOST_DIR:/cases" \
  -w /cases \
  "$IMAGE" "$@"
rc=$?

printf -- '- %s  cwd=%s  image=%s  `memprocfs %s`  exit=%d\n' "$ts" "$cwd" "$IMAGE" "$*" "$rc" >> "$LOG_FILE"

exit "$rc"
