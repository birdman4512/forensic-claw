---
name: forensic-tool-psort-py
description: Use psort.py in Forensic Claw for lawful DFIR, cyber security, evidence triage, intrusion analysis, and case-backed forensic workflows. Filter and export Plaso timeline stores into readable timelines.
---

# forensic-tool-psort.py

Always invoke this tool through the Forensic Claw wrapper (the wrapper auto-logs the command and runs the upstream `log2timeline/plaso` image via Docker). From the workspace `/home/node/.openclaw/workspace`:

```bash
tools/run-plaso-tool.sh psort.py [args...]
```

Inside the tool container the case root is mounted at `/cases`, so use tool-container paths in args. Use after `log2timeline.py`: `tools/run-plaso-tool.sh psort.py -o l2tcsv -w /cases/<case-id>/outputs/timeline.csv /cases/<case-id>/outputs/timeline.plaso`.

## Case discipline

- Confirm the case id and scope before using this tool on evidence.
- Prefer read-only operation and work on copies where extraction/parsing creates output.
- Save substantive output under `/home/node/.openclaw/cases/<case-id>/outputs/`.
- Update the case `notes/worklog.md` and `status.json` when the run affects findings or next steps.

## History and skill maintenance

Every wrapper invocation is auto-logged (timestamp + command + exit code) to `/home/node/.openclaw/logs/tool-command-history.md`. After notable runs, append a richer entry to the active case `notes/worklog.md` covering scope/authorization, output files, result summary, and follow-up. Record failures too. If the run reveals a reusable option set, caveat, limitation, or fix, update this skill page. Do not store secrets or unrelated sensitive data.
