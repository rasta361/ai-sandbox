#!/bin/bash
set -e

# AI Sandbox entrypoint - supports Claude Code and OpenCode
# Network filtering is handled by the squid proxy (external to this container)

# Change to project directory immediately (before any tool runs)
PROJECT_NAME="${PROJECT_NAME:-project}"
cd "/home/devuser/${PROJECT_NAME}"

# Copy Claude settings into the mounted volume (read-only security config)
# Remove existing file first (may be read-only from previous run)
rm -f /home/devuser/.claude/settings.json 2>/dev/null || true
cp /opt/claude-settings.json /home/devuser/.claude/settings.json
chmod 444 /home/devuser/.claude/settings.json

# Copy OpenCode settings into the mounted volume (read-only security config)
# Remove existing file first (may be read-only from previous run)
rm -f /home/devuser/.config/opencode/opencode.json 2>/dev/null || true
cp /opt/opencode-settings.json /home/devuser/.config/opencode/opencode.json
chmod 444 /home/devuser/.config/opencode/opencode.json

# Copy OpenCode notification plugin to the plugin directory
mkdir -p /home/devuser/.config/opencode/plugin
rm -f /home/devuser/.config/opencode/plugin/notification.js 2>/dev/null || true
cp /opt/opencode-notification-plugin.js /home/devuser/.config/opencode/plugin/notification.js
chmod 444 /home/devuser/.config/opencode/plugin/notification.js

# Configure git identity
/opt/real-bin/git config --global user.name "${GIT_USER_NAME:-AI Assistant}"
/opt/real-bin/git config --global user.email "${GIT_USER_EMAIL:-ai@sandbox.local}"

# Mark project directory as safe (prevents dubious ownership errors)
/opt/real-bin/git config --global --add safe.directory "/home/devuser/${PROJECT_NAME}"

# Configure per-project package persistence

# Ensure npm directory exists
mkdir -p /home/devuser/.npm-global

# Ensure OpenCode cache directory exists and is writable
mkdir -p /home/devuser/.cache/opencode

# Create sandbox-managed Python virtual environment (if not exists)
# This is stored in a named Docker volume, not the project directory
if [ ! -f "/home/devuser/.venv_sandbox/bin/python3" ]; then
    echo "Creating sandbox virtual environment..." >&2
    # Clean up any incomplete venv contents (don't remove mount point itself)
    rm -rf /home/devuser/.venv_sandbox/* 2>/dev/null || true
    # Create fresh venv (with timeout to prevent hanging)
    timeout 30 /opt/system-python/bin/python3 -m venv /home/devuser/.venv_sandbox 2>&1 || {
        echo "Warning: Failed to create venv (or timed out). Using system Python as fallback." >&2
        rm -rf /home/devuser/.venv_sandbox/* 2>/dev/null || true
    }
    echo "Virtual environment setup complete." >&2
fi

# Start vibe-kanban in background if enabled
if [[ "${VIBE_KANBAN:-true}" == "true" ]]; then
    echo "Starting vibe-kanban on ${VIBE_KANBAN_HOST:-0.0.0.0}:${VIBE_KANBAN_PORT:-8100}..." >&2
    HOST="${VIBE_KANBAN_HOST:-0.0.0.0}" PORT="${VIBE_KANBAN_PORT:-8100}" vibe-kanban >/dev/null 2>&1 &
fi

# Determine which AI tool to run
AI_TOOL="${AI_TOOL:-claude}"

# Execute the main command based on AI_TOOL environment variable
case "$AI_TOOL" in
    opencode)
        exec /home/devuser/.opencode/bin/opencode .
        ;;
    claude|*)
        # If --dangerously-skip-permissions flag is set, add the flag
        if [[ "$DANGEROUSLY_SKIP_PERMISSIONS" == "true" ]]; then
            exec claude --dangerously-skip-permissions "$@"
        else
            exec claude "$@"
        fi
        ;;
esac
