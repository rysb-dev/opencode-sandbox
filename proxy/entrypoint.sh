#!/bin/bash
# =============================================================================
# Squid Proxy Entrypoint
# =============================================================================
# Configures upstream (corporate) proxy if environment variables are set,
# then starts squid.
#
# Environment variables:
#   UPSTREAM_PROXY_HOST - Upstream proxy hostname (required for upstream proxy)
#   UPSTREAM_PROXY_PORT - Upstream proxy port (default: 3128)
#   NO_PROXY_DOMAINS    - Comma-separated domains to access directly (bypass upstream)
# =============================================================================

set -e

UPSTREAM_CONFIG="/etc/squid/upstream_proxy.conf"

# -----------------------------------------------------------------------------
# Generate upstream proxy configuration
# -----------------------------------------------------------------------------
generate_upstream_config() {
    # Start with empty config
    > "$UPSTREAM_CONFIG"

    if [ -z "$UPSTREAM_PROXY_HOST" ]; then
        echo "# No upstream proxy configured - direct connections"
        return
    fi

    local proxy_host="$UPSTREAM_PROXY_HOST"
    local proxy_port="${UPSTREAM_PROXY_PORT:-3128}"

    echo "[proxy] Configuring upstream proxy: ${proxy_host}:${proxy_port}"

    # Configure the parent proxy
    cat >> "$UPSTREAM_CONFIG" << EOF
# Upstream (corporate) proxy configuration
# Auto-generated at container startup

# Define the parent proxy
cache_peer ${proxy_host} parent ${proxy_port} 0 no-query default

EOF

    # Handle NO_PROXY domains - these should go direct, not through upstream
    if [ -n "$NO_PROXY_DOMAINS" ]; then
        echo "[proxy] Configuring no_proxy domains: ${NO_PROXY_DOMAINS}"

        # Create ACL for no_proxy domains
        echo "# Domains that bypass the upstream proxy (no_proxy)" >> "$UPSTREAM_CONFIG"
        echo "acl no_proxy_domains dstdomain" >> "$UPSTREAM_CONFIG"

        # Parse comma-separated list
        IFS=',' read -ra DOMAINS <<< "$NO_PROXY_DOMAINS"
        for domain in "${DOMAINS[@]}"; do
            # Trim whitespace
            domain=$(echo "$domain" | xargs)
            [ -z "$domain" ] && continue

            # Handle .domain.com format (add both with and without dot)
            if [[ "$domain" == .* ]]; then
                echo "acl no_proxy_domains dstdomain ${domain}" >> "$UPSTREAM_CONFIG"
                # Also add without leading dot
                echo "acl no_proxy_domains dstdomain ${domain#.}" >> "$UPSTREAM_CONFIG"
            else
                echo "acl no_proxy_domains dstdomain ${domain}" >> "$UPSTREAM_CONFIG"
                # Also add with leading dot for subdomains
                echo "acl no_proxy_domains dstdomain .${domain}" >> "$UPSTREAM_CONFIG"
            fi
        done

        echo "" >> "$UPSTREAM_CONFIG"

        # Go direct for no_proxy domains
        echo "# Bypass upstream proxy for no_proxy domains" >> "$UPSTREAM_CONFIG"
        echo "always_direct allow no_proxy_domains" >> "$UPSTREAM_CONFIG"
        echo "" >> "$UPSTREAM_CONFIG"
    fi

    # Force all other traffic through the parent proxy
    cat >> "$UPSTREAM_CONFIG" << EOF
# Send all other traffic through the upstream proxy
never_direct allow all
EOF

    echo "[proxy] Upstream proxy configuration complete"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "[proxy] Starting squid proxy..."

    # Generate upstream proxy config
    generate_upstream_config

    # Execute the command (default: squid)
    exec "$@"
}

main "$@"
