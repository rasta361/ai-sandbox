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
exec /opt/real-bin/git "$@"
