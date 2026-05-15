# =============================================================================
# Forensic Claw - MemProcFS image
# =============================================================================
# Packages a release of MemProcFS (https://github.com/ufrisk/MemProcFS) into
# a small Debian-based image with the runtime deps and FUSE bindings needed
# to mount memory dumps as a virtual filesystem.
#
# Build:
#   docker build -t forensic-claw-memprocfs:latest tools-images/memprocfs/
#
# Bump version with --build-arg:
#   docker build \
#     --build-arg MEMPROCFS_TAG=v5.17 \
#     --build-arg MEMPROCFS_ASSET=MemProcFS_files_and_binaries_v5.17.7-linux_x64-20260514.tar.gz \
#     -t forensic-claw-memprocfs:latest tools-images/memprocfs/
# =============================================================================
FROM debian:bookworm-slim

ARG MEMPROCFS_TAG=v5.17
ARG MEMPROCFS_ASSET=MemProcFS_files_and_binaries_v5.17.7-linux_x64-20260514.tar.gz

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        fuse3 \
        libfuse3-3 \
        libusb-1.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/ufrisk/MemProcFS/releases/download/${MEMPROCFS_TAG}/${MEMPROCFS_ASSET}" -o /tmp/memprocfs.tar.gz \
    && mkdir -p /opt/memprocfs \
    && tar -xzf /tmp/memprocfs.tar.gz -C /opt/memprocfs --strip-components=1 \
    && rm /tmp/memprocfs.tar.gz \
    && chmod +x /opt/memprocfs/memprocfs \
    && ln -s /opt/memprocfs/memprocfs /usr/local/bin/memprocfs

# MemProcFS loads vmm.so / leechcore.so / plugin .so files from its install dir.
ENV LD_LIBRARY_PATH=/opt/memprocfs

# Default mount point used when callers pass `-mount /mnt/memprocfs`.
RUN mkdir -p /mnt/memprocfs

WORKDIR /cases
ENTRYPOINT ["memprocfs"]
CMD ["-h"]
