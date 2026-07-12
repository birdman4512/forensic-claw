# Forensic Claw Tool Wrappers

Two execution paths:

1. **In-image tools** — most of the toolchain is baked into the gateway image. The generic wrapper execs them directly, no docker socket required.
2. **Containerized tools** — heavy or hard-to-install tools (plaso, vol2, memprocfs, nuclei) run inside ephemeral upstream Docker containers. These need `/var/run/docker.sock` mounted into the gateway (already wired up in `docker-compose.yml`).

Every wrapper auto-logs to `${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}/tool-command-history.md`.

## In-image tools

```bash
tools/run-forensic-tool.sh <tool> [args...]
```

Reference files using gateway paths: `/home/node/.openclaw/cases/<case-id>/...`.

Examples:

```bash
tools/run-forensic-tool.sh file /home/node/.openclaw/cases/CASE-001/evidence/artifact.bin
tools/run-forensic-tool.sh sha256sum /home/node/.openclaw/cases/CASE-001/evidence/artifact.bin
tools/run-forensic-tool.sh tshark -r /home/node/.openclaw/cases/CASE-001/evidence/capture.pcap -q -z io,phs
tools/run-forensic-tool.sh vol -f /home/node/.openclaw/cases/CASE-001/evidence/memdump.raw windows.info
```

## Containerized tools

| Wrapper | Default image | Required env |
|---|---|---|
| `tools/run-plaso-tool.sh <tool> [args...]` | `log2timeline/plaso:latest` (upstream) | `OPENCLAW_CASES_HOST_PATH` |
| `tools/run-vol2-tool.sh [args...]` | `blacktop/volatility:2.6` (community) | `OPENCLAW_CASES_HOST_PATH` |
| `tools/run-memprocfs-tool.sh [args...]` | `forensic-claw-memprocfs:latest` (build locally from `tools-images/memprocfs/`) | `OPENCLAW_CASES_HOST_PATH` |
| `tools/run-nuclei-tool.sh [args...]` | `projectdiscovery/nuclei:latest` (upstream) | `OPENCLAW_CASES_HOST_PATH` |

Plaso, vol2, and nuclei images pull on first use. MemProcFS has no upstream image — build it locally first: `docker build -t forensic-claw-memprocfs:latest tools-images/memprocfs/`.

Inside each tool container the case root is mounted at `/cases`, so args use **tool-container paths**:

```bash
tools/run-plaso-tool.sh log2timeline.py /cases/CASE-001/outputs/timeline.plaso /cases/CASE-001/evidence/source
tools/run-plaso-tool.sh psort.py -o l2tcsv -w /cases/CASE-001/outputs/timeline.csv /cases/CASE-001/outputs/timeline.plaso
tools/run-vol2-tool.sh -f /cases/CASE-001/evidence/mem.raw imageinfo
tools/run-nuclei-tool.sh -u https://target.example.com -o /cases/CASE-001/outputs/nuclei.txt
```

`OPENCLAW_CASES_HOST_PATH` must be set to the **absolute host path** of `./cases` (the docker daemon resolves bind-mounts against the host filesystem, not against the gateway container). Example: `OPENCLAW_CASES_HOST_PATH=/home/you/forensic-claw/cases`.

## Delegating to a local model

For vol, vol2, memprocfs, tshark, pyshark, log2timeline.py, or psort.py,
you can hand the whole sub-task (run the tool, read the output, answer a
question) to `local-analyst` — a second, always-local agent — instead of
running it yourself. Keeps large raw tool output and the reasoning about
it out of your own context.

```bash
tools/delegate-to-local-analyst.sh "<task message>" [timeout-seconds]
```

See [`skills/delegate-to-local-analyst/SKILL.md`](../../skills/delegate-to-local-analyst/SKILL.md)
and [`docs/local-analyst-delegation.md`](../../docs/local-analyst-delegation.md).

## Case helper

Create a standard case scaffold from templates (in-image, no docker socket needed):

```bash
tools/new-case.sh CASE-YYYYMMDD-01
```

Templates are read from `<case-root>/templates/`. The case is created at `<case-root>/<case-id>/` (flat — no doubled `cases/` segment).
