#!/bin/bash
# Auto-detect and activate nearest virtual environment for pip

find_venv() {
    local dir="$PWD"
    local project_root="/home/devuser/project"

    # Search from current directory up to project root
    while [[ "$dir" == "$project_root"* ]]; do
        # Prioritize sandbox venv, then check user venvs
        for venv_name in .venv_claude_sandbox .venv venv .virtualenv env; do
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
