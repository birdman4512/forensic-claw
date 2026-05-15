# TOOLS.md - Forensic Claw Local Notes

Case root (gateway container path): `/home/node/.openclaw/cases/` — bind-mounted from `${OPENCLAW_CASES_DIR:-./cases}` on the host. Layout is flat: `<case-root>/<case-id>/` and `<case-root>/templates/`.

## In-image tools

Most of the toolchain runs directly inside the gateway container:

```bash
tools/run-forensic-tool.sh <tool> [args...]
```

The wrapper execs the tool inside the gateway, no docker socket needed. Logged to `${FORENSIC_CLAW_LOG_DIR:-/home/node/.openclaw/logs}/tool-command-history.md`.

## Containerized tools

Plaso, vol2, memprocfs, and nuclei run inside ephemeral containers spawned via the host docker daemon (`/var/run/docker.sock`):

```bash
tools/run-plaso-tool.sh   <log2timeline.py|psort.py> [args...]
tools/run-vol2-tool.sh    [vol2 args...]
tools/run-memprocfs-tool.sh [args...]
tools/run-nuclei-tool.sh  [nuclei args...]
```

Inside each tool container the case root appears at `/cases`, so args use tool-container paths: `/cases/<case-id>/evidence/...`, `/cases/<case-id>/outputs/...`.

## Configuration

| Setting | Default | Required? |
|---|---|---|
| `FORENSIC_CLAW_LOG_DIR` | `/home/node/.openclaw/logs` | no |
| `FORENSIC_CLAW_CASE_ROOT` | `/home/node/.openclaw/cases` | no |
| `OPENCLAW_CASES_HOST_PATH` (→ `FORENSIC_CLAW_CASES_HOST_DIR`) | _(unset)_ | **yes** for the four containerized wrappers |
| `FORENSIC_CLAW_PLASO_IMAGE` | `log2timeline/plaso:latest` | no |
| `FORENSIC_CLAW_NUCLEI_IMAGE` | `projectdiscovery/nuclei:latest` | no |
| `FORENSIC_CLAW_VOL2_IMAGE` | `blacktop/volatility:2.6` | no |
| `FORENSIC_CLAW_MEMPROCFS_IMAGE` | `forensic-claw-memprocfs:latest` (build locally — see [`tools-images/memprocfs/`](../../tools-images/memprocfs/)) | yes (build first) |

Do not store secrets or live case evidence in this workspace. Store evidence, outputs, and worklogs in the case folder.
