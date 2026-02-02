# OpenCode Sandbox

Run [OpenCode](https://opencode.ai) in a secure, network-isolated Docker environment with domain whitelisting.

## Features

- **Network isolation** - Agent container has no direct internet access
- **Domain whitelisting** - Only approved domains reachable via squid proxy
- **Filesystem isolation** - Only your project directory is mounted
- **Simple CLI** - Just run `opencode-sandbox /path/to/project`
- **Auto-cleanup** - Containers stop when you exit
- **Existing config support** - Automatically uses your host opencode settings

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Host Machine                                   │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        Docker Environment                           │   │
│   │                                                                     │   │
│   │   ┌─────────────────────┐         ┌─────────────────────┐           │   │
│   │   │    Proxy Container  │         │   Agent Container   │           │   │
│   │   │       (squid)       │         │     (opencode)      │           │   │
│   │   │                     │         │                     │           │   │
│   │   │  Domain whitelist:  │         │  • Node.js          │           │   │
│   │   │  .anthropic.com    │◄────────│  • Go               │           │   │
│   │   │  .github.com       │  HTTP    │  • Python           │           │   │
│   │   │  .npmjs.org        │  PROXY   │  • ripgrep, git...  │           │   │
│   │   │  ...               │         │                     │           │   │
│   │   │                     │         │  /workspace ◄───────┼───────────┼── Project
│   │   └──────────┬──────────┘         └─────────────────────┘           │   │
│   │              │                              │                       │   │
│   │   ═══════════╪══════════════════════════════╪═══════════════════    │   │
│   │   external   │                    internal  │ (no internet)         │   │
│   │   network    │                    network   │                       │   │
│   └──────────────┼──────────────────────────────────────────────────────┘   │
│                  ▼                                                          │
│              Internet (filtered)                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) for macOS
- Bash shell

### Installation

```bash
git clone https://github.com/yourusername/opencode-sandbox.git
cd opencode-sandbox
./setup.sh
```

### Usage

```bash
# Run in current directory
opencode-sandbox

# Run in a specific directory  
opencode-sandbox ~/Projects/my-app

# Open a shell in the running sandbox (from another terminal)
opencode-sandbox shell

# Stop the sandbox
opencode-sandbox stop
```

When you press `Ctrl+C` or exit opencode, the sandbox containers automatically shut down.

## Configuration

Edit the configuration file:

```bash
opencode-sandbox --config
```

Or directly edit `~/.config/opencode-sandbox/config`:

```ini
[network]
# Domains opencode can connect to (one per line)
# Leading dot matches subdomains: .github.com matches api.github.com
.anthropic.com
.openai.com
.github.com
.npmjs.org

[filesystem]
# Additional directories to mount (optional)
# /path/to/dir       - read-only (default)
# /path/to/dir:rw    - read-write
```

### Corporate Proxy Configuration

If your network requires a proxy to access the internet (common in corporate environments), configure it in the `[proxy]` section:

```ini
[proxy]
http_proxy=http://proxy.company.com:8080
https_proxy=http://proxy.company.com:8080
no_proxy=localhost,127.0.0.1,.internal.company.com,intranet.local
```

**How it works:**
- The sandbox's squid proxy routes whitelisted traffic through your corporate proxy
- `no_proxy` domains are accessed directly (useful for intranet hosts)
- Both the domain whitelist AND corporate proxy rules are enforced

### Default Allowed Domains

The default configuration allows:

| Category | Domains |
|----------|---------|
| LLM APIs | `.anthropic.com`, `.openai.com` |
| GitHub | `.github.com`, `.githubusercontent.com` |
| npm | `.npmjs.org`, `.npmjs.com`, `registry.yarnpkg.com` |
| Go | `proxy.golang.org`, `sum.golang.org`, `storage.googleapis.com` |
| Python | `.pypi.org`, `.pythonhosted.org` |

## Command Reference

```bash
opencode-sandbox [OPTIONS] [PROJECT_DIR]

Commands:
  shell              Open bash shell in running sandbox
  stop               Stop all sandbox containers
  update             Update opencode to latest version

Options:
  -h, --help         Show help message
  -b, --build        Force rebuild Docker images
  -u, --update       Update opencode to latest version
  -c, --config       Open configuration file in editor
  --no-network       Disable all network access
```

## How It Works

1. **Launcher script** reads your config and generates a docker-compose setup
2. **Proxy container** (squid) starts with your domain whitelist
3. **Agent container** starts on an internal network with no direct internet
4. All agent traffic routes through the proxy, which enforces the whitelist
5. When you exit, both containers are automatically removed

### Automatic Host Config Mounting

The sandbox automatically mounts your existing opencode configuration:

- `~/.config/opencode` - Your opencode settings
- `~/.cache/opencode` - Cached data
- `~/.local/share/opencode` - Application data
- `~/.local/state/opencode` - State data
- `~/.gitconfig` - Git configuration (read-only)

This means your API keys, model preferences, and other settings work automatically.

## Verifying Network Isolation

From inside the sandbox, test that isolation is working:

```bash
# This should work (allowed domain)
curl https://api.github.com

# This should fail (blocked domain)
curl https://example.com

# This should fail (bypassing proxy)
curl --noproxy '*' https://api.github.com
```

## Updating OpenCode

To get the latest version of opencode:

```bash
opencode-sandbox update
```

This rebuilds the agent Docker image with the latest opencode release.

## Troubleshooting

### "Docker daemon not running"

Start Docker Desktop and try again.

### Network connections failing

1. Check your whitelist includes the domain: `opencode-sandbox --config`
2. Rebuild: `opencode-sandbox --build`

### Permission errors on /workspace

Ensure your project directory is readable by your user.

### View container logs

```bash
docker logs opencode-sandbox-proxy
docker logs opencode-sandbox-agent
```

## Uninstallation

```bash
./setup.sh --remove
```

## Files

| File | Description |
|------|-------------|
| `setup.sh` | Installation script |
| `opencode-sandbox` | Main launcher script |
| `agent/Dockerfile` | Agent container with opencode + dev tools |
| `proxy/Dockerfile` | Squid proxy container |
| `proxy/squid.conf` | Squid configuration |
| `smoke-test.sh` | Test script to verify setup |

## Security Notes

- Agent container is physically isolated on an internal Docker network
- Cannot bypass proxy - there's no route to the internet
- No `NET_ADMIN` or other privileged capabilities required
- Only your project directory is mounted read-write
- Host SSH keys and other sensitive files are NOT mounted

## License

MIT License - See [LICENSE](LICENSE) file.