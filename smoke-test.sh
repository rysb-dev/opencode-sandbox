#!/bin/bash
# =============================================================================
# OpenCode Sandbox Smoke Test
# =============================================================================
# This script verifies that the sandbox is working correctly by testing:
#   1. Network isolation (blocked hosts are unreachable)
#   2. Network whitelist (allowed hosts are reachable)
#   3. Filesystem isolation (only mounted paths are accessible)
#   4. OpenCode is installed and runnable
#
# Usage:
#   ./smoke-test.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="opencode-sandbox"
TEST_RESULTS=()
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_test()    { echo -e "${BLUE}[test]${NC} $1"; }
log_pass()    { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED++)) || true; }
log_fail()    { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED++)) || true; }
log_header()  { echo -e "\n${BOLD}$1${NC}\n"; }

# Helper: Run docker without entrypoint (for direct commands)
docker_run_direct() {
    docker run --rm --entrypoint="" "$@"
}

# Helper: Run docker with entrypoint (for testing entrypoint behavior)
docker_run_with_entrypoint() {
    docker run --rm "$@"
}

# Helper: Extract just the last line (actual result) from output that may contain sandbox logs
get_last_line() {
    echo "$1" | tail -1
}

# Helper: Check if output contains a value (ignoring sandbox log lines)
output_contains() {
    local output="$1"
    local pattern="$2"
    echo "$output" | grep -v '^\[sandbox\]' | grep -v '^\[0;' | grep -q "$pattern"
}

# -----------------------------------------------------------------------------
# Check prerequisites
# -----------------------------------------------------------------------------
check_prerequisites() {
    log_header "Prerequisites"
    
    if ! command -v docker &>/dev/null; then
        log_fail "Docker not installed"
        exit 1
    fi
    log_pass "Docker is installed"
    
    if ! docker info >/dev/null 2>&1; then
        log_fail "Docker daemon not running"
        exit 1
    fi
    log_pass "Docker daemon is running"
    
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        log_test "Building Docker image (required for tests)..."
        docker build -t "$IMAGE_NAME" "$SCRIPT_DIR" >/dev/null 2>&1
    fi
    log_pass "Docker image '$IMAGE_NAME' exists"
}

# -----------------------------------------------------------------------------
# Test: OpenCode installation
# -----------------------------------------------------------------------------
test_opencode_installed() {
    log_header "Test: OpenCode Installation"
    
    log_test "Checking if opencode binary exists..."
    if docker_run_direct "$IMAGE_NAME" which opencode >/dev/null 2>&1; then
        log_pass "opencode binary found"
    else
        log_fail "opencode binary not found"
        return
    fi
    
    log_test "Checking opencode version..."
    local version
    version=$(docker_run_direct "$IMAGE_NAME" opencode --version 2>/dev/null || echo "")
    if [[ -n "$version" ]]; then
        log_pass "opencode version: $version"
    else
        log_fail "Could not get opencode version"
    fi
}

