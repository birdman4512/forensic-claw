# TOOLS.md - Forensic Claw Local Notes

Case root (gateway container path): `/home/node/.openclaw/cases/` — bind-mounted from `${OPENCLAW_CASES_DIR:-./cases}` on the host. Layout is flat: `<case-root>/<case-id>/` and `<case-root>/templates/`.

Heavy forensic tools are run through:

```bash
tools/run-forensic-tool.sh <tool> [args...]
```

The wrapper executes the requested tool directly inside the gateway container (no docker-in-docker) and writes a one-line entry per invocation to `${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}/tool-command-history.md`.

Do not store secrets or live case evidence in this workspace. Store evidence, outputs, and worklogs in the case folder.
