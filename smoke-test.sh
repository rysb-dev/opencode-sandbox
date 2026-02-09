#!/bin/bash
# =============================================================================
# OpenCode Sandbox Smoke Test
# =============================================================================
# This script tests the sandbox environment to verify:
# 1. Containers are running and healthy
# 2. Proxy is blocking disallowed domains
# 3. Proxy is allowing allowed domains
# 4. Agent has correct environment configuration
# 5. Network isolation is working (agent can't bypass proxy)
#
# Usage: ./smoke-test.sh
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}!${NC}"
INFO="${BLUE}ℹ${NC}"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Container names (overridden with --acp flag)
PROXY_CONTAINER="opencode-sandbox-proxy"
AGENT_CONTAINER="opencode-sandbox-agent"
MODE="tui"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log_test() {
    echo -e "\n${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "  ${PASS} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "  ${FAIL} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_skip() {
    echo -e "  ${WARN} SKIP: $1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

log_info() {
    echo -e "  ${INFO} $1"
}

# Run command in agent container
agent_exec() {
    docker exec "$AGENT_CONTAINER" "$@" 2>/dev/null
}

# Check if containers are running
check_containers_running() {
    log_test "Checking containers are running..."

    # Check proxy
    if docker ps -q -f "name=${PROXY_CONTAINER}" -f "status=running" | grep -q .; then
        log_pass "Proxy container is running"
    else
        log_fail "Proxy container is not running"
        return 1
    fi

    # Check agent
    if docker ps -q -f "name=${AGENT_CONTAINER}" -f "status=running" | grep -q .; then
        log_pass "Agent container is running"
    else
        log_fail "Agent container is not running"
        return 1
    fi
}

# Check proxy health
check_proxy_health() {
    log_test "Checking proxy health..."

    if docker ps -f "name=${PROXY_CONTAINER}" | grep -q "healthy"; then
        log_pass "Proxy is healthy"
    else
        log_fail "Proxy is not healthy"
        return 1
    fi
}

# Check environment variables in agent
check_agent_environment() {
    log_test "Checking agent environment configuration..."

    # Check HTTP_PROXY is set
    if agent_exec printenv HTTP_PROXY | grep -q "proxy:3128"; then
        log_pass "HTTP_PROXY is configured correctly"
    else
        log_fail "HTTP_PROXY is not configured"
    fi

    # Check HTTPS_PROXY is set
    if agent_exec printenv HTTPS_PROXY | grep -q "proxy:3128"; then
        log_pass "HTTPS_PROXY is configured correctly"
    else
        log_fail "HTTPS_PROXY is not configured"
    fi
}

# Check tools are installed
check_agent_tools() {
    log_test "Checking agent has required tools..."

    # Check opencode
    if agent_exec which opencode >/dev/null 2>&1; then
        local version
        version=$(agent_exec opencode --version 2>/dev/null || echo "unknown")
        log_pass "opencode is installed (${version})"
    else
        log_fail "opencode is not installed"
    fi

    # Check Node.js
    if agent_exec which node >/dev/null 2>&1; then
        local version
        version=$(agent_exec node --version 2>/dev/null)
        log_pass "Node.js is installed (${version})"
    else
        log_fail "Node.js is not installed"
    fi

    # Check Go
    if agent_exec which go >/dev/null 2>&1; then
        local version
        version=$(agent_exec go version 2>/dev/null | awk '{print $3}')
        log_pass "Go is installed (${version})"
    else
        log_fail "Go is not installed"
    fi

    # Check Python
    if agent_exec which python >/dev/null 2>&1; then
        local version
        version=$(agent_exec python --version 2>/dev/null)
        log_pass "Python is installed (${version})"
    else
        log_fail "Python is not installed"
    fi

    # Check git
    if agent_exec which git >/dev/null 2>&1; then
        log_pass "git is installed"
    else
        log_fail "git is not installed"
    fi

    # Check ripgrep
    if agent_exec which rg >/dev/null 2>&1; then
        log_pass "ripgrep is installed"
    else
        log_fail "ripgrep is not installed"
    fi
}

# Test allowed domain access through proxy
check_allowed_domains() {
    log_test "Checking access to allowed domains..."

    # Test Anthropic API (should get through, even if we get an auth error)
    log_info "Testing api.anthropic.com..."
    local anthropic_response
    anthropic_response=$(agent_exec curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 https://api.anthropic.com/v1/messages 2>/dev/null)

    # Check if response is a valid HTTP code (3 digits, not 000)
    if [ -n "$anthropic_response" ] && [ "$anthropic_response" != "000" ] && echo "$anthropic_response" | grep -qE '^[1-5][0-9]{2}$'; then
        log_pass "api.anthropic.com is accessible (HTTP ${anthropic_response})"
    else
        log_fail "api.anthropic.com is not accessible (response: ${anthropic_response:-empty})"
    fi

    # Test GitHub API
    log_info "Testing api.github.com..."
    local github_response
    github_response=$(agent_exec curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 https://api.github.com 2>/dev/null)

    if [ -n "$github_response" ] && [ "$github_response" != "000" ] && echo "$github_response" | grep -qE '^[1-5][0-9]{2}$'; then
        log_pass "api.github.com is accessible (HTTP ${github_response})"
    else
        log_fail "api.github.com is not accessible (response: ${github_response:-empty})"
    fi
}

# Test blocked domain access through proxy
check_blocked_domains() {
    log_test "Checking blocked domains are denied..."

    # Test a domain that should NOT be in the allowlist
    log_info "Testing example.com (should be blocked)..."
    local example_response
    example_response=$(agent_exec curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 https://example.com 2>/dev/null)

    # Blocked domains should return 000 (connection failed) or be empty
    if [ -z "$example_response" ] || [ "$example_response" = "000" ]; then
        log_pass "example.com is blocked (connection failed as expected)"
    else
        log_fail "example.com is NOT blocked (HTTP ${example_response}) - check your allowlist!"
    fi

    # Test another blocked domain
    log_info "Testing httpbin.org (should be blocked)..."
    local httpbin_response
    httpbin_response=$(agent_exec curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 https://httpbin.org/get 2>/dev/null)

    if [ -z "$httpbin_response" ] || [ "$httpbin_response" = "000" ]; then
        log_pass "httpbin.org is blocked (connection failed as expected)"
    else
        log_fail "httpbin.org is NOT blocked (HTTP ${httpbin_response}) - check your allowlist!"
    fi
}

# Test that agent cannot bypass proxy
check_network_isolation() {
    log_test "Checking network isolation (agent cannot bypass proxy)..."

    # Try to reach an allowed domain WITHOUT using the proxy
    log_info "Attempting direct connection (bypassing proxy)..."
    local direct_response
    direct_response=$(agent_exec curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 --noproxy '*' https://api.github.com 2>/dev/null)

    # Direct access should fail (000 or empty) because agent is on internal network
    if [ -z "$direct_response" ] || [ "$direct_response" = "000" ]; then
        log_pass "Direct internet access is blocked (agent isolated correctly)"
    else
        log_fail "Agent can bypass proxy! (HTTP ${direct_response}) - Network isolation is compromised!"
    fi
}

# Test workspace mount
check_workspace() {
    log_test "Checking workspace mount..."

    if agent_exec test -d /workspace; then
        log_pass "/workspace directory exists"

        # Check if it's writable
        if agent_exec touch /workspace/.smoke-test-tmp 2>/dev/null && agent_exec rm /workspace/.smoke-test-tmp 2>/dev/null; then
            log_pass "/workspace is writable"
        else
            log_fail "/workspace is not writable"
        fi
    else
        log_fail "/workspace directory does not exist"
    fi
}

# Check user is non-root
check_non_root() {
    log_test "Checking agent runs as non-root..."

    local current_user
    current_user=$(agent_exec whoami)

    if [ "$current_user" = "coder" ]; then
        log_pass "Agent runs as 'coder' user (non-root)"
    elif [ "$current_user" = "root" ]; then
        log_fail "Agent runs as root (security risk!)"
    else
        log_pass "Agent runs as '${current_user}' (non-root)"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "============================================================================="
    echo "                           SMOKE TEST SUMMARY"
    echo "============================================================================="
    echo ""
    echo -e "  ${GREEN}Passed:${NC}  ${TESTS_PASSED}"
    echo -e "  ${RED}Failed:${NC}  ${TESTS_FAILED}"
    echo -e "  ${YELLOW}Skipped:${NC} ${TESTS_SKIPPED}"
    echo ""

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "  ${GREEN}All tests passed!${NC} ✨"
        echo ""
        return 0
    else
        echo -e "  ${RED}Some tests failed.${NC} Review the output above for details."
        echo ""
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

# ACP-specific: check host path symlink exists
check_acp_path_symlink() {
    log_test "Checking ACP host path symlink..."

    # Look for any symlink pointing to /workspace outside of /proc (the host path mapping)
    local symlinks
    symlinks=$(agent_exec find / -maxdepth 6 -path /proc -prune -o -type l -lname /workspace -print 2>/dev/null | head -5)

    if [ -n "$symlinks" ]; then
        log_pass "Host path symlink found: ${symlinks}"
    else
        log_skip "No host path symlink found (may not be needed if project dir is /workspace)"
    fi
}

# ACP-specific: check JSON-RPC responsiveness
check_acp_jsonrpc() {
    log_test "Checking ACP JSON-RPC responsiveness..."

    # Send an initialize request directly to opencode acp inside the container
    local response
    response=$(echo '{"jsonrpc":"2.0","id":99,"method":"initialize","params":{"protocolVersion":1,"capabilities":{}}}' \
        | timeout 15 docker exec -i "$AGENT_CONTAINER" opencode acp --cwd /workspace 2>/dev/null \
        | head -1)

    if echo "$response" | grep -q '"protocolVersion"'; then
        log_pass "OpenCode ACP responds to JSON-RPC initialize"
    else
        log_fail "OpenCode ACP did not respond to JSON-RPC initialize (response: ${response:-empty})"
    fi
}

main() {
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --acp)
                MODE="acp"
                PROXY_CONTAINER="opencode-sandbox-acp-proxy"
                AGENT_CONTAINER="opencode-sandbox-acp-agent"
                ;;
            -h|--help)
                echo "Usage: ./smoke-test.sh [--acp]"
                echo ""
                echo "Options:"
                echo "  --acp    Test ACP mode containers instead of TUI mode"
                exit 0
                ;;
        esac
    done

    echo "============================================================================="
    echo "                    OpenCode Sandbox Smoke Test"
    if [ "$MODE" = "acp" ]; then
        echo "                           (ACP Mode)"
    fi
    echo "============================================================================="
    echo ""
    echo "This script tests that the sandbox is configured correctly."
    if [ "$MODE" = "acp" ]; then
        echo "Make sure the ACP sandbox is running (e.g., via Zed or opencode-sandbox acp)"
    else
        echo "Make sure the sandbox is running first: opencode-sandbox /path/to/project"
    fi
    echo ""

    # Check docker is available
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: docker is not installed${NC}"
        exit 1
    fi

    # Check if containers are running
    if ! docker ps -q -f "name=${AGENT_CONTAINER}" -f "status=running" | grep -q .; then
        echo -e "${RED}Error: Sandbox is not running.${NC}"
        echo ""
        if [ "$MODE" = "acp" ]; then
            echo "Start the ACP sandbox first (e.g., via Zed or):"
            echo "  opencode-sandbox acp /path/to/project"
        else
            echo "Start the sandbox first:"
            echo "  opencode-sandbox /path/to/project"
        fi
        echo ""
        echo "Then run this smoke test from another terminal."
        exit 1
    fi

    # Run common tests
    check_containers_running
    check_proxy_health
    check_agent_environment
    check_agent_tools
    check_non_root
    check_workspace
    check_allowed_domains
    check_blocked_domains
    check_network_isolation

    # Run ACP-specific tests
    if [ "$MODE" = "acp" ]; then
        check_acp_path_symlink
        check_acp_jsonrpc
    fi

    # Print summary
    print_summary
}

main "$@"
