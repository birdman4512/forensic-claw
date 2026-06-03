#!/usr/bin/env bash
# Forensic Claw - unified model selector (bash twin of select-model.ps1).
#
# OpenClaw's built-in `onboard` wizard only knows the two CLOUD providers
# (Anthropic / OpenAI) and has no option for a local model. This wrapper adds
# that choice: pick a cloud provider (it just delegates to `onboard`) or the
# LOCAL Gemma 4 12B provider served by Ollama (it writes ./config/ directly,
# installs Ollama, and pulls the model).
#
# Usage:
#   ./scripts/select-model.sh                  # interactive menu
#   ./scripts/select-model.sh --choice cloud   # run the onboard wizard
#   ./scripts/select-model.sh --choice gemma   # configure local Gemma 4 12B
#   ./scripts/select-model.sh --choice gemma --model gemma4:27b --model-name 'Gemma 4 27B'
#   ./scripts/select-model.sh --choice gemma --skip-ollama-setup   # config only

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

choice=""
model="gemma4:12b"
model_name="Gemma 4 12B (local)"
ollama_url="http://host.docker.internal:11434/v1"
context_window="128000"
max_tokens="8192"
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
    --ollama-url) ollama_url="$2"; shift 2;;
    --ollama-url=*) ollama_url="${1#*=}"; shift;;
    --config-dir) config_dir="$2"; shift 2;;
    --config-dir=*) config_dir="${1#*=}"; shift;;
    --skip-ollama-setup) skip_ollama=1; shift;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

# Resolve config dir (mirrors docker-compose's OPENCLAW_CONFIG_DIR).
if [ -z "$config_dir" ]; then
  config_dir="./config"
  if [ -f .env ]; then
    v=$(grep -E '^OPENCLAW_CONFIG_DIR=' .env | head -n 1 | cut -d= -f2- || true)
    [ -n "${v:-}" ] && config_dir="$v"
  fi
fi

# Interactive menu when --choice wasn't supplied.
if [ -z "$choice" ]; then
  echo "Select the model Forensic Claw should use:"
  echo "  [1] Cloud provider (Anthropic / OpenAI)  - runs the onboard wizard"
  echo "  [2] Local Gemma 4 12B via Ollama         - offline, no API key"
  printf "Enter 1 or 2: "
  read -r sel
  case "$sel" in
    1) choice="cloud";;
    2) choice="gemma";;
    *) echo "Invalid choice '$sel' - aborting." >&2; exit 1;;
  esac
fi

# Cloud path: hand off to the upstream wizard unchanged.
if [ "$choice" = "cloud" ]; then
  echo "==> launching OpenClaw onboard wizard (cloud providers)"
  exec docker compose run --rm openclaw-cli onboard
fi

if [ "$choice" != "gemma" ]; then
  echo "Unknown choice: $choice (expected 'cloud' or 'gemma')" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Gemma path: write provider + active model into ./config/ via python3
# (loads existing config or scaffolds a minimal baseline if this is a fresh
# clone - config/ is gitignored so it may not exist yet).
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to edit the JSON config but wasn't found." >&2
  echo "       Install python3, or edit config by hand (see docs/run-with-gemma-4-12b.md)." >&2
  exit 1
fi

ref="ollama/$model"
FC_CONFIG_DIR="$config_dir" FC_MODEL="$model" FC_MODEL_NAME="$model_name" \
FC_OLLAMA_URL="$ollama_url" FC_CTX="$context_window" FC_MAXT="$max_tokens" \
python3 - <<'PY'
import json, os, secrets, pathlib

config_dir = pathlib.Path(os.environ['FC_CONFIG_DIR'])
model      = os.environ['FC_MODEL']
name       = os.environ['FC_MODEL_NAME']
url        = os.environ['FC_OLLAMA_URL']
ctx        = int(os.environ['FC_CTX'])
maxt       = int(os.environ['FC_MAXT'])
provider   = 'ollama'
ref        = f"{provider}/{model}"

models_path   = config_dir / 'agents' / 'main' / 'agent' / 'models.json'
openclaw_path = config_dir / 'openclaw.json'

def load(p, default):
    return json.loads(p.read_text()) if p.exists() else default

def backup_write(p, obj):
    p.parent.mkdir(parents=True, exist_ok=True)
    if p.exists():
        (p.parent / (p.name + '.bak')).write_text(p.read_text())
    p.write_text(json.dumps(obj, indent=2) + "\n")

def gateway_token():
    envp = pathlib.Path('.env')
    if envp.exists():
        for line in envp.read_text().splitlines():
            if line.startswith('OPENCLAW_GATEWAY_TOKEN='):
                t = line.split('=', 1)[1].strip()
                if t and '#' not in t:
                    return t
    return secrets.token_hex(32)

# models.json - add the ollama provider.
m = load(models_path, {"providers": {}})
m.setdefault("providers", {})
m["providers"][provider] = {
    "baseUrl": url, "apiKey": "ollama", "auth": "api_key", "api": "openai-completions",
    "models": [{
        "id": model, "name": name, "api": "openai-completions",
        "input": ["text", "image"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": ctx, "maxTokens": maxt,
    }],
}
backup_write(models_path, m)
print(f"    provider '{provider}' ({model}) written to {models_path}")

# openclaw.json - make it the active model (scaffold a baseline if missing).
o = load(openclaw_path, {
    "agents": {"defaults": {
        "workspace": "/home/node/.openclaw/workspace", "models": {}, "model": {}}},
    "gateway": {"mode": "local",
                "auth": {"mode": "token", "token": gateway_token()},
                "port": 18789, "bind": "loopback",
                "controlUi": {"allowInsecureAuth": True}},
    "tools": {"profile": "coding"},
})
o.setdefault("agents", {}).setdefault("defaults", {})
o["agents"]["defaults"]["models"] = {ref: {}}
o["agents"]["defaults"].setdefault("model", {})["primary"] = ref
backup_write(openclaw_path, o)
print(f"    active model set to '{ref}' in {openclaw_path}")
PY

echo
echo "Configured Forensic Claw to use $model_name ($ref)."
echo "Backups written alongside each file as *.bak."

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
    echo "   then re-run:  ./scripts/select-model.sh --choice gemma"
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
