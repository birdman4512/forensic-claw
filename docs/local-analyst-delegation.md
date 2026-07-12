# Hybrid architecture: frontier plans, local model executes

Forensic Claw's main agent (typically a frontier cloud model) plans an
investigation and calls tools directly. For the handful of forensic tools
whose output is genuinely large (Volatility, MemProcFS, tshark/pyshark,
Plaso), it can instead **delegate the whole sub-task** — run the tool, read
the output, answer a specific question — to `local-analyst`: a second,
fully local OpenClaw agent. Only the local model's compact answer comes
back into the main agent's context; the raw tool output never does, and no
frontier tokens are spent reading it.

This is a genuinely separate agent, not a summarization pass: `local-analyst`
decides how to run the tool and what the output means, using its own
tool-calling model. See [`skills/delegate-to-local-analyst/SKILL.md`](../skills/delegate-to-local-analyst/SKILL.md)
for how the main agent invokes it, and
[`workspace/tools/delegate-to-local-analyst.sh`](../workspace/tools/delegate-to-local-analyst.sh)
for the wrapper.

## Why a second gateway container, not a second agent in the same process

OpenClaw supports multiple named agents (`openclaw agents add`) within one
gateway process, but they all share that process's `OPENCLAW_SKILLS_DIR` —
there's no per-agent skill scoping. `local-analyst` needs a much smaller
skill set than the main agent (it should only ever reach for the tools it's
actually delegated: vol, vol2, memprocfs, tshark, pyshark, log2timeline.py,
psort.py — not all 35+ `forensic-tool-*` skills), both so its system prompt
fits comfortably in a small model's context window and so it isn't tempted
to go off and use tools nobody asked it to run. That requires a fully
separate gateway process with its own `OPENCLAW_SKILLS_DIR`, hence
`docker-compose.yml`'s `openclaw-gateway-local` service — its own config
dir (`config-local-analyst/`), own curated skills dir
(`skills-local-analyst/`), but the *same* workspace and cases as main, so
it can run the same tool wrappers against the same evidence.

## How delegation actually happens

The main agent's tool call is a shell script
(`workspace/tools/delegate-to-local-analyst.sh`) that runs:

```bash
docker exec forensic-claw-local-analyst node /app/dist/index.js agent \
  --agent main --message "<task>" --json --timeout <n>
```

`docker exec` rather than a network call: the main gateway already has
`/var/run/docker.sock` mounted (for the vol2/memprocfs/plaso wrappers), so
this reuses that instead of standing up gateway-to-gateway RPC. `--agent
main` refers to `local-analyst`'s *own* single agent (also confusingly
named `main` inside its isolated config — there's only one agent in that
process, so this is always its default).

## Two hard-won CPU-only gotchas

Both were found the hard way while wiring this up on a 16GB RAM, no-GPU
laptop — worth knowing if you touch `docker-compose.yml`'s
`init-config-local` block:

1. **Context window.** Ollama defaults new models to a 4096-token context.
   `local-analyst`'s system prompt (workspace bootstrap files + skill
   blocks) is a few thousand tokens on its own — it silently overflows a
   4096 window and every tool-calling turn just times out with no useful
   error. Fix: a derived model tag with a larger `num_ctx`:
   ```bash
   ollama create qwen3:1.7b-longctx -f - <<'EOF'
   FROM qwen3:1.7b
   PARAMETER num_ctx 16384
   EOF
   ```
   The declared `contextWindow` field in `openclaw.json`'s provider config
   does **not** set Ollama's actual context size — it's only used for
   OpenClaw's own token-budget accounting. The model tag's baked-in
   `num_ctx` is what Ollama actually uses.

2. **The idle-timeout watchdog only recognizes literal IPs, not
   `host.docker.internal`.** OpenClaw's gateway aborts a model request if
   no token arrives within a short idle window (~120s), *unless* it
   recognizes the provider's `baseUrl` as local/private — which lets slow
   CPU-only prompt processing run for many minutes without being killed.
   That recognition checks `URL(baseUrl).hostname` against literal
   loopback/private-IP/`.local` patterns; it does **no DNS resolution**.
   `http://host.docker.internal:11434` is a hostname, so it's treated as
   "remote" and gets the short timeout regardless of any configured
   `timeoutSeconds` — even though it resolves to a private IP
   (`192.168.65.254` on this Docker Desktop install). Fix: resolve the IP
   once and use it directly in the provider's `baseUrl`
   (`OPENCLAW_LOCAL_ANALYST_OLLAMA_HOST_IP` in `.env`):
   ```bash
   docker exec forensic-claw-local-analyst getent hosts host.docker.internal
   ```
   If Docker Desktop ever changes that IP on your machine, update the env
   var and run `docker compose up -d openclaw-gateway-local` to pick it up.

## Model sizing on CPU-only hardware

Bigger isn't better here. A 4B model measured **~150ms/token** on a
6-core/12-thread Ryzen 5625U (both prefill and decode) — a multi-thousand
token system prompt alone took over 10 minutes to process. Dropping to
1.7B cut that to **~5-25ms/token prefill, ~66ms/token decode** — roughly a
6-10x improvement, since CPU throughput for this box scales much better
with parameter count than expected. If delegated tasks still feel
sluggish, try an even smaller tool-calling model before reaching for a
bigger one; verify raw throughput directly against Ollama before wiring
it into OpenClaw:

```bash
curl http://localhost:11434/api/generate -d '{"model":"<tag>","prompt":"hi","stream":false}'
```

Look at `eval_duration / eval_count` (decode) and `prompt_eval_duration /
prompt_eval_count` (prefill) in the response, warm (second call, model
already loaded).

## Verify / troubleshoot

```bash
docker compose up -d openclaw-gateway-local
docker exec forensic-claw-local-analyst curl -s http://127.0.0.1:18789/healthz
docker exec forensic-claw-local-analyst node /app/dist/index.js agents list
```

Then smoke-test delegation end to end (from inside `openclaw-gateway`, cwd
`/home/node/.openclaw/workspace`):

```bash
bash tools/delegate-to-local-analyst.sh "Reply with exactly: pong"
```

If that hangs or times out, check `docker logs forensic-claw-local-analyst`
for `fetch timeout` / `idle watchdog` lines — that's gotcha #2 above, not a
hardware problem.
