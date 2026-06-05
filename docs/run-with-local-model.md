# Running Forensic Claw on a local model (Ollama)

Forensic Claw can run its agent "brain" on a **local model served by Ollama**
instead of a cloud provider, so it works fully offline with no API key. The
forensic toolchain (Sleuth Kit, Volatility, Plaso, tshark, …) is unaffected —
only the model changes.

> **Read this first.**
>
> 1. **You need a real GPU.** Ollama ignores integrated GPUs and falls back to
>    CPU, where a 12–14B model is far too slow for agent use (multi-minute turns
>    that hit the request timeout). A discrete GPU with enough VRAM for the model
>    (≈10 GB for a 14B at Q4, ≈16 GB unified on Apple Silicon) is strongly
>    recommended. On a laptop with only an integrated GPU, use a small model
>    (`llama3.2:3b`, `qwen3:4b`) or stick with a cloud model.
> 2. **The model must support tool-calling.** Forensic Claw is an agent — it
>    calls tools every turn. **Gemma 2 / 3 / 4 do *not* support tools** in Ollama
>    and will fail with `does not support tools`. (Gemma 4 12B is also macOS-only
>    — an Apple MLX build that won't pull on Windows/Linux at all.) Pick a
>    tool-capable model: **`qwen3:14b`** (default), `qwen2.5-coder:14b`,
>    `llama3.1:8b`, `mistral-nemo:12b`.
> 3. **Quality.** Even a good 14B local model is below Claude/GPT-class on long,
>    messy forensic chains. Expect more retries and thinner `findings.md`. Good
>    enough to run real cases with supervision; not a drop-in equal to cloud.

---

## Quick start

One command installs Ollama, pulls the model, writes the config, and starts the
gateway:

```powershell
.\start.ps1 -Model local       # Windows (PowerShell)
```

```bash
./start.sh --model local       # Linux / macOS
```

On a brand-new clone, running `start` with no flag also **prompts** you to pick
cloud or local on first run. Switch back to cloud anytime with
`-Model cloud` / `--model cloud`, or reopen the picker with
`-SelectModel` / `--select-model`.

Use a different model:

```powershell
.\start.ps1 -SelectModel        # interactive, or:
.\scripts\select-model.ps1 -Choice local -Model 'qwen2.5-coder:14b' -ModelName 'Qwen2.5 Coder 14B'
```

```bash
./scripts/select-model.sh --choice local --model qwen2.5-coder:14b --model-name 'Qwen2.5 Coder 14B'
```

> **Bind caveat.** Ollama listens on `127.0.0.1` by default, but the gateway
> container reaches it over the host network, so it must listen on `0.0.0.0`. The
> script sets `OLLAMA_HOST=0.0.0.0:11434` for you, but an *already-running*
> Ollama must be restarted once to pick it up:
> - **Windows:** quit Ollama from the system tray, relaunch.
> - **Linux (systemd):** the script writes a drop-in and restarts (needs `sudo`);
>   otherwise `sudo systemctl restart ollama`.
> - **Linux/macOS (no systemd):** `OLLAMA_HOST=0.0.0.0:11434 ollama serve`.

---

## How it works under the hood

OpenClaw has **native Ollama support**, and that path is the one that works from
inside a container. The setup is data-driven — no image rebuild:

| Where | What |
|---|---|
| [`.env`](../.env.example) → `OPENCLAW_LOCAL_MODEL` / `_NAME` | **Source of truth for the model id.** Default `qwen3:14b`. |
| `docker-compose.yml` → `init-config` step | On every `docker compose up`, registers the Ollama provider from `.env` into `openclaw.json` (see below). Idempotent; never changes your active-model choice. |
| [`config/openclaw.json`](../config/openclaw.json) → `models.providers.ollama` | The provider the gateway's model resolver actually reads. Registered with the **native `"api": "ollama"`** (not `openai-completions`). |
| `config/openclaw.json` → `agents.defaults.model.primary` | The active model, e.g. `ollama/qwen3:14b`. Set by the selector. |
| [`config/agents/main/agent/auth-profiles.json`](../config/agents/main/agent/auth-profiles.json) → `ollama:default` | Placeholder credential (Ollama ignores it, but the gateway requires one for a non-loopback host). Seeded by `init-config`. |

Two non-obvious details that make or break this — both handled for you:

- **Native `api: "ollama"` is required.** The gateway runs an **SSRF guard** that
  blocks outbound requests to private IPs. A generic `openai-completions`
  provider pointed at `host.docker.internal` is *blocked* (`SsrfBlockedError`).
  The native Ollama provider gets a host-network exemption, so it's allowed.
- **The provider must list the model** (`models: [{ id: … }]`). With an empty
  `models[]`, the gateway tries to auto-discover on `127.0.0.1` (unreachable from
  the container) and resets the base URL. Listing the model keeps your
  `host.docker.internal` base URL.

The provider also carries `timeoutSeconds: 600`, since local inference is slow.

### Cloud vs. local

The bare `onboard` wizard only knows the two cloud providers, so this repo wraps
model selection in [`scripts/select-model.ps1`](../scripts/select-model.ps1) /
[`.sh`](../scripts/select-model.sh):

- **cloud** → delegates to `onboard` (Anthropic / OpenAI).
- **local** → records the model in `.env`, sets it active in `openclaw.json`,
  installs Ollama, and pulls the model.

Switching is non-destructive: the Ollama provider stays registered even on cloud
(it's just not `primary`), so flipping back to local is instant.

---

## Linux hosts only — expose the host gateway

On **Docker Desktop (Windows/macOS)** `host.docker.internal` resolves
automatically. On a **Linux** host, add the mapping to the `openclaw-gateway`
service in [`docker-compose.yml`](../docker-compose.yml):

```yaml
  openclaw-gateway:
    # ...
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

---

## Verify

```bash
# 1. Ollama reachable on all interfaces, model present:
curl http://localhost:11434/v1/models        # should list your model id

# 2. The gateway resolves and runs it:
docker compose run --rm openclaw-cli agent --agent main --message "what model are you?"
```

Watch the Ollama console on the host — you should see the request land there,
confirming traffic goes to the local model and not a cloud API.

---

## Troubleshooting

| Symptom (in `docker compose logs openclaw-gateway`) | Cause / fix |
|---|---|
| `does not support tools` | The model has no tool-calling (e.g. any Gemma). Switch to `qwen3:14b`, `qwen2.5-coder:14b`, `llama3.1:8b`, etc. |
| `SsrfBlockedError` / `Blocked … private/internal … IP` | Provider isn't the native `api: "ollama"`. Re-run `--model local` (or check `config/openclaw.json` → `models.providers.ollama.api == "ollama"`). |
| `Unknown model … no matching models.providers[…]` | Provider missing from `openclaw.json` → `models.providers`, or its `models[]` is empty. Re-run `--model local`, then `docker compose up -d --force-recreate openclaw-gateway`. |
| `No API key found for provider "ollama"` | Missing `ollama:default` auth profile. `init-config` seeds it on `docker compose up --force-recreate`. |
| `network connection error` / `ECONNREFUSED 11434` | Ollama not bound to `0.0.0.0`, or not restarted after the bind change. `curl http://localhost:11434/v1/models` from the host to confirm. |
| `model … requires a newer version of Ollama` / `pull model manifest: file does not exist` | Ollama too old for a freshly-released model. Update Ollama (or pick another tag). |
| `idle timeout` / extremely slow | Running on **CPU** (integrated GPU is ignored). `ollama ps` shows `100% CPU`. Use a discrete GPU, a much smaller model, or go cloud. `timeoutSeconds` is already 600. |
| Agent still calls the cloud provider | `agents.defaults.model.primary` isn't `ollama/<model>`. Re-run `--model local`, then force-recreate. |

---

## Reverting to a cloud model

```bash
./start.sh --model cloud        # or  .\start.ps1 -Model cloud
```

The Ollama provider stays registered but inactive; switch back with
`--model local` whenever you like.

---

## Security note

[`config/agents/main/agent/auth-profiles.json`](../config/agents/main/agent/auth-profiles.json)
stores provider credentials (including any real Anthropic/OpenAI key) in
cleartext, and `./config/` lives in the repo. Confirm `./config/` is git-ignored
and no key was ever committed; if one was, rotate it. Moving to a local model is
a good moment to remove cloud keys you no longer need.

---

### Sources
- [Ollama model library](https://ollama.com/library) — check a model's **Tools** capability before using it.
- [Ollama OpenAI-compatible API](https://github.com/ollama/ollama/blob/main/docs/openai.md)
