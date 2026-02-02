#!/bin/bash
# =============================================================================
# OpenCode Sandbox Entrypoint
# =============================================================================
# Sets up network whitelist using iptables, then runs opencode as non-root user.
#
# Environment variables:
#   ALLOWED_HOSTS - Comma-separated list of allowed hostnames
#   SKIP_FIREWALL - Set to "true" to skip firewall setup (for debugging)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[sandbox]${NC} $1"; }
log_success() { echo -e "${GREEN}[sandbox]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[sandbox]${NC} $1"; }
log_error()   { echo -e "${RED}[sandbox]${NC} $1"; }

setup_firewall() {
    if [ "$SKIP_FIREWALL" = "true" ]; then
        log_warn "Firewall setup skipped (SKIP_FIREWALL=true)"
        return
    fi

    if [ -z "$ALLOWED_HOSTS" ]; then
        log_warn "No ALLOWED_HOSTS specified - all network access allowed"
        return
    fi

    log_info "Setting up network whitelist..."

    # Flush existing rules
    iptables -F OUTPUT 2>/dev/null || true

    # Default policy: drop all outgoing traffic
    iptables -P OUTPUT DROP

    # Allow loopback (localhost)
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established/related connections (responses to allowed requests)
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow DNS resolution (required to resolve hostnames)
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

    # Resolve and allow each whitelisted host
    IFS=',' read -ra HOSTS <<< "$ALLOWED_HOSTS"
    for host in "${HOSTS[@]}"; do
        host=$(echo "$host" | xargs)  # trim whitespace
        [ -z "$host" ] && continue

        log_info "  Allowing: $host"

        # Resolve hostname to IP addresses
        ips=$(dig +short "$host" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)

        if [ -z "$ips" ]; then
            log_warn "    Could not resolve $host - skipping"
            continue
        fi

        for ip in $ips; do
            # Allow HTTPS (443), HTTP (80), and SSH (22) to resolved IPs
            iptables -A OUTPUT -d "$ip" -p tcp --dport 443 -j ACCEPT
            iptables -A OUTPUT -d "$ip" -p tcp --dport 80 -j ACCEPT
            iptables -A OUTPUT -d "$ip" -p tcp --dport 22 -j ACCEPT
            log_info "    -> $ip (ports 80, 443, 22)"
        done
    done

    log_success "Network whitelist configured"
    echo ""
}

# Main execution
if [ "$(id -u)" = "0" ]; then
    # Running as root - set up firewall, then drop to coder user
    setup_firewall

    # Configure git safe.directory in system gitconfig (writable, unlike mounted ~/.gitconfig)
    # This is needed because the workspace is mounted from host with different ownership
    git config --system --add safe.directory /workspace 2>/dev/null || true

    # Switch to coder user and run the command using gosu
    # gosu properly handles TTY and signals, unlike su
    cd /workspace
    if [ $# -eq 0 ]; then
        exec gosu coder bash
    else
        exec gosu coder "$@"
    fi
else
    # Not running as root - just execute the command
    # (firewall won't be set up, but container isolation still applies)
    log_warn "Not running as root - network firewall not configured"
    exec "$@"
fi
