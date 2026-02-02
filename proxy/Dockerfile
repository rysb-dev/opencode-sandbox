# Squid Proxy Container for OpenCode Sandbox
#
# This container runs a squid proxy that only allows connections to
# explicitly whitelisted domains. It acts as the network gatekeeper
# for the agent container.
#
# Supports optional upstream (corporate) proxy via environment variables:
#   UPSTREAM_PROXY_HOST - Upstream proxy hostname
#   UPSTREAM_PROXY_PORT - Upstream proxy port (default: 3128)
#   NO_PROXY_DOMAINS    - Comma-separated domains to access directly (no upstream proxy)

FROM debian:bookworm-slim

# Install squid and netcat for health checks
RUN apt-get update && apt-get install -y \
    squid \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Create directories for squid with proper permissions
RUN mkdir -p /var/spool/squid /var/log/squid \
    && chown -R proxy:proxy /var/spool/squid /var/log/squid

# Copy squid configuration
COPY squid.conf /etc/squid/squid.conf
COPY allowed_domains.txt /etc/squid/allowed_domains.txt

# Create empty upstream proxy config (will be populated by entrypoint if needed)
RUN touch /etc/squid/upstream_proxy.conf \
    && chown proxy:proxy /etc/squid/upstream_proxy.conf

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Initialize squid cache directories
RUN squid -N -z 2>/dev/null || true

# Expose the proxy port
EXPOSE 3128

# Use entrypoint to configure upstream proxy at runtime
ENTRYPOINT ["/entrypoint.sh"]
CMD ["squid", "-N", "-d", "1"]
