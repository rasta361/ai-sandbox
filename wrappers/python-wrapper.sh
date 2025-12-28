#!/bin/bash
# Auto-detect and activate nearest virtual environment

find_venv() {
    local dir="$PWD"
    local project_root="/home/devuser/project"

    # Search from current directory up to project root for user venvs
    while [[ "$dir" == "$project_root"* ]]; do
        for venv_name in .venv venv .virtualenv env; do
            # Only use venv if it has both python3 AND pip (complete venv)
            if [ -f "$dir/$venv_name/bin/python3" ] && [ -f "$dir/$venv_name/bin/pip" ]; then
                echo "$dir/$venv_name"
                return 0
            fi
        done

        # Stop at project root
        if [ "$dir" = "$project_root" ]; then
            break
        fi

        dir=$(dirname "$dir")
    done

    # Fall back to sandbox venv (in named volume)
    if [ -f "/home/devuser/.venv_sandbox/bin/python3" ]; then
        echo "/home/devuser/.venv_sandbox"
        return 0
    fi

    return 1
}

# Try to find and use venv
if VENV_PATH=$(find_venv); then
    export VIRTUAL_ENV="$VENV_PATH"
    exec "$VENV_PATH/bin/python3" "$@"
else
    # No venv found - use system Python
    exec /opt/system-python/bin/python3 "$@"
fi
