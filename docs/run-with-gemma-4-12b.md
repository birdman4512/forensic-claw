# Running Forensic Claw on a local Gemma 4 12B

This guide replaces the cloud model (Claude / OpenAI) with **Google Gemma 4 12B**
served locally by **Ollama**, so Forensic Claw runs fully offline. The forensic
toolchain (Sleuth Kit, Volatility, Plaso, tshark, …) is unaffected — only the
agent's "brain" changes.

> **Read this first — capability expectations.** Gemma 4 12B is the variant
> Google markets for *local agentic workflows*, and it is far more reliable at
> multi-step tool use than the tiny E2B/E4B sizes. It is still well below
> Claude/GPT-class models on long, messy forensic chains. Expect more retries,
> the occasional malformed tool call, and thinner `findings.md` output. Treat
> this as "good enough to run real cases with supervision," not "drop-in
> equal to the cloud model."

---

## Quick start

One command does the whole thing — installs Ollama, pulls the model, writes the
config, and starts the gateway:

```powershell
.\start.ps1 -Model gemma      # Windows (PowerShell)
```

```bash
./start.sh --model gemma      # Linux / macOS
```

On a brand-new clone, just running `start` with no model flag (`.\start.ps1` /
`./start.sh`) **prompts** you to pick cloud or Gemma on first run and does the
same. Switch back to a cloud model later with `-Model cloud` / `--model cloud`,
or re-open the picker anytime with `-SelectModel` / `--select-model`.

