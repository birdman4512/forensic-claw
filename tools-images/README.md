# Forensic Claw - Tool Images

Dockerfiles for the heavyweight tool images consumed by the wrappers in [`workspace/tools/`](../workspace/tools/). The four containerized tools are sourced as follows:

| Tool | Image | Source |
|---|---|---|
| Plaso | `log2timeline/plaso:latest` | [Upstream Docker Hub](https://hub.docker.com/r/log2timeline/plaso) — used as-is, nothing to build |
| Nuclei | `projectdiscovery/nuclei:latest` | [Upstream Docker Hub](https://hub.docker.com/r/projectdiscovery/nuclei) — used as-is, nothing to build |
| Volatility 2 | `blacktop/volatility:2.6` | [Community on Docker Hub](https://hub.docker.com/r/blacktop/volatility) — used as-is, nothing to build |
| MemProcFS | `forensic-claw-memprocfs:latest` | **Built locally from [`memprocfs/Dockerfile`](memprocfs/Dockerfile)** |

Only MemProcFS needs a local build because there's no maintained upstream image.

## Build the MemProcFS image

```bash
docker build -t forensic-claw-memprocfs:latest tools-images/memprocfs/
```

The Dockerfile pulls the latest pinned MemProcFS Linux x64 release (currently `v5.17.7`). To bump the version:

```bash
docker build \
  --build-arg MEMPROCFS_TAG=v5.18 \
  --build-arg MEMPROCFS_ASSET=MemProcFS_files_and_binaries_v5.18.X-linux_x64-YYYYMMDD.tar.gz \
  -t forensic-claw-memprocfs:latest tools-images/memprocfs/
```

(Asset filenames change each release — find the current Linux x64 tarball name on the [MemProcFS releases page](https://github.com/ufrisk/MemProcFS/releases).)

## Why we don't ship our own vol2 image

Multiple maintained community images exist on Docker Hub (`blacktop/volatility`, `sk4la/volatility`, `cincan/volatility`, `phocean/volatility`). Re-baking another would just duplicate effort. The default in [`.env.example`](../.env.example) points at `blacktop/volatility:2.6`; swap it with `FORENSIC_CLAW_VOL2_IMAGE` if you prefer a different one.

## Why MemProcFS needs FUSE flags

MemProcFS's "mount" mode exposes the analyzed memory dump as a virtual filesystem via FUSE. Inside a container that requires `--cap-add SYS_ADMIN`, `--device /dev/fuse`, and an AppArmor exception. [`workspace/tools/run-memprocfs-tool.sh`](../workspace/tools/run-memprocfs-tool.sh) already adds those flags to the per-invocation `docker run`, so the gateway container itself doesn't need them.

If you only use MemProcFS in non-mount modes (e.g. `-forensic` analysis to dump artifacts to a directory), the FUSE flags aren't strictly required, but they don't hurt — the kernel only enforces them when actual FUSE mounts are attempted.
