#!/bin/sh
set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else command -v sudo >/dev/null 2>&1 || { echo "sudo is required" >&2; exit 2; }; SUDO=sudo; fi

# No compilation: restore the CLI and manager immediately from source files.
$SUDO install -Dm755 cli/wproxyctl.py /usr/bin/wproxyctl
$SUDO install -Dm755 manager/wproxy-manager.py /usr/bin/wproxy-manager

# Restore the runner too if NetworkManager service already exists.
LIBEXEC="$(pkg-config --variable=libexecdir NetworkManager 2>/dev/null || true)"
[ -n "$LIBEXEC" ] || LIBEXEC=/usr/libexec
$SUDO install -Dm755 service/wproxy-xray-runner "$LIBEXEC/wproxy-xray-runner"

/usr/bin/wproxyctl --version
pkill -f '^/usr/bin/wproxy-manager$' >/dev/null 2>&1 || true

echo "WProxy CLI/runtime restored. Start it again with: wproxy-manager"
