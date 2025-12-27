#!/bin/bash
COMMAND="$1"

# Explicitly block dangerous commands first (defense in depth)
case "$COMMAND" in
    api)
        echo "BLOCKED: 'gh api' is not allowed in this sandbox."
        echo "Direct API access could bypass security restrictions."
        exit 1
        ;;
    secret|variable)
        echo "BLOCKED: 'gh $COMMAND' is not allowed in this sandbox."
        echo "Secret and variable management requires human approval."
        exit 1
        ;;
    workflow)
        echo "BLOCKED: 'gh workflow' is not allowed in this sandbox."
        echo "Workflow management requires human approval."
        exit 1
        ;;
    codespace)
        echo "BLOCKED: 'gh codespace' is not allowed in this sandbox."
        echo "Codespace management requires human approval."
        exit 1
        ;;
    extension)
        echo "BLOCKED: 'gh extension' is not allowed in this sandbox."
        echo "Extension management requires human approval."
        exit 1
        ;;
    gist)
        echo "BLOCKED: 'gh gist' is not allowed in this sandbox."
        echo "Gist operations could be used for data exfiltration."
        exit 1
        ;;
    issue)
        # All issue operations allowed
        exec /opt/real-bin/gh "$@"
        ;;
    pr)
        if [[ "$2" == "create" || "$2" == "view" || "$2" == "list" || "$2" == "status" || "$2" == "diff" || "$2" == "checks" ]]; then
            exec /opt/real-bin/gh "$@"
        else
            echo "BLOCKED: 'gh pr $2' is not allowed in this sandbox."
            echo "You can create PRs with 'gh pr create', but other PR operations require human approval."
            exit 1
        fi
        ;;
    auth)
        if [[ "$2" == "login" || "$2" == "status" ]]; then
            exec /opt/real-bin/gh "$@"
        else
            echo "BLOCKED: 'gh auth $2' is not allowed in this sandbox."
            echo "Only 'gh auth login' and 'gh auth status' are permitted."
            exit 1
        fi
        ;;
    *)
        echo "BLOCKED: 'gh $COMMAND' is not allowed in this sandbox."
        echo "Allowed commands: 'gh issue *', 'gh pr create/view/list/status/diff/checks', 'gh auth login/status'"
        exit 1
        ;;
esac
