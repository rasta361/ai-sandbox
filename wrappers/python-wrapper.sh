#!/bin/bash
# Auto-detect and activate nearest virtual environment

find_venv() {
    local dir="$PWD"
    local project_root="/home/devuser/project"

    # Search from current directory up to project root
    while [[ "$dir" == "$project_root"* ]]; do
        # Prioritize sandbox venv, then check user venvs
        for venv_name in .venv_claude_sandbox .venv venv .virtualenv env; do
            if [ -f "$dir/$venv_name/bin/python3" ]; then
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
