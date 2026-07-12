---
name: forensic-tool-pyshark
description: Use pyshark in Forensic Claw for lawful DFIR, cyber security, evidence triage, intrusion analysis, and case-backed forensic workflows. Use Python/tshark-backed packet parsing when available.
---

# forensic-tool-pyshark

Output can be verbose. **Prefer delegating to `local-analyst`** (see `skills/delegate-to-local-analyst/SKILL.md`) rather than running it yourself:

```bash
tools/delegate-to-local-analyst.sh \
  "Run tools/run-forensic-tool.sh pyshark <args>. Report suspicious connections/protocols and a one-line summary." \
  600
```

Run it yourself only when you need to inspect exact raw output, need a fast turnaround, or the question is more exploratory than a single bounded ask. Direct invocation, through the Forensic Claw wrapper (auto-logs the command), from the workspace `/home/node/.openclaw/workspace`:

```bash
tools/run-forensic-tool.sh pyshark [args...]
```

The import may be available even if no CLI exists; verify with `python3 -c "import pyshark"`. Prefer tshark for simple outputs.

## Case discipline

- Confirm the case id and scope before using this tool on evidence.
- Prefer read-only operation and work on copies where extraction/parsing creates output.
- Save substantive output under `/home/node/.openclaw/cases/<case-id>/outputs/`.
- Update the case `notes/worklog.md` and `status.json` when the run affects findings or next steps.

## History and skill maintenance

Every wrapper invocation is auto-logged (timestamp + command + exit code) to `/home/node/.openclaw/logs/tool-command-history.md`. After notable runs, append a richer entry to the active case `notes/worklog.md` covering scope/authorization, output files, result summary, and follow-up. Record failures too. If the run reveals a reusable option set, caveat, limitation, or fix, update this skill page. Do not store secrets or unrelated sensitive data.
