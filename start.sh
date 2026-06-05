#!/usr/bin/env bash
# Forensic Claw - one-shot start.
# Runs the host-side setup (templates, token, hooks), selects a model on first
# run, then brings up the gateway. Idempotent - safe to re-run on every start.
#
# Pass-through args go to `docker compose up`. Common ones:
#   ./start.sh                  # plain start (prompts for a model on first run)
#   ./start.sh --select-model   # (re)choose the model: cloud or local
#   ./start.sh --model local    # switch to the local model (Ollama), non-interactive
#   ./start.sh --model cloud    # run the cloud onboard wizard
#   ./start.sh --build          # rebuild image first (after Dockerfile change)
#   ./start.sh --force-recreate # recreate containers (after .env change)

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# Separate our own flags from args passed through to `docker compose up`.
select_model=0
model_choice=""
compose_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --select-model) select_model=1; shift;;
    --model) model_choice="$2"; shift 2;;
    --model=*) model_choice="${1#*=}"; shift;;
    *) compose_args+=("$1"); shift;;
  esac
done

if [ ! -f .env ]; then
  echo "==> .env missing - copying from .env.example"
  cp .env.example .env
  echo "    edit .env to add your API key + OPENCLAW_CASES_HOST_PATH, then re-run ./start.sh"
  exit 1
fi

./scripts/setup-workspace.sh

# ---------------------------------------------------------------------------
# Model selection. Auto-prompts on first run (no model configured yet); stays
# silent once a model is set. Force it anytime with --select-model / --model.
# ---------------------------------------------------------------------------
# cut the value, then strip any trailing inline comment (` # ...`, as docker
# compose does) and surrounding whitespace.
config_dir=$(grep -E '^OPENCLAW_CONFIG_DIR=' .env | head -n 1 | cut -d= -f2- \
  | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' || true)
config_dir="${config_dir:-./config}"
openclaw_path="$config_dir/openclaw.json"

primary=""
if [ -f "$openclaw_path" ]; then
  if command -v python3 >/dev/null 2>&1; then
    primary=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("agents",{}).get("defaults",{}).get("model",{}).get("primary","") or "")' "$openclaw_path" 2>/dev/null || true)
  else
    primary=$(grep -o '"primary"[[:space:]]*:[[:space:]]*"[^"]*"' "$openclaw_path" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
  fi
fi

model_changed=0
if [ "$select_model" -eq 1 ] || [ -n "$model_choice" ]; then
  if [ -n "$model_choice" ]; then bash scripts/select-model.sh --choice "$model_choice"; else bash scripts/select-model.sh; fi
  model_changed=1
elif [ -z "$primary" ]; then
  if [ ! -t 0 ]; then
    echo "==> no model configured and this isn't an interactive session." >&2
    echo "    run:  ./start.sh --model local   (or --model cloud)" >&2
    exit 1
  fi
  echo
  echo "==> no model configured yet"
  bash scripts/select-model.sh
  model_changed=1
else
  # The local Ollama provider is re-registered on every `docker compose up` by
  # the init-config step, so nothing to re-apply here - just report.
  echo "==> model: $primary  (use ./start.sh --select-model to change)"
fi

# A config change only takes effect on a fresh container, so recreate.
if [ "$model_changed" -eq 1 ]; then
  case " ${compose_args[*]:-} " in
    *" --force-recreate "*) : ;;
    *) compose_args+=(--force-recreate);;
  esac
fi

gateway_port=$(grep -E '^OPENCLAW_GATEWAY_PORT=' .env | head -n 1 | cut -d= -f2- \
  | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')
gateway_port="${gateway_port:-18789}"

echo
echo "==> docker compose up -d openclaw-gateway ${compose_args[*]:-}"
docker compose up -d openclaw-gateway "${compose_args[@]:+${compose_args[@]}}"

echo
echo "==> waiting for gateway healthcheck"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  container_id=$(docker compose ps -q openclaw-gateway 2>/dev/null || true)
  if [ -n "$container_id" ]; then
    s=$(docker inspect "$container_id" --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
  else
    s="missing"
  fi
  printf "    t+%ss: %s\n" "$((i*5))" "$s"
  if [ "$s" = "healthy" ]; then
    echo
    echo "Gateway up at http://localhost:$gateway_port"
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
