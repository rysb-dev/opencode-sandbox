#!/bin/bash
# =============================================================================
# OpenCode Sandbox Setup Script
# =============================================================================
# This script installs the opencode-sandbox tool on your system.
#
# What it does:
#   1. Copies configuration files to ~/.config/opencode-sandbox/
#   2. Creates a symlink to the launcher script in ~/.local/bin/
#   3. Builds the Docker image
#
# Requirements:
#   - Docker (Docker Desktop on macOS/Windows, or docker-ce on Linux)
#   - Bash 4.0+
#
# Usage:
#   ./setup.sh          # Install
#   ./setup.sh --remove # Uninstall
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode-sandbox"
BIN_DIR="$HOME/.local/bin"
IMAGE_NAME="opencode-sandbox"

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
log_header()  { echo -e "\n${BOLD}$1${NC}"; }

# -----------------------------------------------------------------------------
# Check prerequisites
# -----------------------------------------------------------------------------
check_prerequisites() {
    log_header "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &>/dev/null; then
        log_error "Docker not found!"
        echo ""
        echo "Please install Docker:"
        echo "  macOS:   https://docs.docker.com/desktop/install/mac-install/"
        echo "  Linux:   https://docs.docker.com/engine/install/"
        echo "  Windows: https://docs.docker.com/desktop/install/windows-install/"
        exit 1
    fi
    log_success "Docker found: $(docker --version)"
    
    # Check Docker daemon
    if ! docker info &>/dev/null 2>&1; then
        log_error "Docker daemon is not running!"
        echo ""
        echo "Please start Docker Desktop and try again."
        exit 1
    fi
    log_success "Docker daemon is running"
    
    # Check Bash version
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        log_warn "Bash version ${BASH_VERSION} detected. Version 4.0+ recommended."
    else
        log_success "Bash version: ${BASH_VERSION}"
    fi
}

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------
install() {
    log_header "Installing OpenCode Sandbox..."
    
    # Create directories
    log_info "Creating directories..."
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BIN_DIR"
    
    # Copy Docker files to config directory
    log_info "Copying Docker files..."
    cp "$SCRIPT_DIR/Dockerfile" "$CONFIG_DIR/"
    cp "$SCRIPT_DIR/entrypoint.sh" "$CONFIG_DIR/"
    cp "$SCRIPT_DIR/opencode.json" "$CONFIG_DIR/"
    
    # Copy example config if no config exists
    if [[ ! -f "$CONFIG_DIR/config" ]]; then
        log_info "Creating default configuration..."
        cp "$SCRIPT_DIR/config.example" "$CONFIG_DIR/config"
    else
        log_info "Keeping existing configuration"
    fi
    
    # Create symlink to launcher
    log_info "Installing launcher script..."
    cp "$SCRIPT_DIR/opencode-sandbox" "$BIN_DIR/opencode-sandbox"
    chmod +x "$BIN_DIR/opencode-sandbox"
    
    # Check if BIN_DIR is in PATH
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        log_warn "$BIN_DIR is not in your PATH"
        echo ""
        echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo ""
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    fi
    
    # Build Docker image
    log_header "Building Docker image..."
    log_info "This may take a minute on first run..."
    docker build -t "$IMAGE_NAME" "$CONFIG_DIR"
    
    # Show installed version
    local version=$(docker run --rm "$IMAGE_NAME" opencode --version 2>/dev/null || echo "unknown")
    
    log_header "Installation Complete!"
    echo ""
    echo -e "  ${GREEN}✓${NC} OpenCode version: $version"
    echo -e "  ${GREEN}✓${NC} Configuration: $CONFIG_DIR/config"
    echo -e "  ${GREEN}✓${NC} Command: opencode-sandbox"
    echo ""
    echo -e "${BOLD}Quick Start:${NC}"
    echo "  cd /path/to/your/project"
    echo "  opencode-sandbox"
    echo ""
    echo -e "${BOLD}Edit Configuration:${NC}"
    echo "  opencode-sandbox --config"
    echo ""
    echo -e "${BOLD}Update OpenCode:${NC}"
    echo "  opencode-sandbox --update"
    echo ""
}

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------
uninstall() {
    log_header "Uninstalling OpenCode Sandbox..."
    
    # Remove launcher
    if [[ -f "$BIN_DIR/opencode-sandbox" ]]; then
        log_info "Removing launcher script..."
        rm "$BIN_DIR/opencode-sandbox"
    fi
    
    # Remove Docker image
    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        log_info "Removing Docker image..."
        docker rmi "$IMAGE_NAME"
    fi
    
    # Ask about config
    if [[ -d "$CONFIG_DIR" ]]; then
        echo ""
        read -p "Remove configuration directory $CONFIG_DIR? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing configuration..."
            rm -rf "$CONFIG_DIR"
        else
            log_info "Keeping configuration directory"
        fi
    fi
    
    log_success "Uninstallation complete!"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo -e "${BOLD}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║       OpenCode Sandbox Setup              ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    
    case "${1:-}" in
        --remove|--uninstall|-r)
            check_prerequisites
            uninstall
            ;;
        --help|-h)
            echo "Usage: $0 [--remove]"
            echo ""
            echo "Options:"
            echo "  --remove    Uninstall opencode-sandbox"
            echo "  --help      Show this help message"
            ;;
        *)
            check_prerequisites
            install
            ;;
    esac
}

main "$@"
