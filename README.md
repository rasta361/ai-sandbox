# AI Sandbox

Run Claude Code or OpenCode in a sandboxed Docker environment where they **cannot push code, access arbitrary websites, or leak credentials**.

## Why?

AI coding tools run with full shell access. This sandbox adds safety layers:

| Threat | Protection |
|--------|------------|
| Pushes malicious code | `git push` blocked via wrapper scripts |
| Exfiltrates data to attacker server | Network allowlist (squid proxy) |
| Steals credentials | `git credential` and `gh auth logout` blocked |
| Modifies remotes | `git remote add/set-url/remove` blocked |

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  ai-sandbox (no direct internet)                     │
│  └─► squid-proxy (allowlist) ─► Internet             │
└──────────────────────────────────────────────────────┘
```

Two containers: The AI tool runs isolated, all traffic routes through a filtering proxy.

## Usage

```bash
# First time: copy and edit .env
cp .env.example .env

# Start sandbox with Claude Code (default)
./ai-sandbox /path/to/project

# Start sandbox with OpenCode
./ai-sandbox /path/to/project --opencode

# Multiple instances
./ai-sandbox /path/to/project-a -n sandbox-a
./ai-sandbox /path/to/project-b -n sandbox-b --opencode

# Unrestricted network (bypass allowlist)
./ai-sandbox /path/to/project --unrestricted
```

**Arguments:**
- `--claude` — Use Claude Code (default)
- `--opencode` — Use OpenCode
- `-n, --name NAME` — Instance name (for running multiple sandboxes)
- `--unrestricted` — Disable network allowlist

**Stop:** Exit the AI tool (`Ctrl+D` or `/exit`). Containers are cleaned up automatically.

**First run:** Authenticate once inside the container:
```bash
# For Claude Code
gh auth login   # GitHub
claude          # Anthropic

# For OpenCode
opencode auth login
```
Credentials persist in Docker volumes across runs.

## Network Allowlist

Edit `proxy/allowlist.txt` — one domain per line (supports wildcards like `.github.com`).

Default: `.anthropic.com`, `.github.com`, `.githubusercontent.com`, `.pypi.org`, `.pythonhosted.org`, `.npmjs.org`, `.npmjs.com`, `.opencode.ai`

Reload without restart:
```bash
./ai-sandbox-reload
```

## Rebuild

```bash
./ai-sandbox-rebuild        # Rebuild sandbox image
docker compose build --no-cache # Rebuild all images
```
