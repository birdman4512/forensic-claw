# TOOLS-AVAILABLE.md - Forensic Claw

Forensic Claw runs inside the OpenClaw gateway container. Tools are baked into the image by the project Dockerfile. Wrappers under `tools/` execute them directly (no docker-in-docker) and auto-log every invocation.

## Wrapper map

From the workspace `/home/node/.openclaw/workspace` (host: `${OPENCLAW_WORKSPACE_DIR:-./workspace}`):

```bash
# Generic forensic tool runner (logs and execs)
tools/run-forensic-tool.sh <tool> [args...]

# Plaso (log2timeline / psort) - requires plaso to be installed in the image
tools/run-plaso-tool.sh <tool> [args...]

# Volatility 2 - currently backed by a stub; replace if you need real vol2 support
tools/run-vol2-tool.sh [vol2 args...]
```

The wrappers don't mount anything; they just exec the tool inside the gateway container. Reference files using their gateway-container paths (`/home/node/.openclaw/cases/<case-id>/...`).

## Tools available in the gateway image

Provided by the project [Dockerfile](../../Dockerfile):

- Hashing and integrity: `sha256sum`, `sha1sum`, `md5sum`
- File and metadata triage: `file`, `exiftool`, `binwalk`
- Disk and recovery: `fls`, `mmls`, `fsstat`, `istat`, `icat`, `testdisk`, `foremost`
- Memory analysis: `vol` (Volatility 3, via the `volatility3` Python package)
- Memory note: `vol2` and `memprocfs` are stubs that exit 1 with an "unavailable in this image" message; replace them in the Dockerfile if you need them.
- YARA and malware-adjacent triage: `yara`
- Network and packet analysis: `tcpdump`, `tshark`, `tcpflow`, `nmap`, `traceroute`, `dig`, `whois`
- Host/hardware triage: `lshw`, `lspci`, `lsusb`
- General support: `curl`, `wget`, `git`, `jq`, `rg`, `python3`, `httpie`
- Recon binaries: `subfinder`, `httpx-pd` (ProjectDiscovery httpx, renamed to avoid collision with the Python `httpx` library), `nuclei`, `amass`
- Python: `requests`, `httpx`, `openai`, `anthropic`, `binwalk`, `dnstwist`, `pyshark`, `volatility3`, `yq`
- Python packet parsing: `pyshark` as an import, not a CLI

## Plaso

Bundled via the pip install block in [Dockerfile](../../Dockerfile). Use `tools/run-plaso-tool.sh log2timeline.py ...` and `tools/run-plaso-tool.sh psort.py ...`.

## Volatility 2

Not bundled (the image installs a stub `vol2` that exits 1). To enable, replace the stub in [Dockerfile](../../Dockerfile) with a real Volatility 2 install and rebuild.

## Skills

Tool-specific instructions live under `skills/forensic-tool-*/SKILL.md`. Update the relevant skill whenever a run reveals a reusable option set, caveat, limitation, or fix.

## Tool run history

Every wrapper invocation is auto-logged (timestamp + cwd + command + exit code) to `/home/node/.openclaw/logs/tool-command-history.md` (host: `${OPENCLAW_LOGS_DIR:-./logs}/tool-command-history.md`). For substantive runs, also append a richer entry covering scope/authorization, output files, result summary, and follow-up to the active case worklog under `/home/node/.openclaw/cases/<case-id>/notes/worklog.md`.

## Source-of-truth checks

```bash
tools/run-forensic-tool.sh sh -lc 'for t in sha256sum sha1sum md5sum file exiftool binwalk fls mmls fsstat istat icat testdisk foremost vol yara tcpdump tshark tcpflow nmap traceroute dig whois lshw lspci lsusb curl wget git jq rg python3; do command -v "$t" >/dev/null && printf "%s %s\n" "$t" "$(command -v "$t")" || printf "%s MISSING\n" "$t"; done'
```

Do not claim a tool works unless it has been verified.
