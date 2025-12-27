# Claude Code Containerization & Security Design

## Overview

A Docker-based sandbox for running Claude Code with strict security controls. The container isolates Claude from the host system, prevents code pushes to remote repositories, and restricts network access to an allowlist of approved domains.

## Core Objectives

1. **Isolated Environment** - Run Claude Code inside a Docker container to prevent unauthorized access to the host system
2. **Push Restriction** - Block Claude from performing `git push` while allowing local commits and branch management
3. **GitHub Integration** - Enable `gh` CLI for reading/writing issues and creating Pull Requests only
4. **Data Protection** - Prevent exfiltration via network allowlist
5. **Developer Continuity** - Seamless file sharing with host IDE, persistent authentication

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST SYSTEM                              │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────────┐ │
│  │   PyCharm   │  │ Git (push)  │  │  claude-sandbox script   │ │
│  └──────┬──────┘  └─────────────┘  └────────────┬─────────────┘ │
│         │                                       │               │
│         ▼                                       ▼               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    PROJECT FOLDER                           ││
│  │                 /home/andreas/repos/X                       ││
│  └─────────────────────────────────────────────────────────────┘│
│         ▲                                       │               │
│         │ bind mount                            │ docker run    │
│         │                                       ▼               │
│  ┌──────┴──────────────────────────────────────────────────────┐│
│  │                    DOCKER CONTAINER                         ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  ││
│  │  │ Claude Code │  │  gh (limited)│  │ git (push blocked) │  ││
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘  ││
│  │                                                              ││
│  │  Network: allowlist (api.anthropic.com, api.github.com,     ││
│  │           pypi.org, npmjs.org) OR unrestricted via toggle   ││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│  Named Volumes: claude_creds, gh_creds (persist auth)           │
└─────────────────────────────────────────────────────────────────┘
```

**Key principle:** The container is disposable. Only auth tokens and project files persist. Everything else resets on each launch.

## Security Layers

### Layer 1: Docker Filesystem Isolation
- Container only sees `/home/devuser/project` (mounted project folder)
- No access to host's `~/.ssh`, other repos, or system files
- Fresh container each run (`--rm`) - any container modifications are wiped

### Layer 2: Network Allowlist
Default allowed domains:
- `api.anthropic.com` (Claude API)
- `api.github.com`, `github.com` (issues, PRs)
- `pypi.org`, `files.pythonhosted.org` (pip)
- `registry.npmjs.org` (npm)
- Additional docs sites added as needed

Toggle: `--unrestricted` flag disables allowlist for research sessions.

Implementation: iptables rules in container entrypoint.

### Layer 3: Git Wrapper Script
Replaces `/usr/bin/git` with a wrapper that blocks:
- `git push` (all forms)
- `git remote add|set-url|remove`
- `git credential*`

All other git commands pass through normally.

### Layer 4: GitHub CLI Wrapper
Replaces `/usr/bin/gh` with a wrapper that only allows:
- `gh issue *` (all issue operations)
- `gh pr create`

Blocks: `gh pr merge`, `gh release`, `gh repo`, etc.

### Layer 5: Claude Code Settings
`.claude/settings.json` deny list mirrors Layer 3 & 4 restrictions as defense-in-depth.

## File Structure

```
claude-sandbox/
├── Dockerfile                 # Container image definition
├── entrypoint.sh              # Startup script (network rules, checks)
├── claude-sandbox             # Host launch script
├── .env.example               # Template for required variables
│
├── wrappers/
│   ├── git-wrapper.sh         # Git command filter
│   └── gh-wrapper.sh          # GitHub CLI command filter
│
├── config/
│   ├── settings.json          # Claude Code deny rules (mounted read-only)
│   └── mcp_servers.json       # MCP config placeholder (mounted read-only)
│
└── docs/
    └── plans/
        └── 2025-12-27-containerization-design.md
```

## Implementation Files

### Dockerfile

```dockerfile
FROM node:22-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    python3 \
    python3-pip \
    iptables \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code (latest on each build)
RUN npm install -g @anthropic-ai/claude-code

