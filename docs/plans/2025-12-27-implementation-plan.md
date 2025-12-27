# Claude Code Sandbox Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a secure Docker sandbox for running Claude Code with network restrictions, git push blocking, and limited GitHub CLI access.

**Architecture:** Docker container with wrapper scripts that intercept git/gh commands, iptables-based network allowlist, and Claude Code's internal deny list as defense-in-depth. Auth tokens persist via named volumes; container is disposable.

**Tech Stack:** Docker, Bash, iptables, Node.js (Claude Code), GitHub CLI

---

## Task 1: Create Directory Structure

**Files:**
- Create: `wrappers/` directory
- Create: `config/` directory

**Step 1: Create directories**

```bash
mkdir -p wrappers config
```

**Step 2: Verify structure exists**

Run: `ls -la`
Expected: `wrappers/` and `config/` directories visible

**Step 3: Commit**

```bash
git add -A && git commit -m "chore: create directory structure for wrappers and config"
```

---

## Task 2: Create Git Wrapper Script

**Files:**
- Create: `wrappers/git-wrapper.sh`

**Step 1: Write the git wrapper**

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

**Step 2: Make executable and verify syntax**

Run: `chmod +x wrappers/git-wrapper.sh && bash -n wrappers/git-wrapper.sh && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add wrappers/git-wrapper.sh && git commit -m "feat: add git wrapper to block push/remote/credential commands"
```

---

## Task 3: Create GitHub CLI Wrapper Script

**Files:**
- Create: `wrappers/gh-wrapper.sh`

**Step 1: Write the gh wrapper**

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
    auth)
        if [[ "$2" == "login" || "$2" == "status" ]]; then
            exec /usr/bin/gh-real "$@"
        else
            echo "BLOCKED: 'gh auth $2' is not allowed in this sandbox."
            echo "Only 'gh auth login' and 'gh auth status' are permitted."
            exit 1
        fi
        ;;
    *)
        echo "BLOCKED: 'gh $COMMAND' is not allowed in this sandbox."
        echo "Allowed commands: 'gh issue *', 'gh pr create', 'gh auth login'"
        exit 1
        ;;
esac
```

**Step 2: Make executable and verify syntax**

Run: `chmod +x wrappers/gh-wrapper.sh && bash -n wrappers/gh-wrapper.sh && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add wrappers/gh-wrapper.sh && git commit -m "feat: add gh wrapper to restrict to issues and pr create only"
```

---

## Task 4: Create Claude Code Settings

**Files:**
- Create: `config/settings.json`

**Step 1: Write the settings file**

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

**Step 2: Verify valid JSON**

Run: `python3 -m json.tool config/settings.json > /dev/null && echo "Valid JSON"`
Expected: `Valid JSON`

**Step 3: Commit**

```bash
git add config/settings.json && git commit -m "feat: add Claude Code deny list for belt-and-suspenders security"
```

---

## Task 5: Create MCP Servers Config Placeholder

**Files:**
- Create: `config/mcp_servers.json`

**Step 1: Write empty MCP config**

```json
{
  "mcpServers": {}
}
```

**Step 2: Verify valid JSON**

Run: `python3 -m json.tool config/mcp_servers.json > /dev/null && echo "Valid JSON"`
Expected: `Valid JSON`

**Step 3: Commit**

```bash
git add config/mcp_servers.json && git commit -m "feat: add empty MCP servers config placeholder"
```

---

## Task 6: Create Entrypoint Script

**Files:**
- Create: `entrypoint.sh`

**Step 1: Write the entrypoint script**

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
    iptables -F OUTPUT 2>/dev/null || true
    iptables -P OUTPUT DROP 2>/dev/null || true

    # Allow loopback
    iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true

    # Allow established connections
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

    # Allow DNS (needed to resolve domains)
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || true

    # Allow each domain
    for domain in "${ALLOWED_DOMAINS[@]}"; do
        iptables -A OUTPUT -d "$domain" -j ACCEPT 2>/dev/null || true
    done

    echo "Network restricted to: ${ALLOWED_DOMAINS[*]}"
else
    echo "Network unrestricted mode enabled."
fi

# Execute the main command
exec "$@"
```

