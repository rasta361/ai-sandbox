#!/bin/bash
# Auto-detect and activate nearest virtual environment for pip

find_venv() {
    local dir="$PWD"
    local project_root="/home/devuser/project"

    # Search from current directory up to project root for user venvs
    while [[ "$dir" == "$project_root"* ]]; do
        for venv_name in .venv venv .virtualenv env; do
            if [ -f "$dir/$venv_name/bin/pip" ]; then
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
    if [ -f "/home/devuser/.venv_sandbox/bin/pip" ]; then
        echo "/home/devuser/.venv_sandbox"
        return 0
    fi

    return 1
}

# Try to find and use venv
if VENV_PATH=$(find_venv); then
    export VIRTUAL_ENV="$VENV_PATH"
    exec "$VENV_PATH/bin/pip" "$@"
else
    # No venv found - provide helpful error
    echo "Error: No virtual environment found." >&2
    echo "" >&2
    echo "Create one with:" >&2
    echo "  python3 -m venv .venv" >&2
    echo "" >&2
    echo "Then try again." >&2
    exit 1
fi
