# AI Sandbox

Run **OpenCode** (default), **Claude Code**, **Gemini**, or the **Pi** coding agent in a secure, sandboxed Docker environment. The sandbox blocks code pushes and restricts network access to prevent data leaks.

## 🚀 Quick Start

1.  **Setup Configuration:**
    ```bash
    cp .env.example .env
    # (Optional) Edit .env to set your git user/email
    ```

2.  **Start the Sandbox:**
    Run this from your project root (or provide the path as an argument):
    ```bash
    /path/to/ai-sandbox .
    ```
    *This starts **OpenCode** by default.*

3.  **Authenticate (First Run Only):**
    Credentials persist across restarts.
    *   **GitHub:** Run `gh auth login` inside the sandbox.
    *   **OpenCode / Gemini:**
        1.  The tool will prompt you to login and show a URL.
        2.  Open that URL in your host browser and follow the workflow.
        3.  **Final Step:** The browser will eventually show a "connection refused" error on `localhost:8085`. This is expected.
        4.  **Copy the URL** of that error page (the one starting with `http://localhost:8085/...`).
        5.  Open a **new terminal** on your host and run:
            ```bash
            ./ai-sandbox-auth "http://localhost:8085/..."
            ```
        6.  The script will complete the login for you.

## 🛠️ Usage

```bash
# Start with OpenCode (Default)
./ai-sandbox /path/to/project

# Start with Claude Code
./ai-sandbox /path/to/project --claude

# Start with the Pi coding agent
./ai-sandbox /path/to/project --pi

# Pi against a local LM Studio model (see "Local Models" below)
./ai-sandbox /path/to/project --pi --local-model
```

**Pi Authentication (First Run Only):**
Pi credentials persist across restarts in a dedicated volume.
*   Run `/login` inside Pi to authenticate a subscription provider (e.g. Claude Pro/Max), or set an API key such as `ANTHROPIC_API_KEY` in your `.env`.
*   If `/login` opens a browser OAuth flow that redirects to a `localhost` "connection refused" page, complete it the same way as OpenCode: copy that URL and run `./ai-sandbox-auth "<url>"` from a host terminal.

