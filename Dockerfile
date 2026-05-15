# =============================================================================
# OpenClaw – Custom Image
# Extends the official image so you can pre-install tools that the Claw
# (and its sub-agents) can use at runtime.
# =============================================================================
ARG OPENCLAW_IMAGE=ghcr.io/phioranex/openclaw-docker:latest
FROM ${OPENCLAW_IMAGE}

# Switch to root only for package installation, then drop back.
USER root

# -----------------------------------------------------------------------------
# Patch pi-ai's OpenAI Codex provider to present as chatgpt-web rather than pi.
# Best-effort: if the upstream pi-ai layout changes (file moves, header block
# refactored), warn and continue rather than failing the whole build. Re-check
# the warning on each base-image bump and update the path/old-block as needed.
# -----------------------------------------------------------------------------
RUN python3 - <<'PY'
from pathlib import Path
p = Path('/app/node_modules/@mariozechner/pi-ai/dist/providers/openai-codex-responses.js')
old = '    headers.set("originator", "pi");\n    const userAgent = _os ? `pi (${_os.platform()} ${_os.release()}; ${_os.arch()})` : "pi (browser)";\n    headers.set("User-Agent", userAgent);\n'
new = '    headers.set("originator", "chatgpt-web");\n    const userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36";\n    headers.set("User-Agent", userAgent);\n'
if not p.exists():
    print(f"WARN: {p} not present in base image - skipping pi-ai originator/UA patch")
else:
    text = p.read_text()
    if old not in text:
        print(f"WARN: expected header block not found in {p} - upstream pi-ai layout changed; skipping patch")
    else:
        p.write_text(text.replace(old, new, 1))
        print(f"patched {p}")
PY

# -----------------------------------------------------------------------------
# System tools
# Add or remove packages here – these become available inside the sandbox.
# -----------------------------------------------------------------------------
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        bzip2 \
        ca-certificates \
        curl \
        dnsutils \
        exiftool \
        ffmpeg \
        file \
        foremost \
        git \
        httpie \
        jq \
        libbz2-dev \
        libffi-dev \
        libgdbm-dev \
        libimage-exiftool-perl \
        liblzma-dev \
        libmagic1 \
        libncurses5-dev \
        libnss3-dev \
        libreadline-dev \
        libsqlite3-dev \
        libssl-dev \
        lshw \
        nmap \
        pciutils \
        python3 \
        python3-dev \
        python3-distutils \
        python3-pip \
        python3-setuptools \
        python3-venv \
        ripgrep \
        sleuthkit \
        tar \
        tcpdump \
        tcpflow \
        testdisk \
        tk-dev \
        traceroute \
        tshark \
        unzip \
        usbutils \
        uuid-dev \
        wget \
        whois \
        wireshark-common \
        xz-utils \
        yara \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Python packages available to agents
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir --break-system-packages pipx \
    && pipx ensurepath

RUN pip3 install --break-system-packages --no-cache-dir \
    anthropic \
    binwalk \
    dnstwist \
    httpx \
    openai \
    plaso \
    pyshark \
    requests \
    volatility3 \
    yq

# -----------------------------------------------------------------------------
# Stubs for tools not available in this image (keep paths invocable).
# -----------------------------------------------------------------------------
RUN printf '%s\n' '#!/bin/sh' 'echo "vol2 unavailable in this image" >&2' 'exit 1' > /usr/local/bin/vol2 \
    && chmod +x /usr/local/bin/vol2

RUN printf '%s\n' '#!/bin/sh' 'echo "memprocfs unavailable in this image" >&2' 'exit 1' > /usr/local/bin/memprocfs \
    && chmod +x /usr/local/bin/memprocfs

# -----------------------------------------------------------------------------
# ProjectDiscovery + OWASP recon binaries
# -----------------------------------------------------------------------------
RUN curl -fsSL "https://github.com/projectdiscovery/subfinder/releases/download/v2.13.0/subfinder_2.13.0_linux_amd64.zip" -o /tmp/subfinder.zip \
    && unzip -q /tmp/subfinder.zip -d /tmp/subfinder \
    && install -m 0755 /tmp/subfinder/subfinder /usr/local/bin/subfinder \
    && rm -rf /tmp/subfinder.zip /tmp/subfinder

RUN curl -fsSL "https://github.com/projectdiscovery/httpx/releases/download/v1.9.0/httpx_1.9.0_linux_amd64.zip" -o /tmp/httpx.zip \
    && unzip -q /tmp/httpx.zip -d /tmp/httpx \
    && install -m 0755 /tmp/httpx/httpx /usr/local/bin/httpx-pd \
    && rm -rf /tmp/httpx.zip /tmp/httpx

RUN curl -fsSL "https://github.com/projectdiscovery/nuclei/releases/download/v3.7.1/nuclei_3.7.1_linux_amd64.zip" -o /tmp/nuclei.zip \
    && unzip -q /tmp/nuclei.zip -d /tmp/nuclei \
    && install -m 0755 /tmp/nuclei/nuclei /usr/local/bin/nuclei \
    && rm -rf /tmp/nuclei.zip /tmp/nuclei

RUN curl -fsSL "https://github.com/owasp-amass/amass/releases/download/v5.1.1/amass_linux_amd64.tar.gz" -o /tmp/amass.tar.gz \
    && mkdir -p /tmp/amass \
    && tar -xzf /tmp/amass.tar.gz -C /tmp/amass \
    && install -m 0755 /tmp/amass/amass_linux_amd64/amass /usr/local/bin/amass \
    && rm -rf /tmp/amass.tar.gz /tmp/amass

# -----------------------------------------------------------------------------
# Node global packages (the base image already has Node)
# -----------------------------------------------------------------------------
# RUN npm install -g <package>

# Drop back to the non-root node user that OpenClaw expects.
USER node