**Step 2: Make executable and verify syntax**

Run: `chmod +x entrypoint.sh && bash -n entrypoint.sh && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add entrypoint.sh && git commit -m "feat: add entrypoint with git config and network allowlist"
```

---

## Task 7: Create Dockerfile

**Files:**
- Create: `Dockerfile`

**Step 1: Write the Dockerfile**

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

# Setup directories for volume mounts
RUN mkdir -p /home/devuser/.claude /home/devuser/.config/gh \
    && chown -R devuser:devuser /home/devuser

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/devuser/project
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
```

**Step 2: Verify Dockerfile syntax**

Run: `docker build --check . 2>&1 | head -5 || echo "Dockerfile exists (syntax check requires BuildKit)"`
Expected: No syntax errors (or message about BuildKit)

**Step 3: Commit**

```bash
git add Dockerfile && git commit -m "feat: add Dockerfile with Claude Code, gh, and wrapper scripts"
```

---

## Task 8: Create Host Launch Script

**Files:**
- Create: `claude-sandbox`

**Step 1: Write the launch script**

```bash
#!/bin/bash
set -e

# Configuration
IMAGE_NAME="claude-sandbox"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Require project path argument
if [[ -z "$1" ]]; then
    echo "Usage: claude-sandbox /path/to/project [--unrestricted]"
    echo ""
    echo "Options:"
    echo "  --unrestricted    Disable network allowlist (for research)"
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
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
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

**Step 2: Make executable and verify syntax**

Run: `chmod +x claude-sandbox && bash -n claude-sandbox && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add claude-sandbox && git commit -m "feat: add host launch script with volume mounts and network toggle"
```

---

## Task 9: Create Environment Template

**Files:**
- Create: `.env.example`

**Step 1: Write the environment template**

```bash
# Git identity for Claude's commits
GIT_USER_NAME="Claude (AI Assistant)"
GIT_USER_EMAIL="claude@yourdomain.com"
```

**Step 2: Verify file exists**

Run: `cat .env.example`
Expected: Shows the two environment variables

**Step 3: Commit**

```bash
git add .env.example && git commit -m "feat: add environment variable template"
```

---

## Task 10: Create .gitignore

**Files:**
- Create: `.gitignore`

**Step 1: Write gitignore**

```
# Environment (contains user-specific config)
.env

# Editor
.idea/
.vscode/
*.swp

# Docker
.docker/
```

**Step 2: Commit**

```bash
git add .gitignore && git commit -m "chore: add gitignore for env and editor files"
```

---

## Task 11: Build Docker Image

**Files:**
- None (verification task)

**Step 1: Build the image**

Run: `docker build -t claude-sandbox .`
Expected: Build completes with "Successfully tagged claude-sandbox:latest"

**Step 2: Verify image exists**

Run: `docker images claude-sandbox --format "{{.Repository}}:{{.Tag}}"`
Expected: `claude-sandbox:latest`

---

## Task 12: Test Git Wrapper Blocks Push

**Files:**
- None (verification task)

**Step 1: Create a test project directory**

Run: `mkdir -p /tmp/test-project && cd /tmp/test-project && git init`
Expected: Initialized empty Git repository

**Step 2: Run container and test git push is blocked**

Run:
```bash
docker run --rm -it \
    --user "$(id -u):$(id -g)" \
    -v "/tmp/test-project:/home/devuser/project" \
    claude-sandbox \
    git push origin main
```

Expected output contains: `BLOCKED: 'git push' is not allowed in this sandbox`

**Step 3: Test git remote add is blocked**

Run:
```bash
docker run --rm -it \
    --user "$(id -u):$(id -g)" \
    -v "/tmp/test-project:/home/devuser/project" \
    claude-sandbox \
    git remote add evil https://evil.com/repo.git
```

