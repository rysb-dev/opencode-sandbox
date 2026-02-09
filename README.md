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
github.com
api.github.com
codeload.github.com
raw.githubusercontent.com
objects.githubusercontent.com
pypi.org
files.pythonhosted.org
crates.io
static.crates.io
index.crates.io

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

### Custom Environment Variables

Pass custom environment variables to the agent container using the `[environment]` section:

```ini
[environment]
NODE_EXTRA_CA_CERTS=/mnt/Users/yourname/certs/corporate-ca.pem
MY_CUSTOM_VAR=some_value
```

This is useful for:
- Custom CA certificates (corporate environments)
- API keys or tokens
- Any environment configuration the agent needs

**Note:** If referencing mounted files, use the container path (e.g., `/mnt/...`). See the `[filesystem]` section for mounting additional directories.

### Default Allowed Domains

The default configuration allows:

| Category | Domains |
|----------|---------|
| LLM APIs | `.anthropic.com`, `.openai.com` |
| GitHub | `github.com`, `api.github.com`, `codeload.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com` |
| GitHub Copilot | `copilot-proxy.githubusercontent.com`, `origin-tracker.githubusercontent.com`, `.githubcopilot.com` |
| Python | `pypi.org`, `files.pythonhosted.org` |
| Rust | `crates.io`, `static.crates.io`, `index.crates.io` |

**Note:** The whitelist is intentionally narrow. Broader wildcards like `.github.com` would allow access to GitHub Pages sites (potentially controlled by anyone), increasing data exfiltration risk.

## Command Reference

```bash
opencode-sandbox [OPTIONS] [PROJECT_DIR]

Commands:
  acp [PROJECT_DIR]  Run in ACP mode for editor integration (e.g., Zed)
  shell              Open bash shell in running sandbox
  stop               Stop all sandbox containers
  update             Update opencode to latest version

Options:
  -h, --help         Show help message
  -b, --build        Force rebuild Docker images
  -u, --update       Update opencode to latest version
  -c, --config       Open configuration file in editor
  --no-network       Disable all network access
  --with-ssh         Mount ~/.ssh keys into container (disabled by default)
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
- `~/.gitconfig` - Git configuration

This means your API keys, model preferences, and other settings work automatically.

### Git over SSH

Git SSH operations (clone, fetch, pull, push) require the `--with-ssh` flag:

```bash
opencode-sandbox --with-ssh ~/Projects/myapp
```

This mounts your `~/.ssh` directory (read-only) and copies keys into the container with correct permissions. SSH traffic is tunneled through the squid proxy.

**Why disabled by default?** SSH keys give the agent ability to authenticate as you to git hosts. If you're concerned about a compromised agent pushing malicious code, use HTTPS git operations instead.

**Requirements:**
- Pass `--with-ssh` flag
- Your SSH keys must be in `~/.ssh/` (e.g., `~/.ssh/id_ed25519`)
- The git host must be in your `[network]` whitelist

**First-time setup:** You may need to add `/workspace` as a safe directory for git:
```bash
git config --global --add safe.directory /workspace
```

## Editor Integration (ACP Mode)

The sandbox supports the [Agent Client Protocol (ACP)](https://agentclientprotocol.com), allowing editors like [Zed](https://zed.dev) to use sandboxed OpenCode as an AI agent.

### How It Works

ACP mode starts the same proxy + agent container stack, but instead of an interactive terminal, it bridges the editor's stdin/stdout to `opencode acp` running inside the container. The editor communicates via JSON-RPC over this pipe while all network isolation remains in effect.

### Zed Editor Setup

Add this to `~/.config/zed/settings.json`:

```json
{
  "agent_servers": {
    "OpenCode (Sandboxed)": {
      "type": "custom",
      "command": "opencode-sandbox",
      "args": ["acp"],
      "env": {}
    }
  }
}
```

Options like `--with-ssh` or `--no-network` can be added to the `args` array:

```json
"args": ["acp", "--with-ssh"]
```

Then use the command palette action `agent: new thread` in Zed to start a session.

### Manual Usage

```bash
# Run ACP mode in current directory
opencode-sandbox acp

# Run ACP mode for a specific project
opencode-sandbox acp ~/Projects/my-app

# ACP mode with options
opencode-sandbox acp --with-ssh ~/Projects/my-app
```

### Model Configuration

Models are configured through OpenCode's own config at `~/.config/opencode/opencode.json` (not through Zed). This config is automatically mounted into the sandbox.

```json
{
  "model": "anthropic/claude-sonnet-4-5",
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "{env:ANTHROPIC_API_KEY}"
      }
    }
  }
}
```

### How Path Mapping Works

Editors send the host machine's project path (e.g., `/Users/you/Projects/myapp`) to OpenCode via ACP. OpenCode then uses that path as the working directory when running tools like bash. Since the project is mounted at `/workspace` inside the container, the sandbox automatically creates a symlink from the host path to `/workspace` so that tool execution works correctly. This is transparent — no configuration needed.

### Notes

- ACP mode uses a separate container set (`opencode-sandbox-acp-*`) so it can run alongside TUI mode
- Containers start when the editor connects and stop when it disconnects
- All sandbox config (`[network]`, `[filesystem]`, `[environment]`) applies to ACP mode

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
- SSH keys are NOT mounted by default (use `--with-ssh` to enable)

## License

MIT License - See [LICENSE](LICENSE) file.