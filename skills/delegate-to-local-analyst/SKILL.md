---
name: delegate-to-local-analyst
description: Use when a forensic sub-task calls for a heavy/verbose tool (Volatility 3, Volatility 2, MemProcFS, tshark, pyshark, log2timeline.py, psort.py) and you want to keep the raw tool output and the model tokens spent reasoning about it off the frontier context. Delegates the whole sub-task - run the tool, read its output, answer a specific question - to a small local model.
---

# delegate-to-local-analyst

`local-analyst` is a second, fully local OpenClaw agent (own gateway container, own Ollama model, own curated skill set) that can run one of the following tools itself and answer questions about the result: **vol, vol2, memprocfs, tshark, pyshark, log2timeline.py, psort.py**. It shares this workspace (`tools/`, cases) with you, so it produces real output from real evidence, not a guess.

Use it when a sub-task is well-bounded (one tool run, one specific question) and the raw output would be large. Don't use it for case judgment calls, multi-step planning, or anything that needs your reasoning quality — it's a small model; keep the ask narrow and concrete.

```bash
tools/delegate-to-local-analyst.sh "<task message>" [timeout-seconds]
```

The task message must be self-contained — it has no memory of this conversation. Tell it exactly what to run (the real `tools/run-*.sh` invocation, with real evidence paths) and exactly what to report back. Example:

```bash
tools/delegate-to-local-analyst.sh \
  "Run tools/run-forensic-tool.sh vol -f /home/node/.openclaw/cases/CASE-001/evidence/mem.raw windows.pslist. Report any suspicious or unexpected process names, and a one-line summary. If nothing stands out, say so plainly." \
  600
```

Only its final text answer comes back to you — no raw tool output, no intermediate reasoning tokens.

## Timing

This runs on a small CPU-only model. A real tool-calling turn typically takes **2-5 minutes**, more for heavier tools (log2timeline.py over a large source can take much longer). The default timeout is 480s; pass a larger explicit timeout for heavy runs rather than letting it time out and retry. Don't use this for anything that needs a fast turnaround in-conversation — treat it like a background task.

## Case discipline

Same rules as running the tool yourself: confirm case id/scope/authorization before pointing it at real evidence, and note significant delegated findings in the case's `notes/worklog.md` (it does not do this for you). Every delegated call is logged to `/home/node/.openclaw/logs/tool-command-history.md`, and the tool run it performs is logged separately underneath that same entry.

## If it fails or times out

Its reply will say so plainly (`status=timeout` or similar) rather than hallucinate a result. If a task keeps timing out, either raise the timeout, narrow the ask, or just run the tool yourself via the normal `forensic-tool-*` skill — delegation is an optimization, not the only path.