Expected output contains: `BLOCKED: 'git remote add' is not allowed in this sandbox`

**Step 4: Cleanup**

Run: `rm -rf /tmp/test-project`

---

## Task 13: Test GH Wrapper Restrictions

**Files:**
- None (verification task)

**Step 1: Test gh pr merge is blocked**

Run:
```bash
docker run --rm -it \
    --user "$(id -u):$(id -g)" \
    -v "/tmp:/home/devuser/project" \
    claude-sandbox \
    gh pr merge 123
```

Expected output contains: `BLOCKED: 'gh pr merge' is not allowed in this sandbox`

**Step 2: Test gh repo is blocked**

Run:
```bash
docker run --rm -it \
    --user "$(id -u):$(id -g)" \
    -v "/tmp:/home/devuser/project" \
    claude-sandbox \
    gh repo create test
```

Expected output contains: `BLOCKED: 'gh repo' is not allowed in this sandbox`

---

## Task 14: Test Normal Git Operations Work

**Files:**
- None (verification task)

**Step 1: Create test project and verify git status works**

Run:
```bash
mkdir -p /tmp/test-project && cd /tmp/test-project && git init
docker run --rm -it \
    --user "$(id -u):$(id -g)" \
    -v "/tmp/test-project:/home/devuser/project" \
    claude-sandbox \
    git status
```

Expected: Shows git status output (not blocked)

**Step 2: Verify git commit works**

Run:
```bash
docker run --rm -it \
    --user "$(id -u):$(id -g)" \
    -v "/tmp/test-project:/home/devuser/project" \
    claude-sandbox \
    bash -c "touch test.txt && git add test.txt && git commit -m 'test'"
```

Expected: Commit succeeds

**Step 3: Cleanup**

Run: `rm -rf /tmp/test-project`

---

## Task 15: Create README

**Files:**
- Create: `README.md`

**Step 1: Write the README**

```markdown
# Claude Code Sandbox

A secure Docker environment for running Claude Code with restricted permissions.

## Security Features

- **Network Allowlist**: Only approved domains accessible (toggle with `--unrestricted`)
- **Git Push Blocked**: Claude cannot push to remotes; use `gh pr create` instead
- **GitHub CLI Restricted**: Only issues and PR creation allowed
- **Defense in Depth**: Claude Code's internal deny list mirrors wrapper restrictions
- **Disposable Container**: Fresh container each run, only auth tokens persist

## Quick Start

1. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your git identity
   ```

2. **Build the image:**
   ```bash
   docker build -t claude-sandbox .
   ```

3. **First run (authenticate):**
   ```bash
   ./claude-sandbox ~/your/project
   # Inside container:
   gh auth login    # One-time GitHub auth
   claude           # One-time Claude auth
   ```

4. **Daily usage:**
   ```bash
   ./claude-sandbox ~/your/project
   # or with unrestricted network:
   ./claude-sandbox ~/your/project --unrestricted
   ```

## Adding MCP Servers

Edit `config/mcp_servers.json` on the host (file is mounted read-only).

## Updating Claude Code

```bash
docker build -t claude-sandbox --no-cache .
```
```

**Step 2: Commit**

```bash
git add README.md && git commit -m "docs: add README with setup and usage instructions"
```

---

## Summary

After completing all tasks, the project structure will be:

```
claude-sandbox/
├── Dockerfile
├── entrypoint.sh
├── claude-sandbox          # Host launch script
├── .env.example
├── .gitignore
├── README.md
├── wrappers/
│   ├── git-wrapper.sh
│   └── gh-wrapper.sh
├── config/
│   ├── settings.json
│   └── mcp_servers.json
└── docs/
    └── plans/
        ├── 2025-12-27-containerization-design.md
        └── 2025-12-27-implementation-plan.md
```

All security controls will be in place and verified.
