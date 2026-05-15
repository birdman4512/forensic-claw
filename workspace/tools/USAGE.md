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
| `tools/run-plaso-tool.sh <tool> [args...]` | `log2timeline/plaso:latest` | `OPENCLAW_CASES_HOST_PATH` |
| `tools/run-vol2-tool.sh [args...]` | _(set `FORENSIC_CLAW_VOL2_IMAGE`)_ | `OPENCLAW_CASES_HOST_PATH`, `FORENSIC_CLAW_VOL2_IMAGE` |
| `tools/run-memprocfs-tool.sh [args...]` | _(set `FORENSIC_CLAW_MEMPROCFS_IMAGE`)_ | `OPENCLAW_CASES_HOST_PATH`, `FORENSIC_CLAW_MEMPROCFS_IMAGE` |
| `tools/run-nuclei-tool.sh [args...]` | `projectdiscovery/nuclei:latest` | `OPENCLAW_CASES_HOST_PATH` |

Inside each tool container the case root is mounted at `/cases`, so args use **tool-container paths**:

```bash
tools/run-plaso-tool.sh log2timeline.py /cases/CASE-001/outputs/timeline.plaso /cases/CASE-001/evidence/source
tools/run-plaso-tool.sh psort.py -o l2tcsv -w /cases/CASE-001/outputs/timeline.csv /cases/CASE-001/outputs/timeline.plaso
tools/run-vol2-tool.sh -f /cases/CASE-001/evidence/mem.raw imageinfo
tools/run-nuclei-tool.sh -u https://target.example.com -o /cases/CASE-001/outputs/nuclei.txt
```

`OPENCLAW_CASES_HOST_PATH` must be set to the **absolute host path** of `./cases` (the docker daemon resolves bind-mounts against the host filesystem, not against the gateway container). Example: `OPENCLAW_CASES_HOST_PATH=/home/you/forensic-claw/cases`.

## Case helper

Create a standard case scaffold from templates (in-image, no docker socket needed):

```bash
tools/new-case.sh CASE-YYYYMMDD-01
```

Templates are read from `<case-root>/templates/`. The case is created at `<case-root>/<case-id>/` (flat — no doubled `cases/` segment).
