FROM node:22-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    python3 \
    python3-pip \
    python3-venv \
    iputils-ping \
    ffmpeg \
    pulseaudio-utils \
    && rm -rf /var/lib/apt/lists/*

# Install edge-tts for text-to-speech notifications
RUN pip3 install --break-system-packages edge-tts

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

# Install vibe-kanban for task visualization
RUN npm install -g vibe-kanban

# Install OpenCode AI
RUN curl -fsSL https://opencode.ai/install | bash \
    && mv /root/.opencode /opt/opencode

# Store original binaries in /opt, install wrappers
RUN mkdir -p /opt/real-bin \
    && mv /usr/bin/git /opt/real-bin/git \
    && mv /usr/bin/gh /opt/real-bin/gh
COPY wrappers/git-wrapper.sh /usr/bin/git
COPY wrappers/gh-wrapper.sh /usr/bin/gh
RUN chmod 755 /usr/bin/git /usr/bin/gh

# Create home directory (UID/GID set at runtime via --user)
# Make it world-writable so any UID can use it
# Pre-create volume mount points to ensure correct permissions
RUN mkdir -p /home/devuser/.claude \
    /home/devuser/.config/gh \
    /home/devuser/.config/opencode \
    /home/devuser/.npm-global \
    /home/devuser/.venv_sandbox \
    /home/devuser/.local/share/opencode \
    /home/devuser/.cache/opencode \
    /home/devuser/.opencode \
    && chmod -R 777 /home/devuser

# Copy Claude settings to a staging location (will be copied to volume at startup)
COPY config/settings.json /opt/claude-settings.json
RUN chmod 444 /opt/claude-settings.json

# Copy OpenCode settings to a staging location (will be copied to volume at startup)
COPY config/opencode.json /opt/opencode-settings.json
RUN chmod 444 /opt/opencode-settings.json

# Copy OpenCode plugin to staging location (will be copied to plugin dir at startup)
COPY config/notification.js /opt/opencode-notification-plugin.js
RUN chmod 444 /opt/opencode-notification-plugin.js

# Link OpenCode binary to user's home (will be in PATH)
RUN ln -s /opt/opencode/bin/opencode /home/devuser/.opencode/bin/opencode 2>/dev/null || \
    (mkdir -p /home/devuser/.opencode/bin && ln -s /opt/opencode/bin/opencode /home/devuser/.opencode/bin/opencode)

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

WORKDIR /home/devuser
ENTRYPOINT ["/entrypoint.sh"]
CMD ["claude"]
