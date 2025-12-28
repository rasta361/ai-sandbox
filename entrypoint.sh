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

# Create sandbox-managed Python virtual environment at project root (if not exists)
if [ ! -d "/home/devuser/project/.venv_claude_sandbox" ]; then
    echo "Creating Claude sandbox virtual environment..."
    /opt/system-python/bin/python3 -m venv /home/devuser/project/.venv_claude_sandbox
    # Auto-gitignore
    cat > /home/devuser/project/.venv_claude_sandbox/.gitignore <<'EOF'
# Ignore virtual environment
*
!.gitignore
EOF
fi

# Ensure npm global directory exists (will be in named volume)
mkdir -p /home/devuser/.npm-global

# Execute the main command
# If --dangerously-skip-permissions flag is set and we're running claude, add the flag
if [[ "$DANGEROUSLY_SKIP_PERMISSIONS" == "true" && "$1" == "claude" ]]; then
    shift
    exec claude --dangerously-skip-permissions "$@"
else
    exec "$@"
fi
