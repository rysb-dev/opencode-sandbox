# OpenCode Sandbox

Run [OpenCode](https://opencode.ai) in a secure, isolated Docker container with:

- **Network whitelisting** - Only connect to approved domains (e.g., API endpoints)
- **Filesystem isolation** - Only access your project directory and explicitly mounted paths
- **Tool approval** - All tool calls require explicit permission (no auto-approve)
- **Non-root execution** - OpenCode runs as an unprivileged user

## Why Use This?

OpenCode is a powerful AI coding assistant that can read/write files and execute commands. While this is incredibly useful, you may want additional security controls:

- **Prevent data exfiltration** - Block network access except to your LLM API provider
- **Limit file access** - Restrict access to only your current project
- **Audit trail** - See every action before it executes (no auto-approved tools)

This sandbox provides defense-in-depth for running AI coding assistants safely.

## Quick Start

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (macOS/Windows) or Docker Engine (Linux)
- Bash 4.0+ (included on most systems)

### Installation

```bash
# Clone this repository
git clone https://github.com/yourusername/opencode-sandbox.git
cd opencode-sandbox

# Run the setup script
./setup.sh
```

The setup script will:
1. Copy configuration files to `~/.config/opencode-sandbox/`
2. Install the `opencode-sandbox` command to `~/.local/bin/`
3. Build the Docker image

### Basic Usage

```bash
# Run in current directory
cd /path/to/your/project
opencode-sandbox

# Run in a specific directory
opencode-sandbox ~/Projects/my-app

# Show help
opencode-sandbox --help
```

## Configuration

Edit your configuration file:

```bash
opencode-sandbox --config
# Or directly edit: ~/.config/opencode-sandbox/config
```

### Network Whitelist

Specify which domains OpenCode can connect to:

```ini
[network]
# LLM API endpoints
api.anthropic.com
api.openai.com

# GitHub (for Copilot, API access, etc.)
api.githubcopilot.com
copilot-proxy.githubusercontent.com
github.com
api.github.com

# Documentation/research
en.wikipedia.org
docs.python.org
```

**How it works:** At container startup, each hostname is resolved to IP addresses. Iptables rules are created to allow HTTPS (port 443) and HTTP (port 80) connections only to those IPs. All other outbound traffic is blocked.

### Filesystem Whitelist

By default, only your project directory is mounted (at `/workspace` inside the container). Add additional directories:

```ini
[filesystem]
# Read-only access (default)
/Users/yourname/shared-libs

# Read-write access
/Users/yourname/another-project:rw
```

### Proxy Configuration

If you're behind a corporate proxy, configure proxy settings:

```ini
[proxy]
http_proxy=http://proxy.company.com:8080
https_proxy=http://proxy.company.com:8080
no_proxy=localhost,127.0.0.1,.internal.company.com
```

**With authentication:**

```ini
[proxy]
http_proxy=http://username:password@proxy.company.com:8080
https_proxy=http://username:password@proxy.company.com:8080
```

These environment variables are passed to the container and used by OpenCode for API connections. Leave settings commented out (or remove the `[proxy]` section) to disable proxy support.

## Updating OpenCode

To get the latest version of OpenCode:

```bash
opencode-sandbox --update
```

This rebuilds the Docker image with the latest OpenCode release.

### Pinning a Specific Version

To use a specific OpenCode version, edit the Dockerfile in `~/.config/opencode-sandbox/`:

```dockerfile
# Change this line:
ARG OPENCODE_VERSION=latest

# To a specific version:
ARG OPENCODE_VERSION=1.1.48
```

Then rebuild:

```bash
opencode-sandbox --update
```

## Verifying the Sandbox

Run the smoke test to verify everything is working:

```bash
./smoke-test.sh
```

This tests:
- ✅ OpenCode is installed correctly
- ✅ Blocked hosts are unreachable (network isolation)
- ✅ Whitelisted hosts are reachable
- ✅ Host filesystem is isolated
- ✅ Read-only mounts prevent writes
- ✅ Running as non-root user
- ✅ All tools require explicit permission

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Host Machine                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Docker Container                        │   │
│  │                                                      │   │
│  │  ┌────────────────┐     ┌──────────────────────┐   │   │
│  │  │   iptables     │     │      OpenCode        │   │   │
│  │  │   firewall     │────▶│  (runs as 'coder')   │   │   │
│  │  │                │     │                      │   │   │
│  │  │  ALLOW:        │     │  /workspace (rw)     │   │   │
│  │  │  - DNS         │     │  ~/.config (rw)      │   │   │
│  │  │  - whitelist   │     │                      │   │   │
│  │  │                │     └──────────────────────┘   │   │
│  │  │  DENY:         │                                │   │
│  │  │  - everything  │                                │   │
│  │  │    else        │                                │   │
│  │  └────────────────┘                                │   │
│  │                                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Mounted from host:                                         │
│  - Project directory ──▶ /workspace                         │
│  - ~/.config/opencode ──▶ /home/coder/.config/opencode     │
│  - ~/.gitconfig ──▶ /home/coder/.gitconfig (read-only)     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Security Layers

1. **Docker isolation** - Container has its own filesystem, process space, and network stack
2. **iptables firewall** - Blocks all outbound traffic except whitelisted hosts
3. **Volume mounts** - Only explicitly mounted directories are accessible
4. **Non-root user** - OpenCode runs as unprivileged user `coder`
5. **Tool approval** - `autoApprove: []` config requires confirmation for every tool use

### Network Filtering Details

The entrypoint script:
1. Sets iptables default OUTPUT policy to DROP
2. Allows loopback (localhost) traffic
3. Allows DNS queries (UDP/TCP port 53)
4. Resolves each whitelisted hostname to IPs using `dig`
5. Creates ACCEPT rules for each resolved IP on ports 80/443

**Note:** DNS resolution happens at container startup. If an API's IP addresses change while the container is running, connections may fail. Restart the container to re-resolve.

## Command Reference

```bash
# Basic usage
opencode-sandbox [PROJECT_DIR]

# Options
opencode-sandbox --help          # Show help
opencode-sandbox --update        # Update to latest OpenCode
opencode-sandbox --config        # Edit configuration file
opencode-sandbox --no-network    # Disable ALL network access
opencode-sandbox --skip-firewall # Skip firewall (debug only)

# Shell access (while sandbox is running)
opencode-sandbox shell           # Open bash in running container
```

### Shell Access

While the sandbox is running, you can open a bash shell in the container from another terminal:

```bash
opencode-sandbox shell
```

This is useful for:
- Inspecting the container environment
- Running commands alongside OpenCode
- Debugging issues

## Troubleshooting

### "Docker daemon not running"

Start Docker Desktop and try again.

### Network connections failing

1. Check your whitelist includes the necessary hosts
2. Run with `--skip-firewall` to test if it's a firewall issue
3. Check Docker's network settings

### "Permission denied" errors

Ensure your project directory is accessible:
```bash
ls -la /path/to/project
```

### View container logs

```bash
# Run with debug output
docker run --rm -it \
    --cap-add=NET_ADMIN \
    -e "ALLOWED_HOSTS=api.anthropic.com" \
    -v $(pwd):/workspace \
    opencode-sandbox bash
```

## Uninstallation

```bash
./setup.sh --remove
```

This removes:
- The `opencode-sandbox` command
- The Docker image
- Optionally, the configuration directory

## Files

| File | Description |
|------|-------------|
| `setup.sh` | Installation script |
| `opencode-sandbox` | Main launcher script |
| `Dockerfile` | Container definition |
| `entrypoint.sh` | Container startup (firewall setup) |
| `opencode.json` | Default OpenCode config (no auto-approve) |
| `config.example` | Example configuration file |
| `smoke-test.sh` | Verification test suite |

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - See [LICENSE](LICENSE) file.

## Acknowledgments

Inspired by [this gist](https://gist.github.com/robbash/84aaa7c4133535b59cbaf0c1761031a4) using macOS sandbox-exec for OpenCode isolation.
