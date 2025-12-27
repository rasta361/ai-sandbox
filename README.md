# Claude Code Sandbox

Run Claude Code in a sandboxed Docker environment where it **cannot push code, access arbitrary websites, or leak credentials**.

## Why?

Claude Code runs with full shell access. This sandbox adds safety layers:

| Threat | Protection |
|--------|------------|
| Pushes malicious code | `git push` blocked via wrapper scripts |
| Exfiltrates data to attacker server | Network allowlist (squid proxy) |
| Steals credentials | `git credential` and `gh auth logout` blocked |
| Modifies remotes | `git remote add/set-url/remove` blocked |

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  claude-sandbox (no direct internet)                 │
│  └─► squid-proxy (allowlist) ─► Internet             │
└──────────────────────────────────────────────────────┘
```

Two containers: Claude runs isolated, all traffic routes through a filtering proxy.

## Usage

```bash
# First time: copy and edit .env
cp .env.example .env

# Start sandbox
./claude-sandbox /path/to/project

# Multiple instances
./claude-sandbox /path/to/project-a -n sandbox-a
./claude-sandbox /path/to/project-b -n sandbox-b

# Unrestricted network (bypass allowlist)
./claude-sandbox /path/to/project --unrestricted
```

**Arguments:**
- `-n, --name NAME` — Instance name (for running multiple sandboxes)
- `--unrestricted` — Disable network allowlist

**Stop:** Exit Claude (`Ctrl+D` or `/exit`). Containers are cleaned up automatically.

**First run:** Authenticate once inside the container:
```bash
gh auth login   # GitHub
claude          # Anthropic
```
Credentials persist in a Docker volume across runs.

## Network Allowlist

Edit `proxy/allowlist.txt` — one domain per line (supports wildcards like `.github.com`).

Default: `.anthropic.com`, `.github.com`, `.githubusercontent.com`, `.pypi.org`, `.pythonhosted.org`, `.npmjs.org`, `.npmjs.com`

Reload without restart:
```bash
./claude-sandbox-reload
```

## Rebuild

```bash
./claude-sandbox-rebuild        # Rebuild claude image
docker compose build --no-cache # Rebuild all images
```
