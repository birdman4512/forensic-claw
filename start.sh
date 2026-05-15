#!/usr/bin/env bash
# Forensic Claw - one-shot start.
# Runs the host-side setup (templates, token, hooks) then brings up the
# gateway. Idempotent - safe to re-run on every start.
#
# Pass-through args go to `docker compose up`. Common ones:
#   ./start.sh                  # plain start
#   ./start.sh --build          # rebuild image first (after Dockerfile change)
#   ./start.sh --force-recreate # recreate containers (after .env change)

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if [ ! -f .env ]; then
  echo "==> .env missing - copying from .env.example"
  cp .env.example .env
  echo "    edit .env to add your API key + OPENCLAW_CASES_HOST_PATH, then re-run ./start.sh"
  exit 1
fi

./scripts/setup-workspace.sh

echo
echo "==> docker compose up -d openclaw-gateway $*"
docker compose up -d openclaw-gateway "$@"

echo
echo "==> waiting for gateway healthcheck"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  s=$(docker inspect forensic-claw-openclaw-gateway-1 --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
  printf "    t+%ss: %s\n" "$((i*5))" "$s"
  if [ "$s" = "healthy" ]; then
    echo
    echo "Gateway up at http://localhost:${OPENCLAW_GATEWAY_PORT:-18789}"
    echo "Need a launch URL with token? run:"
    echo "    docker compose run --rm openclaw-cli dashboard --no-open"
    exit 0
  fi
  if [ "$s" = "unhealthy" ]; then
    echo
    echo "Gateway reported unhealthy - check logs:" >&2
    echo "    docker compose logs --tail 50 openclaw-gateway" >&2
    exit 1
  fi
  sleep 5
done

echo
echo "Gateway didn't reach healthy within 60s - check logs:" >&2
echo "    docker compose logs --tail 50 openclaw-gateway" >&2
exit 1
