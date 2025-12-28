#!/bin/bash
set -e

# Security settings are mounted read-only from config/settings.json
# Network filtering is handled by the squid proxy (external to this container)

# Configure git identity
/opt/real-bin/git config --global user.name "${GIT_USER_NAME:-Claude (AI Assistant)}"
/opt/real-bin/git config --global user.email "${GIT_USER_EMAIL:-claude@sandbox.local}"

# Mark project directory as safe (prevents dubious ownership errors)
/opt/real-bin/git config --global --add safe.directory /home/devuser/project

# Configure per-project package persistence

# Ensure npm directory exists
mkdir -p /home/devuser/.npm-global

# Create sandbox-managed Python virtual environment (if not exists)
# This is stored in a named Docker volume, not the project directory
if [ ! -f "/home/devuser/.venv_sandbox/bin/python3" ]; then
    echo "Creating Claude sandbox virtual environment..." >&2
    # Clean up any incomplete venv contents (don't remove mount point itself)
    rm -rf /home/devuser/.venv_sandbox/* 2>/dev/null || true
    # Create fresh venv (with timeout to prevent hanging)
    timeout 30 /opt/system-python/bin/python3 -m venv /home/devuser/.venv_sandbox 2>&1 || {
        echo "Warning: Failed to create venv (or timed out). Using system Python as fallback." >&2
        rm -rf /home/devuser/.venv_sandbox/* 2>/dev/null || true
    }
    echo "Virtual environment setup complete." >&2
fi

# Execute the main command
# If --dangerously-skip-permissions flag is set and we're running claude, add the flag
if [[ "$DANGEROUSLY_SKIP_PERMISSIONS" == "true" && "$1" == "claude" ]]; then
    shift
    exec claude --dangerously-skip-permissions "$@"
else
    exec "$@"
fi
