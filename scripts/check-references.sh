#!/usr/bin/env bash
# Guard against regressions of personal info, old host paths, and the
# doubled-cases layout. Runs locally and in CI. Exits non-zero on any hit.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Patterns we never want to see in tracked content.
# Each entry: <label>|<extended-regex>
PATTERNS=(
  'personal: dean|(^|[^a-z])dean([^a-z]|$)'
  'personal: quirk|quirk'
  'old host path: /home/dean|/home/dean'
  'old host path: openclaw-agents|openclaw-agents'
  'old host path: openclaw-cases|openclaw-cases'
  'old layout: /cases/cases/|/cases/cases/'
  'leaked credential: footb@ll|footb@ll'
)

# Files we scan: only what would ship to end users (tracked source files).
INCLUDES=(
  '--include=*.md'
  '--include=*.sh'
  '--include=*.yml'
  '--include=*.yaml'
  '--include=*.json'
  '--include=*.example'
  '--include=Dockerfile'
  '--include=.gitignore'
  '--include=.dockerignore'
)

# Paths to exclude from scanning. We deliberately skip ourself: this script
# defines the patterns it forbids, so it would always self-match.
EXCLUDES=(
  '--exclude-dir=.git'
  '--exclude-dir=node_modules'
  '--exclude-dir=.venv'
  '--exclude=check-references.sh'
)

failed=0
for entry in "${PATTERNS[@]}"; do
  label="${entry%%|*}"
  pattern="${entry#*|}"
  hits=$(grep -rniE "$pattern" "${INCLUDES[@]}" "${EXCLUDES[@]}" . 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "FAIL [$label]"
    echo "$hits" | sed 's/^/  /'
    echo
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "reference-guard: one or more forbidden patterns found above." >&2
  exit 1
fi

echo "reference-guard: OK"
