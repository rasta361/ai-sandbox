FROM node:22-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    python3 \
    python3-pip \
    python3-venv \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Move system Python binaries to safe location for wrapper scripts
RUN mkdir -p /opt/system-python/bin \
    && cp /usr/bin/python3 /opt/system-python/bin/python3 \
    && cp /usr/bin/pip3 /opt/system-python/bin/pip3

# Install Python/pip wrappers for auto-venv detection
COPY wrappers/python-wrapper.sh /usr/local/bin/python3
COPY wrappers/python-wrapper.sh /usr/local/bin/python
COPY wrappers/pip-wrapper.sh /usr/local/bin/pip
COPY wrappers/pip-wrapper.sh /usr/local/bin/pip3
RUN chmod 755 /usr/local/bin/python3 /usr/local/bin/python /usr/local/bin/pip /usr/local/bin/pip3

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code (latest on each build)
RUN npm install -g @anthropic-ai/claude-code

# Store original binaries in /opt, install wrappers
RUN mkdir -p /opt/real-bin \
    && mv /usr/bin/git /opt/real-bin/git \
    && mv /usr/bin/gh /opt/real-bin/gh
COPY wrappers/git-wrapper.sh /usr/bin/git
COPY wrappers/gh-wrapper.sh /usr/bin/gh
RUN chmod 755 /usr/bin/git /usr/bin/gh

# Create home directory (UID/GID set at runtime via --user)
# Make it world-writable so any UID can use it
RUN mkdir -p /home/devuser/.claude /home/devuser/.config/gh \
    && chmod -R 777 /home/devuser

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

WORKDIR /home/devuser/project
ENTRYPOINT ["/entrypoint.sh"]
CMD ["claude"]
