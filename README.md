# OpenCode Sandbox

Run [OpenCode](https://opencode.ai) in a secure, network-isolated Docker environment with domain whitelisting.

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
│   │   │  ┌───────────────┐  │         │  • Node.js          │           │   │
│   │   │  │ allowed_      │  │         │  • Go               │           │   │
│   │   │  │ domains.txt   │  │         │  • Python           │           │   │
│   │   │  │               │  │         │  • ripgrep, git...  │           │   │
│   │   │  │ .anthropic.com│  │◄────────│                     │           │   │
│   │   │  │ .github.com   │  │  HTTP   │  HTTP_PROXY=proxy   │           │   │
│   │   │  │ .npmjs.org    │  │  PROXY  │  HTTPS_PROXY=proxy  │           │   │
│   │   │  │ ...           │  │         │                     │           │   │
│   │   │  └───────────────┘  │         │  /workspace ◄───────┼───────────┼───┼── Project Dir
│   │   │                     │         │                     │           │   │
│   │   └──────────┬──────────┘         └─────────────────────┘           │   │
│   │              │                              │                       │   │
│   │   ═══════════╪══════════════════════════════╪═══════════════════    │   │
│   │   external   │                    internal  │ (no internet)         │   │
│   │   network    │                    network   │                       │   │
│   │              │                                                      │   │
│   └──────────────┼──────────────────────────────────────────────────────┘   │
│                  │                                                          │
│                  ▼                                                          │
│              Internet (filtered: only allowed domains)                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Security Properties:**

- **Agent container has zero direct internet access** - It's on an internal-only Docker network
- **All outbound traffic goes through squid proxy** - Which only allows explicitly whitelisted domains
- **No TLS interception** - HTTPS CONNECT method passes through without decryption
- **Filesystem isolation** - Only your project directory is mounted (no access to home dir, SSH keys, etc.)
- **No privileged capabilities** - Unlike iptables-based approaches, no `NET_ADMIN` required

## Quick Start

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) for macOS
- An Anthropic API key (or OpenAI API key)

### 1. Clone and Configure

```bash
git clone https://github.com/yourusername/opencode-sandbox.git
cd opencode-sandbox

# Create your environment file
cp env.example .env
```

Edit `.env` with your settings:

```bash
PROJECT_DIR=/path/to/your/project
ANTHROPIC_API_KEY=sk-ant-xxxxx
```

### 2. Start the Sandbox

```bash
docker compose up -d
```

### 3. Run OpenCode

```bash
docker compose exec agent opencode
```

Or open a shell in the sandbox:

```bash
docker compose exec agent bash
```

### 4. Run Smoke Tests (Optional)

Verify everything is working correctly:

```bash
./smoke-test.sh
```

This tests network isolation, proxy filtering, tool installation, and more.

### 5. Stop the Sandbox

```bash
docker compose down
```

## Configuration

### Environment Variables (`.env`)

| Variable | Required | Description |
|----------|----------|-------------|
| `PROJECT_DIR` | Yes | Path to your project directory (mounted as `/workspace`) |
| `ANTHROPIC_API_KEY` | Yes* | Anthropic API key for Claude |
| `OPENAI_API_KEY` | No | OpenAI API key (if using OpenAI models) |
| `GIT_TOKEN` | No | GitHub personal access token for push/pull |
| `GIT_USER` | No | Git username (default: `git`) |
| `GIT_HOST` | No | Git host (default: `github.com`) |

*At least one API key is required.

| `OPENCODE_HOST_CONFIG` | No | Path to host `~/.config/opencode` (to import existing config) |
| `OPENCODE_HOST_CACHE` | No | Path to host `~/.cache/opencode` (to import existing cache) |

### Domain Allowlist

Edit `proxy/allowed_domains.txt` to control which domains the agent can reach:

```
# LLM APIs
.anthropic.com
.openai.com

# GitHub
.github.com
.githubusercontent.com

# Package registries
.npmjs.org
proxy.golang.org
.pypi.org
```

After editing, rebuild the proxy:

```bash
docker compose build proxy
docker compose up -d
```

**Domain format:**
- `.example.com` - matches `example.com` and all subdomains (`api.example.com`, `www.example.com`, etc.)
- `api.example.com` - matches only that exact domain

### Using Existing OpenCode Configuration

If you have opencode already configured on your host (with auth or other settings), you can mount that configuration into the container:

```bash
# In your .env file (macOS/Linux paths)
OPENCODE_HOST_CONFIG=/Users/yourname/.config/opencode
OPENCODE_HOST_CACHE=/Users/yourname/.cache/opencode
```

The container will import these files on startup (read-only). This is useful for:
- Reusing existing authentication/API key configurations
- Sharing opencode preferences between host and sandbox
- Avoiding re-configuration when you already have opencode set up

