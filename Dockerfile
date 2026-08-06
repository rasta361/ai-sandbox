FROM node:22-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    python3 \
    python3-pip \
    python3-venv \
    iputils-ping \
    ffmpeg \
    pulseaudio-utils \
    socat \
    xclip \
    xsel \
    wl-clipboard \
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

# Install Bun (required by OpenCode for plugin management)
# Install to /opt/bun so it's accessible to all users, runtime cache configured via env vars
ENV BUN_INSTALL=/opt/bun
RUN curl -fsSL https://bun.sh/install | bash \
    && ln -s /opt/bun/bin/bun /usr/local/bin/bun \
    && chmod -R 755 /opt/bun

# Install Claude Code (latest on each build)
RUN npm install -g @anthropic-ai/claude-code

# Install OpenCode AI
RUN curl -fsSL https://opencode.ai/install | bash \
    && mv /root/.opencode /opt/opencode

# Install Pi coding agent (latest on each build)
# --ignore-scripts matches the official pi installer recommendation
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Install Go (latest stable on each build, matching the "latest on build" pattern
# used for the tools above). The official tarball goes to /usr/local/go; symlink
# the toolchain into /usr/local/bin — which is on the PATH the compose file pins at
# runtime — so `go`/`gofmt` resolve without a Dockerfile ENV (compose would
# override it). GOPATH (~/go, incl. go install'd bins) and the build cache
# (~/.cache/go-build) are backed by shared volumes (see docker-compose.yml), so
# modules and build artifacts persist across sessions and projects.
RUN GO_VERSION="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)" \
    && curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && ln -s /usr/local/go/bin/go /usr/local/bin/go \
    && ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Install OpenTofu (latest stable on each build, same pattern as Go above).
# Uses the standalone tarball from GitHub releases rather than the .deb repo so
# there's no extra apt source to keep alive; the release version comes from the
# /releases/latest redirect instead of the GitHub API to avoid unauthenticated
# rate limits breaking builds. The published SHA256SUMS is checked before the
# binary is unpacked into /usr/local/bin (on the PATH the compose file pins).
# `tofu init` needs registry.opentofu.org at runtime — see proxy/allowlist.txt.
RUN TOFU_VERSION="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/opentofu/opentofu/releases/latest | sed 's#.*/tag/v##')" \
    && TOFU_ARCH="$(dpkg --print-architecture)" \
    && TOFU_TARBALL="tofu_${TOFU_VERSION}_linux_${TOFU_ARCH}.tar.gz" \
    && TOFU_BASE="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}" \
    && curl -fsSL "${TOFU_BASE}/${TOFU_TARBALL}" -o /tmp/tofu.tar.gz \
    && curl -fsSL "${TOFU_BASE}/tofu_${TOFU_VERSION}_SHA256SUMS" -o /tmp/tofu.sha256sums \
    && grep " ${TOFU_TARBALL}\$" /tmp/tofu.sha256sums | sed "s#${TOFU_TARBALL}#/tmp/tofu.tar.gz#" | sha256sum -c - \
    && tar -C /usr/local/bin -xzf /tmp/tofu.tar.gz tofu \
    && chmod 755 /usr/local/bin/tofu \
    && rm /tmp/tofu.tar.gz /tmp/tofu.sha256sums

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
    /home/devuser/.cache/bun \
    /home/devuser/.bun/install/cache \
    /home/devuser/.bun/install/global \
    /home/devuser/.opencode \
    /home/devuser/.pi \
    /home/devuser/go/bin \
    /home/devuser/.cache/go-build \
    && chmod -R 777 /home/devuser

# Copy Claude settings to a staging location (will be copied to volume at startup)
COPY config/settings.json /opt/claude-settings.json
RUN chmod 444 /opt/claude-settings.json

# Copy OpenCode settings to a staging location (will be copied to volume at startup)
COPY config/opencode.json /opt/opencode-settings.json
RUN chmod 444 /opt/opencode-settings.json

# Copy Pi settings + local-model helper to staging (installed to ~/.pi at startup)
COPY config/pi-settings.json /opt/pi-settings.json
RUN chmod 444 /opt/pi-settings.json
COPY config/pi-localmodel-setup.sh /opt/pi-localmodel-setup.sh
RUN chmod 555 /opt/pi-localmodel-setup.sh
# `lm-refresh`: re-run local-model discovery from inside the sandbox (e.g. after
# starting LM Studio or opening the firewall) — pi hot-reloads models.json on
# /model, so no container restart is needed.
RUN ln -s /opt/pi-localmodel-setup.sh /usr/local/bin/lm-refresh

# Copy OpenCode plugin to staging location (will be copied to plugin dir at startup)
COPY config/notification.js /opt/opencode-notification-plugin.js
RUN chmod 444 /opt/opencode-notification-plugin.js

# Install OpenCode wrapper to force 0.0.0.0 binding
RUN mkdir -p /home/devuser/.opencode/bin
COPY wrappers/opencode-wrapper.sh /home/devuser/.opencode/bin/opencode
RUN chmod 755 /home/devuser/.opencode/bin/opencode

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

WORKDIR /home/devuser
ENTRYPOINT ["/entrypoint.sh"]
# Tool selection is driven by the AI_TOOL env var in entrypoint.sh, not by CMD.
# Keep CMD empty so nothing leaks into "$@" — a non-empty CMD (e.g. "claude") would
# be passed to the CLI as a literal initial prompt.
CMD []
