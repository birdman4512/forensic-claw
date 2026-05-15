---
name: forensic-tool-lsusb
description: Use lsusb in Forensic Claw for lawful DFIR, cyber security, evidence triage, intrusion analysis, and case-backed forensic workflows. List USB devices for host triage.
---

# forensic-tool-lsusb

Always invoke this tool through the Forensic Claw wrapper (the wrapper auto-logs the command). From the workspace `/home/node/.openclaw/workspace`:

```bash
tools/run-forensic-tool.sh lsusb [args...]
```

Useful for removable-device context on live authorized systems. Example: `tools/run-forensic-tool.sh lsusb`.

## Case discipline

- Confirm the case id and scope before using this tool on evidence.
- Prefer read-only operation and work on copies where extraction/parsing creates output.
- Save substantive output under `/home/node/.openclaw/cases/<case-id>/outputs/`.
- Update the case `notes/worklog.md` and `status.json` when the run affects findings or next steps.

## History and skill maintenance

Every wrapper invocation is auto-logged (timestamp + command + exit code) to `/home/node/.openclaw/logs/tool-command-history.md`. After notable runs, append a richer entry to the active case `notes/worklog.md` covering scope/authorization, output files, result summary, and follow-up. Record failures too. If the run reveals a reusable option set, caveat, limitation, or fix, update this skill page. Do not store secrets or unrelated sensitive data.
