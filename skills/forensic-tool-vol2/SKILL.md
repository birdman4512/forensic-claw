---
name: forensic-tool-vol2
description: Use vol2 in Forensic Claw for lawful DFIR, cyber security, evidence triage, intrusion analysis, and case-backed forensic workflows. Run Volatility 2 for legacy memory image/plugin support.
---

# forensic-tool-vol2

Always invoke this tool through the Forensic Claw wrapper (the wrapper auto-logs the command and runs an upstream Volatility 2 image via Docker). From the workspace `/home/node/.openclaw/workspace`:

```bash
tools/run-vol2-tool.sh [args...]
```

Inside the tool container the case root is mounted at `/cases`, so reference evidence as `/cases/<case-id>/evidence/...`. Example: `tools/run-vol2-tool.sh -f /cases/<case-id>/evidence/mem.raw imageinfo`; then supply the correct `--profile` for plugins.

Requires `FORENSIC_CLAW_VOL2_IMAGE` to be set in `.env` (no canonical upstream image). The wrapper refuses to run with a clear error if it's unset.

## Case discipline

- Confirm the case id and scope before using this tool on evidence.
- Prefer read-only operation and work on copies where extraction/parsing creates output.
- Save substantive output under `/home/node/.openclaw/cases/<case-id>/outputs/`.
- Update the case `notes/worklog.md` and `status.json` when the run affects findings or next steps.

## History and skill maintenance

Every wrapper invocation is auto-logged (timestamp + command + exit code) to `/home/node/.openclaw/logs/tool-command-history.md`. After notable runs, append a richer entry to the active case `notes/worklog.md` covering scope/authorization, output files, result summary, and follow-up. Record failures too. If the run reveals a reusable option set, caveat, limitation, or fix, update this skill page. Do not store secrets or unrelated sensitive data.
