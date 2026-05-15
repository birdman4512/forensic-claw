#!/usr/bin/env bash
# First-time workspace setup.
# - Copies tracked *.template.md files to their live names (only if the live
#   file doesn't already exist - safe to re-run).
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
