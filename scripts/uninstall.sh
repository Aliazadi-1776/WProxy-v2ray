#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

LIBDIR="$(pkg-config --variable=libdir libnm 2>/dev/null || echo /usr/lib)"
LIBEXEC="$(pkg-config --variable=libexecdir NetworkManager 2>/dev/null || echo /usr/libexec)"
[ -n "$LIBEXEC" ] || LIBEXEC=/usr/libexec
TARGET_USER=${SUDO_USER:-$(id -un)}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
case "$TARGET_HOME" in ''|/) echo 'Could not resolve the desktop home directory.' >&2; exit 2 ;; esac

if command -v wproxyctl >/dev/null 2>&1; then
    $SUDO wproxyctl nm down >/dev/null 2>&1 || true
fi

if [ -x "$LIBEXEC/wproxy-xray-runner" ]; then
    $SUDO "$LIBEXEC/wproxy-xray-runner" stop || true
fi
$SUDO pkill -TERM -x wproxy-service 2>/dev/null || true

if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions disable wproxy@wrench.local >/dev/null 2>&1 || true
fi

for VPN_DIR in "$LIBDIR/NetworkManager/VPN" "/usr/lib/NetworkManager/VPN"; do
    [ -f "$VPN_DIR/nm-wproxy-service.name" ] && $SUDO rm -f "$VPN_DIR/nm-wproxy-service.name"
done

$SUDO rm -f \
    "$LIBDIR/NetworkManager/libnm-vpn-plugin-wproxy.so" \
    "$LIBDIR/NetworkManager/libnm-vpn-plugin-wproxy-editor.so" \
    "$LIBDIR/NetworkManager/libnm-gtk4-vpn-plugin-wproxy-editor.so" \
    "$LIBEXEC/wproxy-service" \
    "$LIBEXEC/wproxy-xray-runner" \
    /etc/dbus-1/system.d/org.freedesktop.NetworkManager.wproxy.conf \
    /etc/NetworkManager/conf.d/90-wproxy-unmanaged.conf \
    /usr/bin/wproxyctl \
    /usr/bin/wproxy-manager \
    /usr/share/applications/wproxy-manager.desktop \
    /usr/share/icons/hicolor/scalable/apps/wproxy.svg
$SUDO rm -rf /usr/share/gnome-shell/extensions/wproxy@wrench.local

# Remove known user-local overrides too, but leave the user's settings/store.
if [ "$TARGET_USER" != root ]; then
    USER_EXT="$TARGET_HOME/.local/share/gnome-shell/extensions/wproxy@wrench.local"
    for name in extension.js metadata.json stylesheet.css; do
        $SUDO rm -f "$USER_EXT/$name"
    done
    $SUDO rmdir "$USER_EXT" 2>/dev/null || true
    $SUDO rm -f "$TARGET_HOME/.local/bin/wproxyctl"
fi

$SUDO find /etc/NetworkManager/system-connections -maxdepth 1 -type f -name 'wproxy-*.nmconnection' -delete 2>/dev/null || true
$SUDO rm -rf /run/wproxy

$SUDO nmcli general reload >/dev/null 2>&1 || true
$SUDO nmcli connection reload >/dev/null 2>&1 || true
$SUDO busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true

echo "WProxy program files and NetworkManager profiles removed."
echo "Your saved node/subscription store under ~/.config/wproxy was intentionally kept."
echo "Xray itself was not removed."
echo 'If installed, remove the Plasma widget separately with scripts/uninstall-kde-widget.sh (without sudo).'
