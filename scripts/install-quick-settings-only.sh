#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
GNOME_SHELL_MAJOR=$(sh scripts/check-gnome-version.sh)
echo "GNOME Shell $GNOME_SHELL_MAJOR compatibility: OK (supported: 49, 50, 51)"
EXT_DIR="/usr/share/gnome-shell/extensions/wproxy@wrench.local"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO=sudo; fi
TARGET_USER=${SUDO_USER:-$(id -un)}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_GID=$(id -g "$TARGET_USER")
if command -v node >/dev/null 2>&1; then
    node --input-type=module --check < gnome-extension/wproxy@wrench.local/extension.js
fi
$SUDO mkdir -p "$EXT_DIR"
for name in metadata.json extension.js stylesheet.css; do
    $SUDO install -m644 "gnome-extension/wproxy@wrench.local/$name" "$EXT_DIR/$name"
done
USER_EXT="$TARGET_HOME/.local/share/gnome-shell/extensions/wproxy@wrench.local"
if [ -d "$USER_EXT" ]; then
    for name in metadata.json extension.js stylesheet.css; do
        $SUDO install -m644 -o "$TARGET_UID" -g "$TARGET_GID" \
            "gnome-extension/wproxy@wrench.local/$name" "$USER_EXT/$name"
    done
fi
for name in metadata.json extension.js stylesheet.css; do
    cmp "gnome-extension/wproxy@wrench.local/$name" "$EXT_DIR/$name" >/dev/null || {
        echo "Installation failed: GNOME extension file mismatch: $name" >&2
        exit 5
    }
done
if command -v gnome-extensions >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
        runuser -u "$TARGET_USER" -- env \
            XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
            gnome-extensions disable wproxy@wrench.local >/dev/null 2>&1 || true
        runuser -u "$TARGET_USER" -- env \
            XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
            gnome-extensions enable wproxy@wrench.local >/dev/null 2>&1 || true
    else
        gnome-extensions disable wproxy@wrench.local >/dev/null 2>&1 || true
        gnome-extensions enable wproxy@wrench.local >/dev/null 2>&1 || true
    fi
fi
echo "WProxy Quick Settings 2.3.1 installed and verified for GNOME Shell $GNOME_SHELL_MAJOR."
echo "Log out/in once if GNOME Shell does not reload the extension immediately."
