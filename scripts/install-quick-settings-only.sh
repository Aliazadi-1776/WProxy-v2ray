#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
EXT_DIR="/usr/share/gnome-shell/extensions/wproxy@wrench.local"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO=sudo; fi
$SUDO mkdir -p "$EXT_DIR"
$SUDO install -m644 gnome-extension/wproxy@wrench.local/metadata.json "$EXT_DIR/metadata.json"
$SUDO install -m644 gnome-extension/wproxy@wrench.local/extension.js "$EXT_DIR/extension.js"
$SUDO install -m644 gnome-extension/wproxy@wrench.local/stylesheet.css "$EXT_DIR/stylesheet.css"
if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions disable wproxy@wrench.local >/dev/null 2>&1 || true
    gnome-extensions enable wproxy@wrench.local >/dev/null 2>&1 || true
fi
echo "WProxy Quick Settings 2.3.0 installed. Log out/in once if GNOME Shell does not reload the extension immediately."