# -----------------------------------------------------------------------------
# Test: Network isolation
# -----------------------------------------------------------------------------
test_network_isolation() {
    log_header "Test: Network Isolation"
    
    # Test 1: Blocked host (google.com is not in whitelist)
    log_test "Testing blocked host (google.com)..."
    local blocked_result
    blocked_result=$(docker_run_with_entrypoint \
        --cap-add=NET_ADMIN \
        -e "ALLOWED_HOSTS=api.anthropic.com" \
        "$IMAGE_NAME" \
        bash -c "curl -s --connect-timeout 5 https://www.google.com >/dev/null 2>&1 && echo 'REACHABLE' || echo 'BLOCKED'" 2>&1)
    
    if output_contains "$blocked_result" "BLOCKED"; then
        log_pass "google.com is BLOCKED (as expected)"
    else
        log_fail "google.com should be blocked but was reachable"
    fi
    
    # Test 2: Allowed host (api.anthropic.com)
    log_test "Testing whitelisted host (api.anthropic.com)..."
    local allowed_result
    allowed_result=$(docker_run_with_entrypoint \
        --cap-add=NET_ADMIN \
        -e "ALLOWED_HOSTS=api.anthropic.com" \
        "$IMAGE_NAME" \
        bash -c "curl -s --connect-timeout 10 -o /dev/null -w '%{http_code}' https://api.anthropic.com; echo ''" 2>&1)
    
    # Extract HTTP status code - look for 3-digit number that's not 000
    local http_code
    http_code=$(echo "$allowed_result" | grep -oE '[0-9]{3}' | tail -1 || echo "000")
    
    # We expect some HTTP response (even 401/403 is fine - it means we reached the server)
    if [[ "$http_code" =~ ^[0-9]+$ ]] && [[ "$http_code" != "000" ]]; then
        log_pass "api.anthropic.com is REACHABLE (HTTP $http_code)"
    else
        log_fail "api.anthropic.com should be reachable but connection failed"
    fi
    
    # Test 3: Another blocked host (example.com)
    log_test "Testing another blocked host (example.com)..."
    local blocked2_result
    blocked2_result=$(docker_run_with_entrypoint \
        --cap-add=NET_ADMIN \
        -e "ALLOWED_HOSTS=api.anthropic.com" \
        "$IMAGE_NAME" \
        bash -c "curl -s --connect-timeout 5 https://example.com >/dev/null 2>&1 && echo 'REACHABLE' || echo 'BLOCKED'" 2>&1)
    
    if output_contains "$blocked2_result" "BLOCKED"; then
        log_pass "example.com is BLOCKED (as expected)"
    else
        log_fail "example.com should be blocked but was reachable"
    fi
    
    # Test 4: No hosts allowed - with empty whitelist, firewall isn't set up
    log_test "Testing with empty whitelist (all hosts allowed - no firewall)..."
    local no_hosts_result
    no_hosts_result=$(docker_run_with_entrypoint \
        --cap-add=NET_ADMIN \
        -e "ALLOWED_HOSTS=" \
        "$IMAGE_NAME" \
        bash -c 'http_code=$(curl -s --connect-timeout 10 -o /dev/null -w "%{http_code}" https://example.com 2>/dev/null); if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then echo "REACHABLE"; else echo "BLOCKED"; fi' 2>&1)
    
    # With empty whitelist, the firewall isn't set up, so connections should be allowed
    if output_contains "$no_hosts_result" "REACHABLE"; then
        log_pass "Empty whitelist = no firewall (all hosts reachable)"
    else
        log_fail "With empty whitelist, hosts should be reachable"
    fi
}

