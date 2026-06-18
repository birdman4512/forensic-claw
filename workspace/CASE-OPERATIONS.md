# CASE-OPERATIONS.md

Forensic Claw must treat substantive forensic requests as case work.
The durable case record belongs in the cases volume, not in the workspace.

## Case root

Inside the gateway container:
- `/home/node/.openclaw/cases/<case-id>/`

This is bind-mounted from `${OPENCLAW_CASES_DIR:-./cases}` on the host. Layout is **flat** — case ids sit directly under the cases root, alongside the `templates/` folder used by `tools/new-case.sh`. No doubled `cases/` segment.

Expected structure for an active case:
- `/home/node/.openclaw/cases/<case-id>/brief.md`
- `/home/node/.openclaw/cases/<case-id>/status.json`
- `/home/node/.openclaw/cases/<case-id>/findings/findings.md`
- `/home/node/.openclaw/cases/<case-id>/notes/worklog.md`
- `/home/node/.openclaw/cases/<case-id>/evidence/`
- `/home/node/.openclaw/cases/<case-id>/outputs/`

Use `tools/new-case.sh <case-id>` to seed this structure from the templates in `/home/node/.openclaw/cases/templates/`.

## Required behavior

1. Pick or create a case id.
2. Ensure the case directory exists under `/home/node/.openclaw/cases/<case-id>/` (run `tools/new-case.sh <case-id>` if it doesn't).
3. Update `status.json` immediately when work starts.
4. Append a work note to `notes/worklog.md` whenever:
   - work begins
   - a new analysis step starts
   - a notable finding is made
   - the work is blocked
   - the work completes
5. Keep `findings/findings.md` as the report-ready findings summary in the case folder.
6. Never leave progress only in chat.
7. Do not use the workspace as the primary storage location for case status, findings, or worklog state.

## Status expectations

Allowed values:
- `draft`
- `ready_for_forensics`
- `in_progress`
- `blocked`
- `review_ready`
- `completed`

## `status.json` schema

The canonical schema lives in `/home/node/.openclaw/cases/templates/status.json`. Minimum fields:

```json
{
  "caseId": "CASE-YYYYMMDD-01",
  "caseName": "",
  "createdAt": "",
  "updatedAt": "",
  "requestedBy": "",
  "assignedTo": "forensic-claw",
  "status": "in_progress",
  "phase": "triage",
  "priority": "normal",
  "authorizationConfirmed": false,
  "readOnlyRequired": true,
  "evidenceReady": false,
  "progressNote": "Initial triage started",
  "currentTask": "Reviewing provided artifact",
  "nextStep": "Extract key metadata and confirm hashes",
  "resumeFrom": "Continue from evidence triage using files already placed in evidence/",
  "lastUpdatedBy": "forensic-claw",
  "outputs": {
    "brief": "brief.md",
    "findings": "findings/findings.md",
    "findingsDir": "findings/",
    "notesDir": "notes/",
    "outputsDir": "outputs/"
  },
  "timestamps": {
    "queuedAt": "",
    "createdAt": "",
    "startedAt": "",
    "lastUpdatedAt": "",
    "completedAt": ""
  }
}
```

## Resume behavior

- On new work for an existing case, read `status.json` and `notes/worklog.md` first.
- If `status` is `in_progress` or `blocked`, resume from `currentTask`, `progressNote`, `nextStep`, and `resumeFrom`.
- Update `status.json` before continuing so the next checkpoint is explicit.
- If the case was interrupted, record the resumed action in `notes/worklog.md` before deeper analysis continues.

## Worklog format

Append-only markdown log in `notes/worklog.md`.

Each entry should include:
- timestamp
- actor (`forensic-claw`)
- action
- commands or artefacts involved
- short outcome
- next step

## If evidence is missing

Still create the case record and mark:
- `status`: `blocked`
- `progressNote`: clear reason evidence or access is missing
- append a worklog entry describing the blocker
