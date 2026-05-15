# Forensic Claw

A Docker setup for running [OpenClaw](https://github.com/phioranex/openclaw-docker) pre-loaded with digital-forensics / incident-response tooling and the Forensic Claw agent skills.

## What you'll need

- **Docker Desktop** (Windows/macOS) or **Docker Engine + Docker Compose v2** (Linux). Verify with `docker --version` and `docker compose version`.
- **An API key** for the model provider you want to use:
  - Anthropic (Claude) — get one at [console.anthropic.com](https://console.anthropic.com/).
  - OpenAI — get one at [platform.openai.com/api-keys](https://platform.openai.com/api-keys).
  - You only need one. Both also work if you want to switch providers later.
- A free TCP port for the web dashboard (default `18789`).

## Step-by-step setup

### 1. Get the files

Clone or download this repo, then open a terminal in the project folder.

### 2. Configure your environment

Copy the env template and open it in your editor:

```bash
cp .env.example .env
```

Fill in the keys for whichever provider you'll use:

```dotenv
# Pick one (or both)
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...

# Generate a token to protect the dashboard
OPENCLAW_GATEWAY_TOKEN=          # run: openssl rand -hex 32

# (optional) change the timezone if you're not in Brisbane
OPENCLAW_TZ=Australia/Brisbane
```

The other variables in `.env.example` have sensible defaults — leave them alone unless you have a specific reason to change them.

### 3. Build the image

This installs the forensic toolchain (tshark, exiftool, volatility3, plaso, yara, …) into a custom Docker image. Takes 5–15 minutes the first time.

```bash
docker compose build
```

### 4. Run the onboarding wizard (this is where you pick the model)

```bash
docker compose run --rm openclaw-cli onboard
```

The wizard is interactive. It will:

- Detect the API keys you put in `.env`.
- Ask which **provider** to use (Anthropic, OpenAI, …).
- Ask which **model** to use within that provider — for Claude, pick the latest Sonnet or Opus model; for OpenAI, pick GPT-4o or newer.
- Save the choice into `./config/` so it persists across restarts.

You can re-run `onboard` any time to switch providers or models.

### 5. Start the gateway

```bash
docker compose up -d openclaw-gateway
```

### 6. Open the dashboard

Visit [http://localhost:18789](http://localhost:18789).

If you're prompted for a token, get the launch URL with:

```bash
docker compose run --rm openclaw-cli dashboard --no-open
```

Copy the printed URL into your browser — it includes the token.

That's it. You can now hand the agent a case (drop evidence into `./cases/<case-id>/evidence/` and ask it to analyze).

## Daily usage

```bash
# Start
docker compose up -d openclaw-gateway

# Stop
docker compose down

# Tail logs
docker compose logs -f openclaw-gateway

# Restart just the gateway (after changing .env)
docker compose restart openclaw-gateway

# Get a fresh dashboard token URL
docker compose run --rm openclaw-cli dashboard --no-open

# Switch model / re-run onboarding
docker compose run --rm openclaw-cli onboard
```

## Where your data lives

| Folder         | What's in it                                                            |
|----------------|-------------------------------------------------------------------------|
| `./config/`    | OpenClaw config, sessions, model selection, memory                      |
| `./workspace/` | Agent instructions, tool wrappers, skills the agent reads               |
| `./skills/`    | Per-tool skill pages (one folder per forensic tool)                     |
| `./cases/`     | Case folders (`<case-id>/{brief,findings,status,notes,evidence,outputs}`) |
| `./logs/`      | `tool-command-history.md` — every wrapper invocation, auto-logged       |

`./config/` and `./cases/` hold your real work — back them up. Everything else is reproducible from this repo.

## Troubleshooting

- **Build fails on `pip install plaso`** — Plaso pulls in a long native dependency chain. If the build OOMs, give Docker Desktop more memory (Settings → Resources → at least 4 GB).
- **Dashboard won't load** — confirm the gateway is running with `docker compose ps` and check `docker compose logs -f openclaw-gateway` for errors.
- **"Token required" loop** — get a fresh launch URL with `docker compose run --rm openclaw-cli dashboard --no-open`.
- **Want a different timezone in logs/timestamps** — set `OPENCLAW_TZ` in `.env` (uses standard tz database names like `America/New_York`) and `docker compose restart openclaw-gateway`.
- **Changed `.env` and nothing happened** — env changes only apply on container start. Run `docker compose up -d --force-recreate openclaw-gateway`.
