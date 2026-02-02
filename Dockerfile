FROM debian:bookworm-slim

ARG OPENCODE_VERSION=latest

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    ripgrep \
    iptables \
    iproute2 \
    dnsutils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install opencode
# If OPENCODE_VERSION is "latest", install latest; otherwise install specific version
RUN if [ "$OPENCODE_VERSION" = "latest" ]; then \
        curl -fsSL https://opencode.ai/install | bash; \
    else \
        curl -fsSL https://opencode.ai/install | VERSION="$OPENCODE_VERSION" bash; \
    fi \
    && find /root -name "opencode" -type f -executable 2>/dev/null | head -1 | xargs -I{} mv {} /usr/local/bin/opencode

# Create non-root user for running opencode
RUN useradd -m -s /bin/bash coder

# Create workspace directory
RUN mkdir -p /workspace && chown coder:coder /workspace

# Create opencode config directory with default config that requires permission for all tools
RUN mkdir -p /home/coder/.config/opencode \
    && chown -R coder:coder /home/coder/.config

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy default opencode config (requires permission for tool calls)
COPY opencode.json /home/coder/.config/opencode/config.json
RUN chown coder:coder /home/coder/.config/opencode/config.json

# Default working directory
WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
CMD ["opencode"]
