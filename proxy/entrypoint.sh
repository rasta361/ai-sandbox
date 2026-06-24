#!/bin/bash
set -e

CONFIG_FILE="/etc/squid/squid.conf"
WORK_CONFIG="/tmp/squid.conf"

# Work on a copy so we can layer optional rules without touching the baked config.
cp "$CONFIG_FILE" "$WORK_CONFIG"

# If unrestricted mode, replace the allowlist rule with allow all
if [[ "${NETWORK_UNRESTRICTED}" == "true" ]]; then
    echo "Proxy: UNRESTRICTED mode - allowing all domains"
    sed -i 's/http_access allow localnet allowed_domains/http_access allow localnet/' "$WORK_CONFIG"
else
    echo "Proxy: RESTRICTED mode - allowlist active"
fi

# If local-model access is enabled, allow EXACTLY host.docker.internal:1234
# (a local LM Studio server). The rule is inserted ahead of the "deny non-safe
# ports" line so port 1234 is permitted for this one destination only — without
# widening Safe_ports for any other domain. squid evaluates http_access
# top-to-bottom, first match wins.
if [[ "${ALLOW_HOST_MODEL}" == "true" ]]; then
    echo "Proxy: LOCAL MODEL access ENABLED (host.docker.internal:1234)"
    sed -i '/^# Security: deny non-safe ports/i \
# --local-model: allow ONLY the local LM Studio server, nothing else\
acl host_model_dst dstdomain host.docker.internal\
acl host_model_port port 1234\
http_access allow localnet host_model_dst host_model_port\
' "$WORK_CONFIG"
else
    echo "Proxy: local model access disabled"
fi

# Clean up any stale pid file
rm -f /run/squid.pid

echo "Starting squid..."

# Run squid with the assembled config (foreground, debug level 1)
exec squid -N -d 1 -f "$WORK_CONFIG"
