#!/usr/bin/env bash
# Forensic Claw - unified model selector (bash twin of select-model.ps1).
#
# Forensic Claw can run on a CLOUD model (Anthropic / OpenAI via OpenClaw's
# `onboard` wizard) or a LOCAL model served by Ollama on the host. This wrapper
# offers both:
#   - cloud: delegates to `onboard`.
#   - local: records the model in .env (docker-compose's init-config step
#            registers the Ollama provider on every start), sets it as the
#            active model, then installs Ollama + pulls the model on the host.
#
# Usage:
#   ./scripts/select-model.sh                  # interactive menu
#   ./scripts/select-model.sh --choice cloud   # run the onboard wizard
#   ./scripts/select-model.sh --choice local   # configure the local model (Ollama)
#   ./scripts/select-model.sh --choice local --model qwen2.5-coder:14b --model-name 'Qwen2.5 Coder 14B'
#   ./scripts/select-model.sh --choice local --skip-ollama-setup   # config only
#
# The local model MUST support tool-calling (Gemma 2/3/4 do NOT). Good choices:
# qwen3:14b (default), qwen2.5-coder:14b, llama3.1:8b. A discrete GPU is strongly
# recommended - see docs/run-with-local-model.md.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

choice=""
model="qwen3:14b"
model_name="Qwen3 14B (local)"
config_dir=""
skip_ollama=0

while [ $# -gt 0 ]; do
  case "$1" in
    --choice) choice="$2"; shift 2;;
    --choice=*) choice="${1#*=}"; shift;;
    --model) model="$2"; shift 2;;
    --model=*) model="${1#*=}"; shift;;
    --model-name) model_name="$2"; shift 2;;
    --model-name=*) model_name="${1#*=}"; shift;;
    --config-dir) config_dir="$2"; shift 2;;
    --config-dir=*) config_dir="${1#*=}"; shift;;
    --skip-ollama-setup) skip_ollama=1; shift;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

# Replace or append KEY=value in .env.
set_env() {
  key="$1"; val="$2"
  [ -f .env ] || : > .env
  if grep -qE "^${key}=" .env; then
    tmp=$(mktemp)
    # Use a sed delimiter unlikely to appear in a model id/name.
    sed -E "s#^${key}=.*#${key}=${val}#" .env > "$tmp" && mv "$tmp" .env
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}

# Resolve config dir (mirrors docker-compose's OPENCLAW_CONFIG_DIR).
if [ -z "$config_dir" ]; then
  config_dir="./config"
  if [ -f .env ]; then
    v=$(grep -E '^OPENCLAW_CONFIG_DIR=' .env | head -n 1 | cut -d= -f2- \
      | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' || true)
    [ -n "${v:-}" ] && config_dir="$v"
  fi
fi

# Interactive menu when --choice wasn't supplied.
if [ -z "$choice" ]; then
  echo "Select the model Forensic Claw should use:"
  echo "  [1] Cloud provider (Anthropic / OpenAI)  - runs the onboard wizard"
  echo "  [2] Local model via Ollama ($model)      - offline, no API key, needs a good GPU"
  printf "Enter 1 or 2: "
  read -r sel
  case "$sel" in
    1) choice="cloud";;
    2) choice="local";;
    *) echo "Invalid choice '$sel' - aborting." >&2; exit 1;;
  esac
fi
[ "$choice" = "gemma" ] && choice="local"   # deprecated alias

# Cloud path: hand off to the upstream wizard unchanged.
if [ "$choice" = "cloud" ]; then
  echo "==> launching OpenClaw onboard wizard (cloud providers)"
  exec docker compose run --rm openclaw-cli onboard
fi

if [ "$choice" != "local" ]; then
  echo "Unknown choice: $choice (expected 'cloud' or 'local')" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Local path. The Ollama provider is registered by docker-compose's init-config
# step (reading OPENCLAW_LOCAL_MODEL); here we record the choice in .env and set
# it as the active model in openclaw.json.
# ---------------------------------------------------------------------------
ref="ollama/$model"

echo "==> recording local model in .env (OPENCLAW_LOCAL_MODEL=$model)"
set_env OPENCLAW_LOCAL_MODEL "$model"
set_env OPENCLAW_LOCAL_MODEL_NAME "$model_name"

echo "==> setting active model to '$ref' in $config_dir/openclaw.json"
if command -v python3 >/dev/null 2>&1; then
  FC_CONFIG_DIR="$config_dir" FC_REF="$ref" python3 - <<'PY'
