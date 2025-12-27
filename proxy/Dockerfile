FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    squid \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy configuration
COPY squid.conf /etc/squid/squid.conf
COPY allowlist.txt /etc/squid/allowlist.txt
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create cache and log directories with correct permissions
RUN mkdir -p /var/spool/squid /var/log/squid \
    && chown -R proxy:proxy /var/spool/squid /var/log/squid

EXPOSE 3128

ENTRYPOINT ["/entrypoint.sh"]
