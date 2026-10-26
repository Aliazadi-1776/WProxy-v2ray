#!/bin/sh
set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else command -v sudo >/dev/null 2>&1 || { echo "sudo is required" >&2; exit 2; }; SUDO=sudo; fi

# Rebuild the desktop shell so a repair cannot silently restore the retired GTK manager.
command -v node >/dev/null 2>&1 || { echo "node is required" >&2; exit 2; }
command -v npm >/dev/null 2>&1 || { echo "npm is required" >&2; exit 2; }
command -v cargo >/dev/null 2>&1 || { echo "cargo is required" >&2; exit 2; }
make desktop

$SUDO install -Dm755 cli/wproxyctl.py /usr/bin/wproxyctl
$SUDO install -Dm755 desktop/src-tauri/target/release/wproxy-desktop /usr/bin/wproxy-manager

# Restore the runner too if NetworkManager service already exists.
LIBEXEC="$(pkg-config --variable=libexecdir NetworkManager 2>/dev/null || true)"
[ -n "$LIBEXEC" ] || LIBEXEC=/usr/libexec
$SUDO install -Dm755 service/wproxy-xray-runner "$LIBEXEC/wproxy-xray-runner"

/usr/bin/wproxyctl --version
pkill -f '^/usr/bin/wproxy-manager$' >/dev/null 2>&1 || true

echo "WProxy CLI/Tauri runtime restored. Start it again with: wproxy-manager"
