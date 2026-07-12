---
name: forensic-tool-log2timeline-py
description: Use log2timeline.py in Forensic Claw for lawful DFIR, cyber security, evidence triage, intrusion analysis, and case-backed forensic workflows. Create Plaso timelines from disk images, filesystems, or log collections.
---

# forensic-tool-log2timeline.py

log2timeline.py's run output (progress/status logging over a large source) can be very verbose, and the run itself can be slow. **Prefer delegating to `local-analyst`** (see `skills/delegate-to-local-analyst/SKILL.md`) rather than running it yourself, with a generous timeout:

```bash
tools/delegate-to-local-analyst.sh \
  "Run tools/run-plaso-tool.sh log2timeline.py /cases/<case-id>/outputs/timeline.plaso /cases/<case-id>/evidence/source. Report scope covered, errors, and notable warnings." \
  1800
```

Run it yourself only when you need to inspect exact raw output, need a fast turnaround, or the question is more exploratory than a single bounded ask. Direct invocation, through the Forensic Claw wrapper (auto-logs the command, runs the upstream `log2timeline/plaso` image via Docker), from the workspace `/home/node/.openclaw/workspace`:

```bash
tools/run-plaso-tool.sh log2timeline.py [args...]
```

Inside the tool container the case root is mounted at `/cases`, so use tool-container paths in args: `tools/run-plaso-tool.sh log2timeline.py /cases/<case-id>/outputs/timeline.plaso /cases/<case-id>/evidence/source`.

## Case discipline

- Confirm the case id and scope before using this tool on evidence.
- Prefer read-only operation and work on copies where extraction/parsing creates output.
- Save substantive output under `/home/node/.openclaw/cases/<case-id>/outputs/`.
- Update the case `notes/worklog.md` and `status.json` when the run affects findings or next steps.

## History and skill maintenance

Every wrapper invocation is auto-logged (timestamp + command + exit code) to `/home/node/.openclaw/logs/tool-command-history.md`. After notable runs, append a richer entry to the active case `notes/worklog.md` covering scope/authorization, output files, result summary, and follow-up. Record failures too. If the run reveals a reusable option set, caveat, limitation, or fix, update this skill page. Do not store secrets or unrelated sensitive data.
