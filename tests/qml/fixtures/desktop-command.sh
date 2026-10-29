#!/bin/sh
# Actual subprocess fixture for Plasma's executable engine; never calls nmcli or pkexec.
set -eu
case "${1:-}:${2:-}" in
    settings:show) printf '%s\n' '{"remember_authorization":true}' ;;
    status:--json) printf '%s\n' '{"active":false,"node_id":null,"name":null}' ;;
    node:list|sub:list) printf '%s\n' '[]' ;;
    sub:add) printf '%s\n' 'fixture-subscription' ;;
    sub:update) printf '%s\n' 'Subscription updated' ;;
    /usr/libexec/wproxy-admin:up-remember|/usr/libexec/wproxy-admin:up)
        if [ "${3:-}" = 0000000000000001 ]; then
            echo 'Authentication cancelled' >&2
            exit 126
        fi
        printf 'Helper %s %s pid=%s\n' "$2" "$3" "$$"
        ;;
    /usr/libexec/wproxy-admin:down) printf '%s\n' "Connection 'WProxy' successfully deactivated (D-Bus active path: /example/1)" ;;
    /usr/libexec/wproxy-admin:sync) printf '%s\n' 'Helper profiles synced' ;;
    *) echo 'Unsupported desktop fixture command' >&2; exit 64 ;;
esac
