#!/bin/bash
# Configure pi to use a local LM Studio server.
#
# Pi has no native model discovery, so we query LM Studio's OpenAI-compatible
# /v1/models endpoint (through the squid proxy, which the --local-model flag has
# opened for host.docker.internal:1234) and generate ~/.pi/agent/models.json from
# whatever models are currently loaded. The active model in settings.json is set
# to the first one. Set LMSTUDIO_MODEL to pin a specific id; if discovery fails we
# fall back to that (or a placeholder), so pi still starts.
set -u

# Use the real system python, bypassing the auto-venv wrapper on PATH.
PY="/opt/system-python/bin/python3"
PI_DIR="/home/devuser/.pi/agent"
BASE_URL="http://host.docker.internal:1234/v1"
mkdir -p "$PI_DIR"

echo "Discovering local models from ${BASE_URL}/models (via proxy) ..." >&2
# Goes through the proxy (host.docker.internal is not in NO_PROXY), so squid's
# --local-model rule applies. Capture the HTTP status so failures are explained
# rather than silently falling back.
BODY_FILE="$(mktemp)"
# curl always prints %{http_code} (000 on connection failure) even when it exits
# non-zero, so capture it directly — don't append a fallback or it doubles up.
HTTP_CODE="$(curl -s -o "$BODY_FILE" -w '%{http_code}' --max-time 8 "${BASE_URL}/models" 2>/dev/null)"
HTTP_CODE="${HTTP_CODE:-000}"
if [ "$HTTP_CODE" = "200" ]; then
    RAW="$(cat "$BODY_FILE")"
else
    RAW=""
    echo "  Could not list models (HTTP ${HTTP_CODE} via proxy)." >&2
    case "$HTTP_CODE" in
        403) echo "  -> The proxy blocked host:1234. The shared proxy isn't running with --local-model." >&2
             echo "     Reset it: ./ai-sandbox --stop-proxy   then relaunch with --local-model." >&2 ;;
        000) echo "  -> No response from the proxy itself. Is the proxy up?" >&2 ;;
        502|503|504) echo "  -> Proxy reached, but LM Studio didn't answer on the host." >&2
             echo "     In LM Studio enable 'Serve on Local Network' (binds 0.0.0.0:1234) and load a model." >&2 ;;
        *)   echo "  -> Unexpected status; check the proxy logs (docker logs ai-sandbox-proxy)." >&2 ;;
    esac
fi
rm -f "$BODY_FILE"

RAW="$RAW" PI_DIR="$PI_DIR" BASE_URL="$BASE_URL" LMSTUDIO_MODEL="${LMSTUDIO_MODEL:-}" "$PY" - <<'PY'
import json, os

raw = os.environ.get("RAW", "")
override = os.environ.get("LMSTUDIO_MODEL", "").strip()
pi_dir = os.environ["PI_DIR"]
base = os.environ["BASE_URL"]

try:
    ids = [m["id"] for m in json.loads(raw).get("data", []) if m.get("id")]
except Exception:
    ids = []

if override:                       # pin the requested id first, keep the rest
    ids = [override] + [i for i in ids if i != override]
if not ids:
    ids = [override] if override else ["local-model"]
    print("WARNING: no models discovered from LM Studio; using fallback '%s'." % ids[0])
    print("         Is LM Studio running and 'Serve on Local Network' (0.0.0.0) enabled?")

with open(os.path.join(pi_dir, "models.json"), "w") as f:
    json.dump({"providers": {"lmstudio": {
        "baseUrl": base,
        "api": "openai-completions",
        "apiKey": "lm-studio",
        "models": [{"id": i} for i in ids],
    }}}, f, indent=2)

settings_path = os.path.join(pi_dir, "settings.json")
try:
    with open(settings_path) as f:
        settings = json.load(f)
except Exception:
    settings = {}
settings["model"] = "lmstudio/%s" % ids[0]
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("Local model ready: provider 'lmstudio' with %d model(s) [%s]." % (len(ids), ", ".join(ids)))
print("Active model: %s" % settings["model"])
PY
