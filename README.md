# AI Sandbox

Run **OpenCode** (default) or **Claude Code** in a secure, sandboxed Docker environment. The sandbox blocks code pushes and restricts network access to prevent data leaks.

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
```

**Common Options:**
*   `--build`: Rebuild the container (use if you updated the sandbox code).
*   `--unrestricted`: Disable network allowlist (use with caution).
*   `--stop-proxy`: Stop the shared network proxy.

**Exit:** Press `Ctrl+D` or type `/exit`. Containers are cleaned up automatically.

## 📋 Network Allowlist

Traffic is restricted to domains in `proxy/allowlist.txt`.
*   **Defaults:** GitHub, Anthropic, OpenCode, PyPI, NPM.
*   **Add Domains:** Edit `proxy/allowlist.txt` and run `./ai-sandbox-reload` (while the sandbox/proxy is running).

## 📎 Clipboard Support

*   **Linux:** Run `xhost +local:docker` on your host to enable copy/paste.
*   **WSL:** Works automatically with WSLg.

## ⚡ Alias

Add this to your shell config (`~/.bashrc` or `~/.zshrc`) to run `oc` from any directory:

```bash
alias oc='/path/to/ai-sandbox/ai-sandbox . --opencode'
```
