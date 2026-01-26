#!/bin/bash
# Wrapper for OpenCode to ensure it binds to 0.0.0.0
# This is necessary for Docker port forwarding to work for authentication callbacks

exec /opt/opencode/bin/opencode --hostname 0.0.0.0 "$@"
