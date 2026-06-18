---
name: pcap-case-analysis
description: Analyze forensic packet capture cases and produce report-ready outputs including timeline, IOCs, notable hosts, protocols, and command-backed findings. Use when examining .pcap evidence in case folders, especially when writing findings/findings.md, notes, or outputs for DFIR casework.
---

# PCAP Case Analysis

Use a preservation-first workflow.

## Workflow

1. Confirm evidence path and create `findings/`, `outputs/`, and `notes/` folders in the case directory if missing.
2. Record file metadata and hashes with `file` and `capinfos`.
3. Use `tshark` summaries first:
   - endpoints (`-z endpoints,ip`)
   - conversations (`-z conv,ip`)
   - protocol hierarchy (`-z io,phs`)
   - DNS statistics (`-z dns,tree`) when present
   - time bucket stats (`-z io,stat,...`) for timeline shaping
4. Extract focused artefacts into `outputs/`:
   - unique IPs
   - DNS queries/responses
   - HTTP hosts/URIs if present
   - TLS SNI if present
   - notable scan patterns or bursts
5. Separate observations from inference. Mark unknowns clearly.
6. Write findings into the case template with:
   - scope
   - commands used
   - key findings
   - evidence notes
   - uncertainties
   - recommended next steps

## Useful command patterns

```bash
file <pcap>
capinfos <pcap>
tshark -r <pcap> -q -z io,phs
tshark -r <pcap> -q -z endpoints,ip
tshark -r <pcap> -q -z conv,ip
tshark -r <pcap> -q -z dns,tree
```

## Timeline extraction

Use coarse buckets first, then tighten around bursts. Save packet summaries with frame time, src/dst, protocol, ports, and info into `outputs/` for later sorting.

## IOC extraction

At minimum capture:
- source and destination IPs
- domains queried/resolved
- URLs or URI paths if present
- TLS server names if present
- suspicious port patterns and scan targets

## Output style

Keep it concise, reproducible, and report-ready. Include exact commands used.
