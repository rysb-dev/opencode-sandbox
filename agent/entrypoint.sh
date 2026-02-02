#!/bin/bash
# =============================================================================
# OpenCode Agent Container Entrypoint
# =============================================================================
# Simple entrypoint that configures git credentials and runs opencode.
# No iptables/firewall setup needed - network isolation is handled by Docker.
# =============================================================================

set -e

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[agent]${NC} $1"; }
log_success() { echo -e "${GREEN}[agent]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[agent]${NC} $1"; }

# -----------------------------------------------------------------------------
# Configure Git for HTTPS authentication
# -----------------------------------------------------------------------------
setup_git() {
    # Set safe directory for mounted workspace (different ownership)
    git config --global --add safe.directory /workspace 2>/dev/null || true

    # Configure git credential helper if GIT_TOKEN is provided
    if [ -n "$GIT_TOKEN" ]; then
        log_info "Configuring git credentials..."

        # Set credential helper to use environment variable
        git config --global credential.helper 'store'

        # Default to github.com if not specified
        GIT_HOST="${GIT_HOST:-github.com}"
        GIT_USER="${GIT_USER:-git}"

        # Store credentials for the git host
        mkdir -p ~/.git-credentials 2>/dev/null || true
        echo "https://${GIT_USER}:${GIT_TOKEN}@${GIT_HOST}" > ~/.git-credentials
        chmod 600 ~/.git-credentials
        git config --global credential.helper 'store --file ~/.git-credentials'

        log_success "Git credentials configured for ${GIT_HOST}"
    else
        log_warn "GIT_TOKEN not set - git push/pull may require manual auth"
    fi

    # Basic git config if not already set
    if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
        git config --global user.email "opencode@sandbox.local"
        git config --global user.name "OpenCode Sandbox"
    fi
}

# -----------------------------------------------------------------------------
# Show proxy configuration status
# -----------------------------------------------------------------------------
show_status() {
    echo ""
    log_info "=== OpenCode Sandbox ==="
    log_info "Proxy: ${HTTPS_PROXY:-not configured}"
    log_info "Workspace: /workspace"

    if [ -n "$ANTHROPIC_API_KEY" ]; then
        log_success "ANTHROPIC_API_KEY: configured"
    else
        log_warn "ANTHROPIC_API_KEY: not set"
    fi

    if [ -n "$OPENAI_API_KEY" ]; then
        log_success "OPENAI_API_KEY: configured"
    else
        log_warn "OPENAI_API_KEY: not set"
    fi

    if [ -n "$GIT_TOKEN" ]; then
        log_success "GIT_TOKEN: configured"
    fi

    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    setup_git
    show_status

    # Execute the command (default: opencode)
    exec "$@"
}

main "$@"