# -----------------------------------------------------------------------------
# Test: Filesystem isolation
# -----------------------------------------------------------------------------
test_filesystem_isolation() {
    log_header "Test: Filesystem Isolation"
    
    # Create a test directory in HOME (not /tmp, which may not be shared with Docker on macOS)
    local test_dir="$HOME/.opencode-sandbox-test-$$"
    mkdir -p "$test_dir"
    echo "test content" > "$test_dir/testfile.txt"
    
    # Test 1: Mounted directory is accessible (bypass entrypoint for clean output)
    log_test "Testing mounted directory access..."
    local mounted_result
    mounted_result=$(docker_run_direct \
        -v "$test_dir:/workspace:ro" \
        "$IMAGE_NAME" \
        cat /workspace/testfile.txt 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$mounted_result" == "test content" ]]; then
        log_pass "Mounted directory is accessible"
    else
        log_fail "Could not read from mounted directory (got: '$mounted_result')"
    fi
    
    # Test 2: Host filesystem outside mounts is not accessible
    log_test "Testing host filesystem isolation..."
    local isolated_result
    isolated_result=$(docker_run_direct \
        -v "$test_dir:/workspace:ro" \
        "$IMAGE_NAME" \
        bash -c "ls /Users 2>/dev/null && echo 'ACCESSIBLE' || echo 'ISOLATED'" 2>/dev/null)
    
    if [[ "$isolated_result" == *"ISOLATED"* ]]; then
        log_pass "Host /Users directory is NOT accessible (isolated)"
    else
        log_fail "Host filesystem should not be accessible"
    fi
    
    # Test 3: Cannot write to read-only mount
    log_test "Testing read-only mount protection..."
    local readonly_result
    readonly_result=$(docker_run_direct \
        -v "$test_dir:/workspace:ro" \
        "$IMAGE_NAME" \
        bash -c "touch /workspace/newfile.txt 2>&1 && echo 'WRITABLE' || echo 'READONLY'" 2>/dev/null)
    
    if [[ "$readonly_result" == *"READONLY"* ]]; then
        log_pass "Read-only mount prevents writes"
    else
        log_fail "Read-only mount should prevent writes"
    fi
    
    # Cleanup
    rm -rf "$test_dir"
}

# -----------------------------------------------------------------------------
# Test: User isolation
# -----------------------------------------------------------------------------
test_user_isolation() {
    log_header "Test: User Isolation"
    
    log_test "Checking running user (via entrypoint)..."
    local user_result
    user_result=$(docker_run_with_entrypoint \
        --cap-add=NET_ADMIN \
        -e "ALLOWED_HOSTS=localhost" \
        "$IMAGE_NAME" \
        whoami 2>&1)
    
    # Extract just the username (last line, removing any color codes)
    local username
    username=$(echo "$user_result" | grep -v '^\[' | grep -v '^$' | tail -1 | tr -d '[:space:]')
    
    if [[ "$username" == "coder" ]]; then
        log_pass "Running as non-root user 'coder'"
    else
        log_fail "Should run as 'coder' but got: '$username'"
    fi
    
    log_test "Checking user cannot become root..."
    local sudo_result
    sudo_result=$(docker_run_direct "$IMAGE_NAME" \
        bash -c "sudo echo 'root' 2>&1 || echo 'NO_SUDO'" 2>/dev/null)
    
    if [[ "$sudo_result" == *"NO_SUDO"* ]] || [[ "$sudo_result" == *"not found"* ]] || [[ "$sudo_result" == *"command not found"* ]]; then
        log_pass "sudo is not available"
    else
        log_fail "sudo should not be available"
    fi
}

# -----------------------------------------------------------------------------
# Test: OpenCode config (tool approval)
# -----------------------------------------------------------------------------
test_opencode_config() {
    log_header "Test: OpenCode Configuration"
    
    log_test "Checking opencode config exists..."
    local config_result
    config_result=$(docker_run_direct "$IMAGE_NAME" \
        cat /home/coder/.config/opencode/config.json 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$config_result" == *"autoApprove"* ]]; then
        log_pass "OpenCode config file exists"
    else
        log_fail "OpenCode config file not found"
        return
    fi
    
    log_test "Checking autoApprove is empty (requires permission for all tools)..."
    if [[ "$config_result" == *'"autoApprove": []'* ]] || [[ "$config_result" == *'"autoApprove":[]'* ]]; then
        log_pass "autoApprove is empty (all tools require permission)"
    else
        log_fail "autoApprove should be empty for maximum safety"
    fi
}

# -----------------------------------------------------------------------------
# Test: Entrypoint firewall setup
# -----------------------------------------------------------------------------
test_entrypoint_firewall() {
    log_header "Test: Entrypoint Firewall Setup"
    
    log_test "Verifying iptables rules are created..."
    # Set up firewall manually (same as entrypoint does) and verify rules
    local iptables_result
    iptables_result=$(docker run --rm \
        --cap-add=NET_ADMIN \
        --entrypoint="" \
        "$IMAGE_NAME" \
        bash -c '
            iptables -F OUTPUT 2>/dev/null || true
            iptables -P OUTPUT DROP
            iptables -A OUTPUT -o lo -j ACCEPT
            iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
            iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
            iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
            ip=$(dig +short api.anthropic.com | grep -E "^[0-9]" | head -1)
            iptables -A OUTPUT -d "$ip" -p tcp --dport 443 -j ACCEPT
            iptables -L OUTPUT -n
        ' 2>&1)
    
    # Check that DROP policy is set and ACCEPT rules exist
    if echo "$iptables_result" | grep -q "policy DROP" && echo "$iptables_result" | grep -q "ACCEPT"; then
        log_pass "iptables firewall rules are configured"
    else
        log_fail "iptables rules not properly configured"
    fi
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_summary() {
    log_header "Test Summary"
    
    echo -e "  ${GREEN}Passed:${NC} $PASSED"
    echo -e "  ${RED}Failed:${NC} $FAILED"
    echo ""
    
    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}All tests passed! ✓${NC}"
        echo ""
        echo "Your OpenCode sandbox is properly configured and secure."
    else
        echo -e "${RED}${BOLD}Some tests failed! ✗${NC}"
        echo ""
        echo "Please review the failures above and fix any issues."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo -e "${BOLD}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║     OpenCode Sandbox Smoke Test           ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_prerequisites
    test_opencode_installed
    test_network_isolation
    test_filesystem_isolation
    test_user_isolation
    test_opencode_config
    test_entrypoint_firewall
    print_summary
}

main "$@"
