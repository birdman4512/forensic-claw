# Forensic Claw Tool Wrappers

Forensic tools run **directly inside the OpenClaw gateway container** (no docker-in-docker). The image baked by the project Dockerfile already contains the tools. Each wrapper logs every invocation to the project log volume.

```bash
tools/run-forensic-tool.sh <tool> [args...]
```

Defaults:
- log file: `${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}/tool-command-history.md`
- case root (referenced by `new-case.sh`): `${FORENSIC_CLAW_CASE_ROOT:-/home/node/.openclaw/cases}`

Examples:

```bash
tools/run-forensic-tool.sh file /home/node/.openclaw/cases/CASE-001/evidence/artifact.bin
tools/run-forensic-tool.sh sha256sum /home/node/.openclaw/cases/CASE-001/evidence/artifact.bin
tools/run-forensic-tool.sh vol -f /home/node/.openclaw/cases/CASE-001/evidence/memdump.raw windows.info
tools/run-forensic-tool.sh tshark -r /home/node/.openclaw/cases/CASE-001/evidence/capture.pcap -q -z io,phs
```

Use preservation-first, scoped, reproducible commands. Record substantive work in the case worklog.

## Wrapper map

- `tools/run-forensic-tool.sh <tool> [args...]` — generic forensic tool runner (logs and execs).
- `tools/run-plaso-tool.sh <tool> [args...]` — Plaso (`log2timeline.py`, `psort.py`). **Requires** Plaso to be installed in the image; not bundled by default.
- `tools/run-vol2-tool.sh [vol2 args...]` — Volatility 2 (`vol2`). Backed by a stub in the image; replace it with a real Volatility 2 install if you need legacy plugin/profile support.

## Case helper

Create a standard case scaffold from templates:

```bash
tools/new-case.sh CASE-YYYYMMDD-01
```

Templates are read from `<case-root>/templates/`. The case is created at `<case-root>/<case-id>/` (flat — no doubled `cases/` segment).