**Common Options:**
*   `--build`: Rebuild the container (use if you updated the sandbox code).
*   `--unrestricted`: **Bypass the proxy entirely** — the sandbox gets a normal bridge with direct internet access instead of going through the allowlist. This leaves the fail-closed guarantee (no allowlist, no egress audit log) and is meant for research; use with caution. Only this session is affected — the shared proxy and other sessions keep their restrictions. See [Unrestricted sessions](#unrestricted-sessions).
*   `--stop-proxy`: Stop the shared network proxy.

**Exit:** Press `Ctrl+D` or type `/exit`. Containers are cleaned up automatically.

## 📋 Network Allowlist

Traffic is restricted to domains in `proxy/allowlist.txt`.
*   **Defaults:** GitHub, Anthropic, OpenCode, PyPI, NPM.
*   **Add Domains:** Edit `proxy/allowlist.txt` and run `./ai-sandbox-reload` (while the sandbox/proxy is running).

### How it's enforced (fail-closed)

The sandbox container is attached **only** to an `internal: true` Docker network
(`ai-sandbox-proxy-net`). Docker installs no NAT or external routing for that
network, so the container has **no route to the internet or the host** — its only
reachable peer is the squid proxy. The proxy is dual-homed: it also sits on a
separate internet-facing network (`ai-sandbox-egress`) and forwards only
allowlisted requests.

This means the restriction does **not** depend on apps honoring `HTTP_PROXY`. A
process that ignores the proxy env vars (or speaks raw TCP/UDP/DNS) simply has
nowhere to go. **In the default topology, never attach the sandbox service to a
second bridge network** — that reopens a direct path around the allowlist. (The
one sanctioned exception is `--unrestricted`, which *replaces* — not adds to — the
proxy-net with a direct-egress bridge on purpose; see below.)

> ⚠️ Consequence: the sandbox cannot reach host services directly (e.g. host
> audio via PulseAudio, or a local LM Studio server). Anything host-side must be
> routed *through* the proxy.

### Unrestricted sessions

`--unrestricted` is the deliberate escape hatch from the fail-closed model. Rather
than trying to "open" the shared proxy (which would drop the allowlist for *every*
concurrent session, and only for HTTP/HTTPS at that), it takes the sandbox **off**
the proxy entirely: an overlay compose file (`docker-compose.unrestricted.yml`)
puts the container on its own ordinary bridge network — which Docker NATs to the
internet — and blanks the `HTTP_PROXY`/`HTTPS_PROXY` vars. The shared proxy is not
even started for that session.

Because this only swaps one container's network, it is **per-session**: other
running sandboxes keep their allowlist, and there is no shared global state to
reset afterwards. The trade-offs, by design:

*   **No allowlist** — the session can reach any host, on any port, over any
    protocol (not just HTTP/HTTPS).
*   **No egress audit log** — traffic no longer passes through squid, so it isn't
    recorded in the proxy's access log.
*   **Host services work directly** — e.g. `--local-model` reaches
    `host.docker.internal:1234` without a squid rule (subject to your host
    firewall).

Requires Docker Compose ≥ 2.24.4 (for the `!override` / `!reset` merge tags). You
can preview exactly what the overlay produces without launching anything:

```bash
docker compose -f docker-compose.yml -f docker-compose.unrestricted.yml config
```

## 🧠 Local Models (LM Studio)

Pi can use a local [LM Studio](https://lmstudio.ai) model running on your host,
opted into with `--local-model`:

```bash
./ai-sandbox /path/to/project --pi --local-model
```

**On your host:**
1.  In LM Studio, load a model and enable **"Serve on Local Network"** so it binds `0.0.0.0:1234`. Confirm the *actual* bind (the displayed LAN URL can be misleading): `ss -tlnp | grep ':1234'` should show `0.0.0.0:1234`, not `127.0.0.1:1234`.
2.  **Linux host firewall:** containers can't reach host services by default. The launcher detects this and prints the exact one-time rule to run, scoped to the proxy's network, e.g.:
    ```bash
    sudo iptables -I INPUT -p tcp -s <egress-subnet> --dport 1234 -j ACCEPT
    ```
    This is intentionally **not persisted** across reboot — the hole re-closes on its own. Re-run it (the launcher will prompt) when you next need it.

**What the flag does:**
*   Adds a single tight rule to the proxy allowing **only** `host.docker.internal:1234` — every other destination stays blocked, and the traffic is still routed and logged through squid. Without the flag there is no host access at all.
*   On launch, **pre-flight checks** that the model server is reachable; if not, it prints the firewall command and waits (press Enter to retry, `s` to skip).
*   Auto-discovers loaded models from LM Studio's `/v1/models` endpoint and writes `~/.pi/agent/models.json`, setting the first as pi's active model. (Pi has no native discovery; this fills that gap.)

**Refreshing without a restart:** started LM Studio or opened the firewall *after* pi was already running? Run **`lm-refresh`** from pi's shell (`!lm-refresh`), then reopen `/model` — `models.json` is re-read live, no container restart.

**Notes:**
*   The proxy is shared, so enabling `--local-model` recreates it (a brief blip if other sandboxes are running). Once enabled it stays open until `--stop-proxy`.
*   To pin a specific model id (and as a fallback if discovery fails), set `LMSTUDIO_MODEL` in `.env`.

> 🔒 **Security:** "Serve on Local Network" binds LM Studio to `0.0.0.0`, exposing its **unauthenticated** API to your whole LAN — fine on a trusted network, less so on shared/public Wi-Fi. The firewall rule is scoped to the proxy's network (not all Docker), and the in-sandbox access is a single host port, still routed through the audited proxy.

## 📎 Clipboard Support

*   **Linux:** Run `xhost +local:docker` on your host to enable copy/paste.
*   **WSL:** Works automatically with WSLg.

## ⚡ Alias

Add this to your shell config (`~/.bashrc` or `~/.zshrc`) to run `oc` from any directory:

```bash
alias oc='/path/to/ai-sandbox/ai-sandbox . --opencode'
```