**Note:** The files are copied into the container, not bind-mounted directly, so changes made inside the container won't affect your host configuration.

### Adding Custom Tools

The agent container includes common development tools:
- Node.js (LTS)
- Go 1.22
- Python 3
- ripgrep, git, jq, vim

To add more tools, edit `agent/Dockerfile` and rebuild:

```bash
docker compose build agent
docker compose up -d
```

## Git Push/Pull

Git operations use HTTPS with a Personal Access Token (no SSH needed).

### Setup

1. Generate a token at https://github.com/settings/tokens
   - For private repos: select `repo` scope
   - For public repos only: select `public_repo` scope

2. Add to your `.env`:
   ```
   GIT_TOKEN=ghp_xxxxxxxxxxxx
   ```

3. Ensure `github.com` is in the allowlist (it is by default)

### Usage

Inside the sandbox, git push/pull will work automatically:

```bash
cd /workspace
git pull origin main
# ... make changes ...
git push origin main
```

## Common Operations

### Interactive Shell

```bash
docker compose exec agent bash
```

### View Proxy Logs

```bash
docker compose logs proxy -f
```

### Check What's Blocked

Watch the proxy logs while running commands in the agent:

```bash
# Terminal 1: Watch proxy
docker compose logs proxy -f

# Terminal 2: Test in agent
docker compose exec agent curl https://example.com
# You'll see "TCP_DENIED" in the proxy logs
```

### Rebuild After Config Changes

```bash
# After editing allowed_domains.txt
docker compose build proxy && docker compose up -d

# After editing agent/Dockerfile
docker compose build agent && docker compose up -d

# Rebuild everything
docker compose build && docker compose up -d
```

### Update OpenCode Version

Edit `agent/Dockerfile` to pin a specific version:

```dockerfile
ARG OPENCODE_VERSION=1.2.3
```

Then rebuild:

```bash
docker compose build agent && docker compose up -d
```

## Troubleshooting

### "Connection refused" or network errors

1. Check the proxy is healthy:
   ```bash
   docker compose ps
   ```

2. Verify the domain is in the allowlist:
   ```bash
   cat proxy/allowed_domains.txt | grep yourdomain
   ```

3. Check proxy logs for denied requests:
   ```bash
   docker compose logs proxy
   ```

### API calls failing

Ensure your API provider's domain is in the allowlist:
- Anthropic: `.anthropic.com`
- OpenAI: `.openai.com`

### Git push/pull not working

1. Verify `GIT_TOKEN` is set in `.env`
2. Ensure `.github.com` is in the allowlist
3. Check the token has correct permissions

### "Permission denied" on /workspace

The workspace is mounted from your host. Ensure your user can read/write the project directory.

## Security Notes

### What's Protected

- **Network**: Agent can only reach explicitly allowed domains
- **Filesystem**: Only the mounted project directory is accessible
- **Credentials**: API keys and tokens are passed via environment variables (not files)
- **No SSH keys**: Unlike other approaches, your `~/.ssh` is not mounted

### What's Not Protected

- **Build-time network**: The Dockerfile has full network during `docker build`
- **Proxy container**: Has full internet access (but only serves the agent)
- **Docker daemon**: If compromised, isolation could be bypassed

### Best Practices

1. **Minimize the allowlist** - Only add domains you actually need
2. **Use short-lived tokens** - Rotate your `GIT_TOKEN` regularly
3. **Review proxy logs** - Periodically check what domains are being accessed
4. **Keep containers updated** - Rebuild periodically to get security patches

## Smoke Tests

The `smoke-test.sh` script validates your sandbox setup:

```bash
./smoke-test.sh
```

**What it tests:**
- ✓ Containers are running and healthy
- ✓ Proxy environment variables are configured
- ✓ Required tools are installed (opencode, Node.js, Go, Python, git, ripgrep)
- ✓ Agent runs as non-root user
- ✓ Workspace is mounted and writable
- ✓ Allowed domains are accessible (api.anthropic.com, api.github.com)
- ✓ Blocked domains are denied (example.com, httpbin.org)
- ✓ Network isolation works (agent cannot bypass proxy)

Run this after initial setup or whenever you make configuration changes.

## Files

| File | Description |
|------|-------------|
| `docker-compose.yml` | Orchestrates proxy and agent containers |
| `proxy/Dockerfile` | Squid proxy container |
| `proxy/squid.conf` | Squid configuration |
| `proxy/allowed_domains.txt` | **Edit this** - domain allowlist |
| `agent/Dockerfile` | OpenCode agent with dev tools |
| `agent/entrypoint.sh` | Agent startup script |
| `agent/opencode.json` | OpenCode config (no auto-approve) |
| `env.example` | Example environment file |
| `smoke-test.sh` | Smoke test script to validate setup |

## License

MIT License - See [LICENSE](LICENSE) file.