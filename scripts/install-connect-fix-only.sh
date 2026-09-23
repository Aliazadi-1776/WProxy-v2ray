#!/usr/bin/env bash
set -euo pipefail
# The gateway handshake requires matching service, runner and CLI versions.
exec bash "$(dirname -- "$0")/apply-fix.sh" "$@"