# Store original binaries, install wrappers
RUN mv /usr/bin/git /usr/bin/git-real \
    && mv /usr/bin/gh /usr/bin/gh-real
COPY wrappers/git-wrapper.sh /usr/bin/git
COPY wrappers/gh-wrapper.sh /usr/bin/gh
RUN chmod +x /usr/bin/git /usr/bin/gh

# Create non-root user (UID/GID set at runtime)
RUN useradd -m -s /bin/bash devuser

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/devuser/project
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
```

### entrypoint.sh

```bash
#!/bin/bash
set -e

# Configure git identity
git-real config --global user.name "${GIT_USER_NAME:-Claude (AI Assistant)}"
git-real config --global user.email "${GIT_USER_EMAIL:-claude@sandbox.local}"

# Mark project directory as safe (prevents dubious ownership errors)
git-real config --global --add safe.directory /home/devuser/project

# Network allowlist (unless NETWORK_UNRESTRICTED=true)
if [[ "${NETWORK_UNRESTRICTED}" != "true" ]]; then
    echo "Applying network allowlist..."

    ALLOWED_DOMAINS=(
        "api.anthropic.com"
        "github.com"
        "api.github.com"
        "pypi.org"
        "files.pythonhosted.org"
        "registry.npmjs.org"
    )

    # Flush existing rules, set default DROP for outbound
    iptables -F OUTPUT
    iptables -P OUTPUT DROP

    # Allow loopback
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established connections
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow DNS (needed to resolve domains)
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

    # Allow each domain
    for domain in "${ALLOWED_DOMAINS[@]}"; do
        iptables -A OUTPUT -d "$domain" -j ACCEPT
    done

    echo "Network restricted to: ${ALLOWED_DOMAINS[*]}"
else
    echo "Network unrestricted mode enabled."
fi

# Execute the main command
exec "$@"
```

### wrappers/git-wrapper.sh

```bash
#!/bin/bash
COMMAND="$1"

case "$COMMAND" in
    push)
        echo "BLOCKED: 'git push' is not allowed in this sandbox."
        echo "To submit changes, use 'gh pr create' to open a pull request."
        echo "The human operator will push from the host after review."
        exit 1
        ;;
    remote)
        if [[ "$2" =~ ^(add|set-url|remove)$ ]]; then
            echo "BLOCKED: 'git remote $2' is not allowed in this sandbox."
            echo "Remote configuration is managed by the host system."
            exit 1
        fi
        ;;
    credential*)
        echo "BLOCKED: 'git credential' commands are not allowed in this sandbox."
        echo "Credentials are managed by the host system."
        exit 1
        ;;
esac

# Pass through to real git
exec /usr/bin/git-real "$@"
```

### wrappers/gh-wrapper.sh

```bash
#!/bin/bash
COMMAND="$1"

case "$COMMAND" in
    issue)
        # All issue operations allowed
        exec /usr/bin/gh-real "$@"
        ;;
    pr)
        if [[ "$2" == "create" ]]; then
            exec /usr/bin/gh-real "$@"
        else
            echo "BLOCKED: 'gh pr $2' is not allowed in this sandbox."
            echo "You can create PRs with 'gh pr create', but other PR operations require human approval."
            exit 1
        fi
        ;;
    *)
        echo "BLOCKED: 'gh $COMMAND' is not allowed in this sandbox."
        echo "Allowed commands: 'gh issue *', 'gh pr create'"
        exit 1
        ;;
esac
```

### config/settings.json

```json
{
  "permissions": {
    "deny": [
      "Bash(git push*)",
      "Bash(git remote add*)",
      "Bash(git remote set-url*)",
      "Bash(git remote remove*)",
      "Bash(git credential*)",
      "Bash(gh pr merge*)",
      "Bash(gh pr close*)",
      "Bash(gh pr edit*)",
      "Bash(gh release*)",
      "Bash(gh repo*)",
      "Bash(gh auth logout*)",
      "Bash(gh config*)"
    ]
  }
}
```

### config/mcp_servers.json

```json
{
  "mcpServers": {}
}
```

### claude-sandbox (host launch script)

```bash
#!/bin/bash
set -e