> **First-run bind caveat:** Ollama serves on `127.0.0.1` by default, but the
> container reaches it over the host network — so it must listen on `0.0.0.0`.
> The script sets this for you, but a *already-running* Ollama has to be
> restarted once to pick it up:
> - **Windows:** quit Ollama from the system tray, relaunch, re-run `.\start.ps1`.
> - **Linux (systemd):** the script writes a drop-in and restarts the service
>   (needs `sudo`); if it couldn't, run `sudo systemctl restart ollama`.
> - **Linux/macOS (no systemd):** start `ollama serve` with `OLLAMA_HOST=0.0.0.0`.
>
> See [Troubleshooting](#troubleshooting). (Linux also needs the one-line
> `extra_hosts` change in [Step 6](#step-6--linux-hosts-only-expose-the-host-gateway).)

The rest of this document explains what that command does under the hood, how to
verify it, the manual steps, and troubleshooting.

---

## How model selection actually works here

Forensic Claw is a thin wrapper around the **OpenClaw** gateway, whose model
choice lives entirely in `./config/` (data-driven — no code change needed):

| File | Role |
|---|---|
| [`config/agents/main/agent/models.json`](../config/agents/main/agent/models.json) | **Provider definitions.** Each provider has `baseUrl`, `apiKey`, `auth`, `api`, and a `models[]` list. This is where we add Ollama. |
| [`config/openclaw.json`](../config/openclaw.json) | **Active model.** `agents.defaults.models` + `agents.defaults.model.primary` pick which `provider/model-id` runs. |
| [`config/agents/main/agent/auth-profiles.json`](../config/agents/main/agent/auth-profiles.json) | Stored API keys per provider (not needed for Ollama — the key is a placeholder). |

Because the provider schema already supports a custom `baseUrl` (the bundled
`codex` provider uses one), we point a new provider at Ollama's
OpenAI-compatible endpoint. No proxy, no image rebuild.

### The `onboard` wizard vs. the model selector

The README's model-selection step —

```bash
docker compose run --rm openclaw-cli onboard
```

— is an interactive wizard baked into the upstream OpenClaw image that **only
knows the two cloud providers** (Anthropic and OpenAI). It has no option for a
local / custom endpoint and can't be edited without binary-patching the image,
so it **cannot** set up Gemma on its own.

To give you a single "pick your model" entry point that offers **cloud OR local
Gemma**, this repo ships a thin wrapper:
[`scripts/select-model.ps1`](../scripts/select-model.ps1). It either:

- **Cloud** → delegates straight to `onboard` (unchanged), or
- **Gemma** → writes the Ollama provider into `models.json` and sets it active in
  `openclaw.json` for you (backing up both files as `*.bak` first).

So you have two ways to do the config:

- **Recommended:** run the selector (Steps 1 + 5 below) — no hand-editing.
- **Manual:** edit the two JSON files yourself (Steps 4–5) if you prefer to see
  exactly what changes.

Either way: **don't re-run the bare `onboard` wizard afterwards** to stay on
Gemma — it rewrites the active model in `openclaw.json` back to a cloud provider.
If you do (e.g. to switch back temporarily), just re-run
`select-model.ps1 -Choice gemma` to restore it. Your `ollama` provider block in
`models.json` is never clobbered — only the *active model* changes.

---

## Prerequisites

- **A GPU with ≥ 8 GB VRAM** (Gemma 4 12B at Q4 needs ~6.6 GB). It will run
  CPU-only on 16 GB+ system RAM but will be slow. Apple Silicon: 16 GB unified
  minimum.
- Forensic Claw already cloned (see the main [README](../README.md)). Ollama is
  installed in Step 2 below.

---

## Step 1 — Scaffold the config (first-time setups only)

The Gemma provider is written *into* existing `./config/` files, so those files
must exist first. If `./config/openclaw.json` already exists (a repo that's been
started before), **skip this step.**

On a fresh clone, generate the baseline config by running the wizard once — via
the selector or directly:

```powershell
.\scripts\select-model.ps1 -Choice cloud
# or equivalently:
docker compose run --rm openclaw-cli onboard
```

Pick any provider/model to get through it — your choice is overwritten in
Step 5. (You'll need a value in `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` in
`.env` for the wizard to proceed; it doesn't have to stay valid once you're on
Gemma.)

## Step 2 — Install Ollama and pull Gemma 4 12B

> The [Quick start](#quick-start) does this for you — `winget install` on
> Windows, `curl … | sh` on Linux/macOS, plus `ollama pull`. The steps below are
> for doing it by hand or understanding the moving parts. Skip the automation
> with `-SkipOllamaSetup` (PowerShell) / `--skip-ollama-setup` (bash).

Install Ollama on the **host** (not inside the container).

**Windows** — download and run the installer from <https://ollama.com/download/windows>,
or via winget:

```powershell
winget install Ollama.Ollama
```

**macOS** — download from <https://ollama.com/download/mac>, or:

```bash
brew install ollama
```

**Linux:**

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Confirm it's installed, then pull and smoke-test the model:

```powershell
ollama --version
ollama pull gemma4:12b
ollama run gemma4:12b "hello"   # sanity check; type /bye to exit
```

The first pull downloads ~7–8 GB.

## Step 3 — Make Ollama reachable from the container

> Also automated by the Quick start: `setx OLLAMA_HOST 0.0.0.0:11434` on Windows,
> a systemd drop-in (`sudo`) on Linux. The first-run bind caveat above still
> applies: an *already-running* Ollama must be restarted once to pick up the new
> address.

By default Ollama listens only on `127.0.0.1`, which the gateway container
**cannot** reach. Bind it to all interfaces so `host.docker.internal` works.

**Windows (PowerShell, persists across reboots):**

```powershell
setx OLLAMA_HOST "0.0.0.0:11434"
# Then fully quit Ollama from the system tray and relaunch it.
```

**macOS / Linux (current shell — make permanent in your shell profile or systemd):**

```bash
export OLLAMA_HOST=0.0.0.0:11434
ollama serve
```

Verify it's listening on all interfaces:

```powershell
curl http://localhost:11434/v1/models
```

You should see `gemma4:12b` in the JSON.

## Steps 4–5 — Configure the provider (recommended: use the selector)

The fastest path is to let the selector script do both Steps 4 and 5 for you —
it adds the provider and sets it active, backing up both files as `*.bak`:

```powershell
.\scripts\select-model.ps1 -Choice gemma          # Windows
```

```bash
bash scripts/select-model.sh --choice gemma       # Linux / macOS
```

That's it — skip to Step 6. The hand-edits below are the **exact equivalent** if
you'd rather do it manually. (The bash selector needs `python3` on the host for
the JSON edits.)

<details>
<summary>Manual alternative — edit the two JSON files yourself</summary>

### Step 4 (manual) — Add Ollama as a provider in `models.json`

Edit [`config/agents/main/agent/models.json`](../config/agents/main/agent/models.json).
Add an `ollama` entry inside `"providers"` (alongside the existing `codex`):

```jsonc
{
  "providers": {
    "ollama": {
      "baseUrl": "http://host.docker.internal:11434/v1",
      "apiKey": "ollama",
      "auth": "api_key",
      "api": "openai-completions",
      "models": [
        {
          "id": "gemma4:12b",
          "name": "Gemma 4 12B (local)",
          "api": "openai-completions",
          "input": ["text", "image"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "contextWindow": 128000,
          "maxTokens": 8192
        }
      ]
    }
    // ... keep the existing "codex" provider here ...
  }
}
```

Notes:
- `apiKey` is a throwaway string — Ollama ignores it but the field must be non-empty.
- `id` **must** exactly match the Ollama tag (`gemma4:12b`).
- `"api": "openai-completions"` targets Ollama's `/v1/chat/completions`. If the
  model fails to respond after everything else checks out, this enum is the most
  likely culprit — try `"openai"` or `"openai-responses"` instead (the exact
  string is set by the OpenClaw/pi-ai version in your base image).

### Step 5 (manual) — Make it the active model in `openclaw.json`

Edit [`config/openclaw.json`](../config/openclaw.json). Change the two model
references under `agents.defaults`:

```jsonc
"agents": {
  "defaults": {
    "workspace": "/home/node/.openclaw/workspace",
    "models": {
      "ollama/gemma4:12b": {}
    },
    "model": {
      "primary": "ollama/gemma4:12b"
    }
  }
}
```

(You can leave the `anthropic` entries under `auth.profiles` / `plugins` in
place as a fallback, or remove them. They're inert once `primary` points at
Ollama.)

</details>

## Step 6 — (Linux hosts only) expose the host gateway

On **Docker Desktop (Windows/macOS)** `host.docker.internal` resolves
automatically — skip this. On a **Linux** host, add the mapping to the
`openclaw-gateway` service in [`docker-compose.yml`](../docker-compose.yml):

```yaml
  openclaw-gateway:
    # ...
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

## Step 7 — Restart and verify

```powershell
docker compose up -d --force-recreate openclaw-gateway
docker compose logs -f openclaw-gateway
```

Then open the dashboard (default <http://localhost:18789>), start a conversation,
and ask something trivial ("what model are you?"). Watch the Ollama console on
the host — you should see the request land there, confirming traffic is going to
the local model and not to a cloud API.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Gateway logs show `ECONNREFUSED` / `connect host.docker.internal:11434` | Ollama isn't bound to `0.0.0.0` (Step 3) or wasn't restarted after `setx`. Re-check `curl http://localhost:11434/v1/models` from the host. |
| `model "gemma4:12b" not found` | The `id` in `models.json` doesn't match the pulled tag, or you didn't `ollama pull gemma4:12b`. |
| Connects but every turn errors / empty responses | Wrong `api` value — try `"openai"` or `"openai-responses"` in Step 4. |
| Agent ignores the change, still calls Anthropic | `model.primary` in `openclaw.json` not updated (Step 5), or you edited the `.bak` file instead of `openclaw.json`. Force-recreate the container — config loads at startup only. |
| Very slow / GPU not used | Model fell back to CPU. Confirm your GPU is visible to Ollama (`ollama ps` shows `GPU`), and that VRAM is sufficient. |
| Tool calls malformed, case files thin | Expected ceiling of a 12B local model. Keep tasks scoped, supervise closely, or fall back to a cloud model for the hardest cases. |

## Reverting to the cloud model

Set `agents.defaults.model.primary` (and `models`) back to
`anthropic/claude-opus-4-7` (or your OpenAI choice) in `openclaw.json`, then
`docker compose up -d --force-recreate openclaw-gateway`. Or just re-run the
wizard: `docker compose run --rm openclaw-cli onboard`.

---

## ⚠ Unrelated but important

While writing this I noticed
[`config/agents/main/agent/auth-profiles.json`](../config/agents/main/agent/auth-profiles.json)
contains a **real Anthropic API key in cleartext**, and `./config/` is inside
the repo. Confirm that file is git-ignored and the key hasn't been committed or
pushed; if it has, rotate it at <https://console.anthropic.com/>. Moving to a
local model is a good moment to remove that key entirely.

---

### Sources
- [Introducing Gemma 4 12B — Google](https://blog.google/innovation-and-ai/technology/developers-tools/introducing-gemma-4-12b/)
- [Bringing Gemma 4 12B to your Laptop: local, agentic workflows — Google Developers Blog](https://developers.googleblog.com/bringing-gemma-4-12b-to-your-laptop-unlocking-local-agentic-workflows-with-google-ai-edge/)
- [Gemma 4 12B on RTX 3060 / Ollama setup — RunAIatHome](https://www.runaiathome.com/blog/gemma-4-local-setup-guide/)
- [Ollama OpenAI-compatible API](https://github.com/ollama/ollama/blob/main/docs/openai.md)