import json, os, secrets, pathlib
config_dir = pathlib.Path(os.environ['FC_CONFIG_DIR'])
ref = os.environ['FC_REF']
openclaw_path = config_dir / 'openclaw.json'

def gateway_token():
    envp = pathlib.Path('.env')
    if envp.exists():
        for line in envp.read_text().splitlines():
            if line.startswith('OPENCLAW_GATEWAY_TOKEN='):
                t = line.split('=', 1)[1].strip()
                if t and '#' not in t:
                    return t
    return secrets.token_hex(32)

if openclaw_path.exists():
    o = json.loads(openclaw_path.read_text())
else:
    o = {"agents": {"defaults": {"workspace": "/home/node/.openclaw/workspace",
                                 "models": {}, "model": {}}},
         "gateway": {"mode": "local",
                     "auth": {"mode": "token", "token": gateway_token()},
                     "port": 18789, "bind": "loopback",
                     "controlUi": {"allowInsecureAuth": True}},
         "tools": {"profile": "coding"}}
o.setdefault("agents", {}).setdefault("defaults", {})
o["agents"]["defaults"]["models"] = {ref: {}}
o["agents"]["defaults"].setdefault("model", {})["primary"] = ref
openclaw_path.parent.mkdir(parents=True, exist_ok=True)
openclaw_path.write_text(json.dumps(o, indent=2) + "\n")
print(f"    active model set to '{ref}'")
PY
else
  echo "!! python3 not found - recorded the model in .env, but couldn't set it as the"
  echo "   active model. Set agents.defaults.model.primary = '$ref' in"
  echo "   $config_dir/openclaw.json, or run the onboard wizard."
fi

echo
echo "Configured Forensic Claw to use $model_name ($ref)."

# ---------------------------------------------------------------------------
# Best-effort Ollama setup: install, bind to all interfaces, pull the model.
# Failures here warn but don't undo the config above. Skip with
# --skip-ollama-setup.
# ---------------------------------------------------------------------------
if [ "$skip_ollama" -eq 1 ]; then
  echo
  echo "Skipped Ollama setup (--skip-ollama-setup). Remember to:"
  echo "  ollama pull $model; bind OLLAMA_HOST=0.0.0.0:11434; restart Ollama"
else
  # 1. Install if missing (Linux/macOS official installer).
  if ! command -v ollama >/dev/null 2>&1; then
    echo
    echo "==> Ollama not found - installing from https://ollama.com/install.sh"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL https://ollama.com/install.sh | sh || true
    fi
  fi

  if ! command -v ollama >/dev/null 2>&1; then
    echo "!! Ollama still isn't installed. Install it from https://ollama.com/download,"
    echo "   then re-run:  ./scripts/select-model.sh --choice local"
    exit 0
  fi

  # 2. Bind to all interfaces so the gateway container can reach it.
  case "${OLLAMA_HOST:-}" in
    *0.0.0.0*) : ;;  # already bound to all interfaces
    *)
      if command -v systemctl >/dev/null 2>&1 \
          && systemctl list-unit-files 2>/dev/null | grep -q '^ollama\.service'; then
        if command -v sudo >/dev/null 2>&1; then
          echo "==> binding the ollama systemd service to 0.0.0.0:11434 (needs sudo)"
          sudo mkdir -p /etc/systemd/system/ollama.service.d
          printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:11434"\n' \
            | sudo tee /etc/systemd/system/ollama.service.d/host.conf >/dev/null
          sudo systemctl daemon-reload
          sudo systemctl restart ollama || true
        else
          echo "!! Need to bind Ollama to 0.0.0.0 so the container can reach it. Run:"
          echo "   sudo systemctl edit ollama   # add: Environment=\"OLLAMA_HOST=0.0.0.0:11434\""
          echo "   sudo systemctl restart ollama"
        fi
      else
        export OLLAMA_HOST=0.0.0.0:11434
        echo "==> exported OLLAMA_HOST=0.0.0.0:11434 (start 'ollama serve' so it binds it)"
      fi
      ;;
  esac

  # 3. Pull the model.
  echo "==> pulling $model (first run downloads several GB)"
  ollama pull "$model" || echo "!! 'ollama pull $model' failed - check the tag and that Ollama is running."
fi

echo
echo "Done. Start (or restart) the gateway to load the model:"
echo "  docker compose up -d --force-recreate openclaw-gateway"
echo "  (or just re-run ./start.sh)"
