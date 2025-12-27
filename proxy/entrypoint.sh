#!/bin/bash
set -e

CONFIG_FILE="/etc/squid/squid.conf"

# If unrestricted mode, replace the allowlist rule with allow all
if [[ "${NETWORK_UNRESTRICTED}" == "true" ]]; then
    echo "Proxy: UNRESTRICTED mode - allowing all domains"
    # Create a modified config that allows all
    sed 's/http_access allow localnet allowed_domains/http_access allow localnet/' "$CONFIG_FILE" > /tmp/squid.conf
    CONFIG_FILE="/tmp/squid.conf"
else
    echo "Proxy: RESTRICTED mode - allowlist active"
fi

# Clean up any stale pid file
rm -f /run/squid.pid

echo "Starting squid..."

# Run squid with the appropriate config (foreground, debug level 1)
exec squid -N -d 1 -f "$CONFIG_FILE"
