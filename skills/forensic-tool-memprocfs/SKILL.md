---
name: forensic-tool-memprocfs
description: Use memprocfs in Forensic Claw for lawful DFIR, cyber security, evidence triage, intrusion analysis, and case-backed forensic workflows. Use MemProcFS if/when available for memory image filesystem-style analysis.
---

# forensic-tool-memprocfs

Always invoke this tool through the Forensic Claw wrapper (the wrapper auto-logs the command and runs an upstream MemProcFS image via Docker). From the workspace `/home/node/.openclaw/workspace`:

```bash
tools/run-memprocfs-tool.sh [args...]
```

Inside the tool container the case root is mounted at `/cases`, so reference evidence as `/cases/<case-id>/evidence/...`.

Requires `FORENSIC_CLAW_MEMPROCFS_IMAGE` to be set in `.env` (no canonical upstream image; build locally or point at a community image you trust). If the env var is unset the wrapper refuses to run with a clear error - in that case, say so and use Volatility instead.

## Case discipline

- Confirm the case id and scope before using this tool on evidence.
- Prefer read-only operation and work on copies where extraction/parsing creates output.
- Save substantive output under `/home/node/.openclaw/cases/<case-id>/outputs/`.
- Update the case `notes/worklog.md` and `status.json` when the run affects findings or next steps.

## History and skill maintenance

Every wrapper invocation is auto-logged (timestamp + command + exit code) to `/home/node/.openclaw/logs/tool-command-history.md`. After notable runs, append a richer entry to the active case `notes/worklog.md` covering scope/authorization, output files, result summary, and follow-up. Record failures too. If the run reveals a reusable option set, caveat, limitation, or fix, update this skill page. Do not store secrets or unrelated sensitive data.
