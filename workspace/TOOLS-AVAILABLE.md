# TOOLS-AVAILABLE.md - Forensic Claw

Forensic Claw runs inside the OpenClaw gateway container. Two execution paths:

1. **In-image tools** — most of the toolchain is baked into the gateway image by the project Dockerfile. The generic `tools/run-forensic-tool.sh` wrapper execs them directly inside the gateway and auto-logs every invocation.
2. **Containerized tools** — heavyweight or hard-to-install tools (plaso, vol2, memprocfs, nuclei) live in upstream Docker images. Their dedicated wrappers shell out to the host docker daemon via `/var/run/docker.sock` (mounted by `docker-compose.yml`).

## Wrapper map

From the workspace `/home/node/.openclaw/workspace` (host: `${OPENCLAW_WORKSPACE_DIR:-./workspace}`):

```bash
# In-image tools (no docker socket needed)
tools/run-forensic-tool.sh <tool> [args...]

# Containerized via upstream image (need docker socket)
tools/run-plaso-tool.sh   <log2timeline.py|psort.py> [args...]
tools/run-vol2-tool.sh    [vol2 args...]
tools/run-memprocfs-tool.sh [args...]
tools/run-nuclei-tool.sh  [nuclei args...]
```

Path conventions:
- For `tools/run-forensic-tool.sh ...` (in-image), reference files using gateway paths: `/home/node/.openclaw/cases/<case-id>/...`.
- For the containerized wrappers, reference files using **tool-container** paths: `/cases/<case-id>/...` (the host case root is bind-mounted at `/cases` inside each tool container).

## Tools available in the gateway image

Provided by the project [Dockerfile](../../Dockerfile):

- Hashing and integrity: `sha256sum`, `sha1sum`, `md5sum`
- File and metadata triage: `file`, `exiftool`, `binwalk`
- Disk and recovery: `fls`, `mmls`, `fsstat`, `istat`, `icat`, `testdisk`, `foremost`
- Memory analysis: `vol` (Volatility 3, via the `volatility3` Python package)
- YARA and malware-adjacent triage: `yara`
- Network and packet analysis: `tcpdump`, `tshark`, `tcpflow`, `nmap`, `traceroute`, `dig`, `whois`
- Host/hardware triage: `lshw`, `lspci`, `lsusb`
- General support: `curl`, `wget`, `git`, `jq`, `rg`, `python3`, `httpie`, `docker` (CLI only - daemon is on the host)
- Recon binaries (in-image): `subfinder`, `httpx-pd`, `amass`
- Python: `requests`, `httpx`, `openai`, `anthropic`, `binwalk`, `dnstwist`, `pyshark`, `volatility3`, `yq`
- Python packet parsing: `pyshark` as an import, not a CLI

## Containerized tools

| Tool | Wrapper | Default image | Configurable via |
|---|---|---|---|
| Plaso (log2timeline / psort) | `tools/run-plaso-tool.sh` | `log2timeline/plaso:latest` (upstream) | `FORENSIC_CLAW_PLASO_IMAGE` |
| Volatility 2 | `tools/run-vol2-tool.sh` | `blacktop/volatility:2.6` (community) | `FORENSIC_CLAW_VOL2_IMAGE` |
| MemProcFS | `tools/run-memprocfs-tool.sh` | `forensic-claw-memprocfs:latest` (built locally — see [`tools-images/memprocfs/`](../../tools-images/memprocfs/)) | `FORENSIC_CLAW_MEMPROCFS_IMAGE` |
| Nuclei | `tools/run-nuclei-tool.sh` | `projectdiscovery/nuclei:latest` (upstream) | `FORENSIC_CLAW_NUCLEI_IMAGE` |

Plaso, Vol2 and Nuclei pull their images from Docker Hub on first use. MemProcFS has no upstream image — build it locally before first use:

```bash
docker build -t forensic-claw-memprocfs:latest tools-images/memprocfs/
```

The MemProcFS wrapper also adds `--cap-add SYS_ADMIN` and `--device /dev/fuse` per invocation so the FUSE mount mode works without granting those caps to the gateway itself.

## Skills

Tool-specific instructions live under `skills/forensic-tool-*/SKILL.md`. Update the relevant skill whenever a run reveals a reusable option set, caveat, limitation, or fix.

## Tool run history

Every wrapper invocation is auto-logged (timestamp + cwd + image + command + exit code) to `/home/node/.openclaw/logs/tool-command-history.md` (host: `${OPENCLAW_LOGS_DIR:-./logs}/tool-command-history.md`). For substantive runs, also append a richer entry covering scope/authorization, output files, result summary, and follow-up to the active case worklog under `/home/node/.openclaw/cases/<case-id>/notes/worklog.md`.

## Source-of-truth checks

```bash
tools/run-forensic-tool.sh sh -lc 'for t in sha256sum sha1sum md5sum file exiftool binwalk fls mmls fsstat istat icat testdisk foremost vol yara tcpdump tshark tcpflow nmap traceroute dig whois lshw lspci lsusb curl wget git jq rg python3 docker; do command -v "$t" >/dev/null && printf "%s %s\n" "$t" "$(command -v "$t")" || printf "%s MISSING\n" "$t"; done'

tools/run-plaso-tool.sh log2timeline.py --version
tools/run-nuclei-tool.sh -version
```

Do not claim a tool works unless it has been verified.
