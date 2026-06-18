#!/usr/bin/env bash
# Create a standard case folder under the cases root, seeded from templates.
# Layout (flat, no doubled `cases/` segment):
#   <cases-root>/
#   ├── templates/         (brief.md, findings/findings.md, status.json, worklog.md)
#   └── <case-id>/
#       ├── brief.md
#       ├── findings/findings.md
#       ├── status.json
#       ├── notes/worklog.md
#       ├── evidence/
#       └── outputs/

set -euo pipefail

CASE_ID="${1:-}"
if [ -z "$CASE_ID" ]; then
  echo "usage: $0 <case-id>" >&2
  exit 2
fi

ROOT="${FORENSIC_CLAW_CASE_ROOT:-/home/node/.openclaw/cases}"
CASE_DIR="$ROOT/$CASE_ID"
TEMPLATE_DIR="$ROOT/templates"

mkdir -p "$CASE_DIR/notes" "$CASE_DIR/evidence" "$CASE_DIR/findings" "$CASE_DIR/outputs"

for f in brief.md status.json; do
  if [ ! -e "$CASE_DIR/$f" ]; then
    if [ -e "$TEMPLATE_DIR/$f" ]; then
      cp "$TEMPLATE_DIR/$f" "$CASE_DIR/$f"
    else
      touch "$CASE_DIR/$f"
    fi
  fi
done

if [ ! -e "$CASE_DIR/findings/findings.md" ]; then
  if [ -e "$TEMPLATE_DIR/findings/findings.md" ]; then
    cp "$TEMPLATE_DIR/findings/findings.md" "$CASE_DIR/findings/findings.md"
  elif [ -e "$TEMPLATE_DIR/findings.md" ]; then
    cp "$TEMPLATE_DIR/findings.md" "$CASE_DIR/findings/findings.md"
  else
    touch "$CASE_DIR/findings/findings.md"
  fi
fi

if [ ! -e "$CASE_DIR/notes/worklog.md" ]; then
  if [ -e "$TEMPLATE_DIR/worklog.md" ]; then
    cp "$TEMPLATE_DIR/worklog.md" "$CASE_DIR/notes/worklog.md"
  else
    printf '# Worklog - %s\n' "$CASE_ID" > "$CASE_DIR/notes/worklog.md"
  fi
fi

printf '%s\n' "$CASE_DIR"
