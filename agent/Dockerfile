# OpenCode Agent Container
#
# This container runs opencode with common development tools installed.
# It has NO direct internet access - all outbound traffic goes through
# the squid proxy container.

FROM debian:bookworm-slim

ARG OPENCODE_VERSION=latest

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
    && rm -rf /var/lib/apt/lists/*

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

# Install opencode
# Note: This requires network access during build, so we build before
# the container is placed on the internal network
RUN if [ "$OPENCODE_VERSION" = "latest" ]; then \
    curl -fsSL https://opencode.ai/install | bash; \
    else \
    curl -fsSL https://opencode.ai/install | VERSION="$OPENCODE_VERSION" bash; \
    fi \
    && find /root -name "opencode" -type f -executable 2>/dev/null | head -1 | xargs -I{} mv {} /usr/local/bin/opencode

# Create non-root user
RUN useradd -m -s /bin/bash coder

# Create workspace and config directories
RUN mkdir -p /workspace \
    && mkdir -p /home/coder/.config/opencode \
    && mkdir -p /home/coder/go \
    && chown -R coder:coder /workspace /home/coder

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy default opencode config
COPY opencode.json /home/coder/.config/opencode/config.json
RUN chown coder:coder /home/coder/.config/opencode/config.json

# Set working directory
WORKDIR /workspace

# Switch to non-root user
USER coder

ENTRYPOINT ["/entrypoint.sh"]
CMD ["opencode"]
