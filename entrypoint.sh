#!/bin/bash
set -e

# Security settings are mounted read-only from config/settings.json
# Network filtering is handled by the squid proxy (external to this container)

# Configure git identity
/opt/real-bin/git config --global user.name "${GIT_USER_NAME:-Claude (AI Assistant)}"
/opt/real-bin/git config --global user.email "${GIT_USER_EMAIL:-claude@sandbox.local}"

# Mark project directory as safe (prevents dubious ownership errors)
/opt/real-bin/git config --global --add safe.directory /home/devuser/project

# Execute the main command
exec "$@"