# Configuration
IMAGE_NAME="claude-sandbox"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Require project path argument
if [[ -z "$1" ]]; then
    echo "Usage: claude-sandbox /path/to/project [--unrestricted]"
    exit 1
fi

PROJECT_PATH="$(readlink -f "$1")"
if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Error: '$PROJECT_PATH' is not a directory"
    exit 1
fi

# Check for unrestricted flag
NETWORK_UNRESTRICTED="false"
if [[ "$2" == "--unrestricted" ]]; then
    NETWORK_UNRESTRICTED="true"
    echo "Warning: Network unrestricted mode enabled"
fi

# Load environment variables
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
fi

# Run container
docker run --rm -it \
    --name claude-sandbox \
    --cap-add=NET_ADMIN \
    --user "$(id -u):$(id -g)" \
    -e "GIT_USER_NAME=${GIT_USER_NAME:-Claude (AI Assistant)}" \
    -e "GIT_USER_EMAIL=${GIT_USER_EMAIL:-claude@sandbox.local}" \
    -e "NETWORK_UNRESTRICTED=${NETWORK_UNRESTRICTED}" \
    -v "${PROJECT_PATH}:/home/devuser/project" \
    -v claude_creds:/home/devuser/.claude \
    -v gh_creds:/home/devuser/.config/gh \
    -v "${SCRIPT_DIR}/config/settings.json:/home/devuser/.claude/settings.json:ro" \
    -v "${SCRIPT_DIR}/config/mcp_servers.json:/home/devuser/.claude/mcp_servers.json:ro" \
    "$IMAGE_NAME"
```

### .env.example

```bash
# Git identity for Claude's commits
GIT_USER_NAME="Claude (AI Assistant)"
GIT_USER_EMAIL="claude@yourdomain.com"
```

## Setup & Usage

### First-Time Setup

```bash
# 1. Clone/create the sandbox project
cd ~/repos
mkdir claude-sandbox && cd claude-sandbox

# 2. Create all files from this design document

# 3. Configure environment
cp .env.example .env
# Edit .env with your values

# 4. Build the image
docker build -t claude-sandbox .

# 5. Make launch script executable and add to PATH
chmod +x claude-sandbox
ln -s $(pwd)/claude-sandbox ~/bin/claude-sandbox

# 6. First run - authenticate
claude-sandbox ~/repos/some-project

# Inside container:
gh auth login   # One-time GitHub auth, stored in gh_creds volume
claude          # One-time Claude auth via browser, stored in claude_creds volume

# 7. Done - credentials persist across runs
```

### Daily Workflow

```bash
# Start sandbox on any project (restricted network)
claude-sandbox ~/repos/my-project

# Start with unrestricted network for research
claude-sandbox ~/repos/my-project --unrestricted

# Inside container, Claude Code is ready
claude

# When done, exit - container is removed, auth persists
exit
```

### Updating Claude Code

```bash
# Rebuild to get latest version
docker build -t claude-sandbox --no-cache .
```

### Adding MCP Servers

Edit `config/mcp_servers.json` on the host:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["/path/to/server.js"]
    }
  }
}
```

The container mounts this file read-only, so Claude cannot modify it.

## Data Persistence

| Data | Location | Survives container restart? |
|------|----------|----------------------------|
| Claude auth tokens | `claude_creds` volume | Yes |
| GitHub auth tokens | `gh_creds` volume | Yes |
| Project files | Bind mount from host | Yes |
| Pip/npm packages installed during session | Container filesystem | No |
| MCP config | Mounted from host (read-only) | Yes |

## Security Summary

| Threat | Mitigation |
|--------|------------|
| Accidental git push | Git wrapper blocks `push` command |
| Push to attacker-controlled remote | Git wrapper blocks `remote add/set-url` |
| Credential theft | Git wrapper blocks `credential` commands |
| PR merge without review | GH wrapper only allows `pr create` |
| Data exfiltration via network | Allowlist restricts outbound connections |
| Access to host filesystem | Docker isolation, only project folder mounted |
| Tampering with container | Fresh container each run (`--rm`) |
| Bypass via Claude Code internals | Belt-and-suspenders deny list in settings.json |
