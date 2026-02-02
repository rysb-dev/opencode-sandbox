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
# Import host opencode configuration if available
# -----------------------------------------------------------------------------
import_host_config() {
    local host_config="/host-config/opencode"
    local host_cache="/host-config/opencode-cache"
    local config_dir="/home/coder/.config/opencode"
    local cache_dir="/home/coder/.cache/opencode"

    # Check if host config directory was mounted and has content
    if [ -d "$host_config" ] && [ "$(ls -A $host_config 2>/dev/null)" ]; then
        log_info "Found host opencode config, importing..."
        mkdir -p "$config_dir"
        # Copy host config files (but don't overwrite existing)
        cp -rn "$host_config"/* "$config_dir"/ 2>/dev/null || true
        log_success "Imported host opencode configuration"
    fi

    # Check if host cache directory was mounted and has content
    if [ -d "$host_cache" ] && [ "$(ls -A $host_cache 2>/dev/null)" ]; then
        log_info "Found host opencode cache, importing..."
        mkdir -p "$cache_dir"
        # Copy host cache files (but don't overwrite existing)
        cp -rn "$host_cache"/* "$cache_dir"/ 2>/dev/null || true
        log_success "Imported host opencode cache"
    fi
}

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
    import_host_config
    setup_git
    show_status

    # Execute the command (default: opencode)
    exec "$@"
}

main "$@"
