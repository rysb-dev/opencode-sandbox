# Squid Proxy Container for OpenCode Sandbox
#
# This container runs a squid proxy that only allows connections to
# explicitly whitelisted domains. It acts as the network gatekeeper
# for the agent container.

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

# Initialize squid cache directories
RUN squid -N -z 2>/dev/null || true

# Expose the proxy port
EXPOSE 3128

# Run squid in foreground mode
CMD ["squid", "-N", "-d", "1"]
