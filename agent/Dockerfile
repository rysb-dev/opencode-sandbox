# OpenCode Agent Container
#
# This container runs opencode with common development tools installed.
# It has NO direct internet access - all outbound traffic goes through
# the squid proxy container.

FROM debian:bookworm-slim

ARG OPENCODE_VERSION=latest
ARG USER_UID=1000
ARG USER_GID=1000

# Install system dependencies and development tools
RUN apt-get update && apt-get install -y \
    # Essential tools
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    # Useful utilities
    ripgrep \
    jq \
    less \
    vim \
    # Build essentials
    build-essential \
    # For SSH proxy tunneling (git over SSH)
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Install Node.js (LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Go
ARG GO_VERSION=1.22.0
RUN curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz \
    | tar -C /usr/local -xzf -
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/coder/go"
ENV PATH="${GOPATH}/bin:${PATH}"

# Install Python with pip
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3 /usr/bin/python

# Install uv (Astral) - fast Python package manager
# Copy from official distroless image (recommended approach)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install opencode
RUN if [ "$OPENCODE_VERSION" = "latest" ]; then \
    curl -fsSL https://opencode.ai/install | bash; \
    else \
    curl -fsSL https://opencode.ai/install | VERSION="$OPENCODE_VERSION" bash; \
    fi \
    && mv /root/.local/bin/opencode /usr/local/bin/opencode 2>/dev/null \
    || find /root -name "opencode" -type f -executable 2>/dev/null | head -1 | xargs -I{} mv {} /usr/local/bin/opencode

# Create non-root user with host UID/GID
# Use existing group if GID already exists, otherwise create new group
RUN (getent group ${USER_GID} || groupadd -g ${USER_GID} coder) && \
    useradd -m -s /bin/bash -u ${USER_UID} -g ${USER_GID} coder

# Create necessary directories
RUN mkdir -p /workspace \
    && mkdir -p /home/coder/.config/opencode \
    && mkdir -p /home/coder/.cache/opencode \
    && mkdir -p /home/coder/.local/share/opencode \
    && mkdir -p /home/coder/.local/state/opencode \
    && mkdir -p /home/coder/.ssh \
    && mkdir -p /home/coder/go \
    && chown -R ${USER_UID}:${USER_GID} /workspace /home/coder

# Configure SSH to use proxy for git hosts
RUN printf '%s\n' \
    'Host github.com gitlab.com bitbucket.org' \
    '    ProxyCommand nc -X connect -x proxy:3128 %h %p' \
    > /home/coder/.ssh/config \
    && chown ${USER_UID}:${USER_GID} /home/coder/.ssh/config \
    && chmod 600 /home/coder/.ssh/config

# Set working directory
WORKDIR /workspace

# Switch to non-root user
USER coder

# Entrypoint copies SSH keys with correct permissions
ENTRYPOINT ["/entrypoint.sh"]
CMD ["opencode"]
