#!/bin/bash
# =============================================================================
# OpenCode Sandbox Setup
# =============================================================================
# Installs opencode-sandbox to ~/.local/bin and sets up configuration.
#
# Usage: ./setup.sh [--remove]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode-sandbox"
SCRIPT_NAME="opencode-sandbox"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[setup]${NC} $1"; }
log_success() { echo -e "${GREEN}[setup]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[setup]${NC} $1"; }
log_error()   { echo -e "${RED}[setup]${NC} $1" >&2; }

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------
install() {
    echo -e "${BOLD}OpenCode Sandbox Setup${NC}"
    echo ""

    # Check Docker
    if ! command -v docker &>/dev/null; then
        log_error "Docker not found. Please install Docker Desktop first."
        exit 1
    fi

    # Create install directory
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_info "Creating $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi

    # Copy the script (preserving the source directory reference)
    log_info "Installing $SCRIPT_NAME to $INSTALL_DIR"

    # Create a wrapper script that calls the original
    cat > "$INSTALL_DIR/$SCRIPT_NAME" << EOF
#!/bin/bash
# Wrapper script - calls the actual opencode-sandbox from the repo
exec "$SCRIPT_DIR/$SCRIPT_NAME" "\$@"
EOF
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

    # Check if install dir is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo ""
        log_warn "$INSTALL_DIR is not in your PATH"
        echo ""
        echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo ""
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    fi

    # Build Docker images
    echo ""
    log_info "Building Docker images (this may take a minute)..."

    # Create a temporary compose file just for building
    local temp_compose
    temp_compose=$(mktemp)
    cat > "$temp_compose" << EOF
services:
  proxy:
    build:
      context: ${SCRIPT_DIR}/proxy
    image: opencode-sandbox-proxy
  agent:
    build:
      context: ${SCRIPT_DIR}/agent
    image: opencode-sandbox-agent
EOF

    docker compose -f "$temp_compose" build --quiet
    rm -f "$temp_compose"

    log_success "Docker images built"

    # Show success message
    echo ""
    echo "=============================================="
    log_success "Installation complete!"
    echo "=============================================="
    echo ""
    echo "Usage:"
    echo "  opencode-sandbox                    # Run in current directory"
    echo "  opencode-sandbox ~/Projects/myapp   # Run in specific directory"
    echo "  opencode-sandbox --help             # Show all options"
    echo ""
    echo "Configuration:"
    echo "  opencode-sandbox --config           # Edit network whitelist"
    echo ""
}

# -----------------------------------------------------------------------------
# Remove
# -----------------------------------------------------------------------------
remove() {
    echo -e "${BOLD}OpenCode Sandbox Removal${NC}"
    echo ""

    # Remove installed script
    if [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        log_info "Removing $INSTALL_DIR/$SCRIPT_NAME"
        rm -f "$INSTALL_DIR/$SCRIPT_NAME"
    fi

    # Remove Docker images
    log_info "Removing Docker images..."
    docker rmi opencode-sandbox-proxy opencode-sandbox-agent 2>/dev/null || true

    # Ask about config
    if [[ -d "$CONFIG_DIR" ]]; then
        echo ""
        read -p "Remove configuration directory $CONFIG_DIR? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing $CONFIG_DIR"
            rm -rf "$CONFIG_DIR"
        fi
    fi

    echo ""
    log_success "Removal complete"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    case "${1:-}" in
        --remove|-r)
            remove
            ;;
        --help|-h)
            echo "Usage: ./setup.sh [--remove]"
            echo ""
            echo "Options:"
            echo "  --remove, -r    Remove opencode-sandbox"
            echo "  --help, -h      Show this help"
            ;;
        *)
            install
            ;;
    esac
}

main "$@"
