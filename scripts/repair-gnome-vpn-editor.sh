#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    command -v sudo >/dev/null 2>&1 || { echo "sudo is required" >&2; exit 2; }
    SUDO="sudo"
fi

command -v pkg-config >/dev/null 2>&1 || { echo "pkg-config is required" >&2; exit 2; }
pkg-config --exists gio-2.0 glib-2.0 gmodule-2.0 libnm gtk+-3.0 gtk4 || {
    echo "Missing libnm/GTK3/GTK4 build dependencies. Run scripts/install.sh instead." >&2
    exit 2
}

LIBDIR="$(pkg-config --variable=libdir libnm 2>/dev/null || true)"
[ -n "$LIBDIR" ] || LIBDIR=/usr/lib
if [ -d "$LIBDIR/NetworkManager/VPN" ]; then
    NM_VPN_DIR="$LIBDIR/NetworkManager/VPN"
elif [ -d /usr/lib/NetworkManager/VPN ]; then
    NM_VPN_DIR=/usr/lib/NetworkManager/VPN
else
    NM_VPN_DIR="$LIBDIR/NetworkManager/VPN"
fi
NM_PLUGIN_DIR="$LIBDIR/NetworkManager"
LIBEXEC="$(pkg-config --variable=libexecdir NetworkManager 2>/dev/null || true)"
[ -n "$LIBEXEC" ] || LIBEXEC=/usr/libexec

make clean
make LIBDIR="$LIBDIR" LIBEXECDIR="$LIBEXEC" NM_PLUGIN_DIR="$NM_PLUGIN_DIR"
./validate-plugin ./libnm-vpn-plugin-wproxy.so

$SUDO mkdir -p "$NM_PLUGIN_DIR" "$NM_VPN_DIR" "$LIBEXEC" /etc/NetworkManager/conf.d

# Repair the complete local runtime, not only the GNOME editor.
$SUDO install -Dm755 wproxyctl /usr/bin/wproxyctl
$SUDO install -Dm755 manager/wproxy-manager.py /usr/bin/wproxy-manager
$SUDO install -Dm755 wproxy-service "$LIBEXEC/wproxy-service"
$SUDO install -Dm755 service/wproxy-xray-runner "$LIBEXEC/wproxy-xray-runner"
$SUDO install -Dm755 libnm-vpn-plugin-wproxy.so "$NM_PLUGIN_DIR/libnm-vpn-plugin-wproxy.so"
$SUDO install -Dm755 libnm-vpn-plugin-wproxy-editor.so "$NM_PLUGIN_DIR/libnm-vpn-plugin-wproxy-editor.so"
$SUDO install -Dm755 libnm-gtk4-vpn-plugin-wproxy-editor.so "$NM_PLUGIN_DIR/libnm-gtk4-vpn-plugin-wproxy-editor.so"
$SUDO install -Dm644 data/org.freedesktop.NetworkManager.wproxy.conf /etc/dbus-1/system.d/org.freedesktop.NetworkManager.wproxy.conf
$SUDO install -Dm644 data/wproxy-manager.desktop /usr/share/applications/wproxy-manager.desktop
$SUDO install -Dm644 icons/wproxy.svg /usr/share/icons/hicolor/scalable/apps/wproxy.svg

sed \
    -e "s|@LIBEXECDIR@|$LIBEXEC|g" \
    -e "s|@NM_PLUGIN_DIR@|$NM_PLUGIN_DIR|g" \
    data/nm-wproxy-service.name.in | $SUDO tee "$NM_VPN_DIR/nm-wproxy-service.name" >/dev/null
$SUDO chmod 644 "$NM_VPN_DIR/nm-wproxy-service.name"

cat > /tmp/90-wproxy-unmanaged.conf <<'CONF'
[keyfile]
unmanaged-devices=interface-name:wproxy0
CONF
$SUDO install -Dm644 /tmp/90-wproxy-unmanaged.conf /etc/NetworkManager/conf.d/90-wproxy-unmanaged.conf
rm -f /tmp/90-wproxy-unmanaged.conf

# Verify the exact executable used by the manager/extension/runner.
[ -x /usr/bin/wproxyctl ] || { echo "Repair failed: /usr/bin/wproxyctl is still missing." >&2; exit 5; }
/usr/bin/wproxyctl --version

$SUDO busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
$SUDO systemctl restart NetworkManager
nmcli connection reload >/dev/null 2>&1 || true
pkill -x gnome-control-center >/dev/null 2>&1 || true
pkill -f '^/usr/bin/wproxy-manager$' >/dev/null 2>&1 || true

echo "WProxy runtime + GNOME VPN editor repaired."
if ! command -v xray >/dev/null 2>&1 && [ ! -x /usr/local/bin/xray ] && [ ! -x /usr/bin/xray ]; then
    echo "WARNING: Xray is still missing. Run scripts/install.sh before trying to connect." >&2
fi
echo "Re-open WProxy Manager and Settings > Network > VPN."
