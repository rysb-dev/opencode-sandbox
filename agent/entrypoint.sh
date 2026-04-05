#!/bin/bash
# Agent container entrypoint
# Copies SSH keys from mounted directory to ensure correct permissions

# If SSH keys are mounted, copy them with correct permissions
if [ -d /mnt/ssh ] && [ "$(ls -A /mnt/ssh 2>/dev/null)" ]; then
    mkdir -p ~/.ssh
    cp -f /mnt/ssh/id_* ~/.ssh/ 2>/dev/null || true
    cp -f /mnt/ssh/known_hosts* ~/.ssh/ 2>/dev/null || true
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_* 2>/dev/null || true
    chmod 644 ~/.ssh/*.pub 2>/dev/null || true
    chmod 644 ~/.ssh/known_hosts* 2>/dev/null || true
fi

# Mark /workspace as safe for git (ownership differs due to container mount)
git config --global --add safe.directory /workspace 2>/dev/null || true

# Auto-setup Python virtual environment for Python projects
if [ "${VENV_ISOLATE:-true}" = "true" ] && [ -f /workspace/pyproject.toml ]; then
    echo "[entrypoint] Python project detected, running uv sync..."
    cd /workspace
    uv sync --all-packages --all-groups 2>&1 || echo "[entrypoint] Warning: uv sync failed (non-fatal)"
fi

# Execute the command (default: opencode)
exec "$@"
