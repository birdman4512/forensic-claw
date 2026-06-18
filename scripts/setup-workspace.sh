#!/usr/bin/env bash
# First-time workspace setup.
# - Copies tracked *.template.md files in workspace/ to their live names
#   (only if the live file doesn't already exist - safe to re-run).
# - Seeds an EXAMPLE-001 case from cases/templates/ if missing.
# - Auto-generates OPENCLAW_GATEWAY_TOKEN in .env if blank or still set to
#   the placeholder.
# - Wires git hooks at .githooks/ via core.hooksPath.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

echo "==> seeding workspace template files"
shopt -s nullglob
for tpl in workspace/*.template.md; do
  live="${tpl/.template./.}"
  if [ -e "$live" ]; then
    echo "    skip: $live already exists"
  else
    cp "$tpl" "$live"
    echo "    seed: $live (from $(basename "$tpl"))"
  fi
done
shopt -u nullglob

echo "==> seeding cases/EXAMPLE-001 from cases/templates/ (if missing)"
if [ ! -d cases/EXAMPLE-001 ]; then
  mkdir -p cases/EXAMPLE-001/notes cases/EXAMPLE-001/evidence cases/EXAMPLE-001/findings cases/EXAMPLE-001/outputs
  for f in brief.md status.json; do
    [ -f "cases/templates/$f" ] && cp "cases/templates/$f" "cases/EXAMPLE-001/$f"
  done
  if [ -f cases/templates/findings/findings.md ]; then
    cp cases/templates/findings/findings.md cases/EXAMPLE-001/findings/findings.md
  elif [ -f cases/templates/findings.md ]; then
    cp cases/templates/findings.md cases/EXAMPLE-001/findings/findings.md
  fi
  [ -f cases/templates/worklog.md ] && cp cases/templates/worklog.md cases/EXAMPLE-001/notes/worklog.md
  echo "    seeded cases/EXAMPLE-001/"
else
  echo "    skip: cases/EXAMPLE-001/ already exists"
fi

if [ -f .env ]; then
  echo "==> ensuring OPENCLAW_GATEWAY_TOKEN is a real value"
  current_token=$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' .env | head -n 1 | cut -d= -f2-)
  if [ -z "$current_token" ] \
      || [ "$current_token" = " " ] \
      || printf '%s' "$current_token" | grep -qE '(^| )#'; then
    new_token=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 64)
    if [ -n "$new_token" ]; then
      # Portable sed in-place: write to a temp file, replace.
      awk -v tok="$new_token" '
        BEGIN { found = 0 }
        /^OPENCLAW_GATEWAY_TOKEN=/ { print "OPENCLAW_GATEWAY_TOKEN=" tok; found = 1; next }
        { print }
        END { if (!found) print "OPENCLAW_GATEWAY_TOKEN=" tok }
      ' .env > .env.tmp && mv .env.tmp .env
      echo "    generated a fresh 64-hex-char token and wrote it to .env"
    else
      echo "    WARN: could not generate token (no openssl or xxd) - set OPENCLAW_GATEWAY_TOKEN manually"
    fi
  else
    echo "    skip: token already looks valid"
  fi
else
  echo "==> .env not present; skipping token check (run \`cp .env.example .env\` first)"
fi

if [ -d .git ]; then
  echo "==> wiring tracked git hooks at .githooks/"
  git config core.hooksPath .githooks
  chmod +x .githooks/* 2>/dev/null || true
  echo "    git hooks active (run \`git config --unset core.hooksPath\` to disable)"
else
  echo "==> skipping git hooks (no .git directory)"
fi

echo
echo "workspace setup OK"
