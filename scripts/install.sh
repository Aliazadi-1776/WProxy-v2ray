#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"

DESKTOP=auto
while [ "$#" -gt 0 ]; do
    case "$1" in
        --desktop)
            [ "$#" -ge 2 ] || { echo 'Missing desktop: gnome, kde, none, or auto' >&2; exit 2; }
            DESKTOP=$2; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
if [ "$DESKTOP" = auto ]; then
    case "${XDG_CURRENT_DESKTOP:-}:${DESKTOP_SESSION:-}" in
        *KDE*|*kde*|*plasma*|*Plasma*) DESKTOP=kde ;;
        *GNOME*|*gnome*|*ubuntu*) DESKTOP=gnome ;;
        *) DESKTOP=none ;;
    esac
fi
case "$DESKTOP" in gnome|kde|none) ;; *) echo 'Invalid desktop selection.' >&2; exit 2 ;; esac
TARGET_USER=${SUDO_USER:-$(id -un)}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_GID=$(id -g "$TARGET_USER")
if [ "$TARGET_USER" = root ] && [ "$DESKTOP" != none ]; then
    echo 'Run from your regular desktop account (or with sudo), not a root login.' >&2
    exit 2
fi

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    command -v sudo >/dev/null 2>&1 || { echo "sudo is required" >&2; exit 2; }
    SUDO="sudo"
fi

have_build_deps() {
    command -v pkg-config >/dev/null 2>&1 &&
    pkg-config --exists gio-2.0 glib-2.0 gmodule-2.0 libnm gtk+-3.0 gtk4
}

install_deps_if_needed() {
    if have_build_deps && command -v python3 >/dev/null 2>&1 && command -v nmcli >/dev/null 2>&1; then
        return 0
    fi

    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing WProxy build/runtime dependencies (Debian/Ubuntu)..."
        $SUDO apt-get update
        $SUDO apt-get install -y \
            build-essential pkg-config libglib2.0-dev libgtk-3-dev libgtk-4-dev libnm-dev \
            network-manager python3 python3-gi gir1.2-gtk-4.0 curl ca-certificates iproute2
        return 0
    fi

    echo "Missing build dependencies. Install libnm development files, GTK3/GTK4 development files, pkg-config, Python 3 and NetworkManager, then re-run." >&2
    exit 2
}

find_xray() {
    for candidate in /usr/local/bin/xray /usr/bin/xray /opt/xray/xray; do
        [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done
    command -v xray 2>/dev/null || return 1
}

install_xray_if_needed() {
    if XRAY_PATH=$(find_xray 2>/dev/null); then
        echo "Xray already installed: $XRAY_PATH"
        "$XRAY_PATH" version 2>/dev/null | head -n 1 || true
        return 0
    fi

    command -v curl >/dev/null 2>&1 || {
        echo "curl is required to install Xray." >&2
        exit 2
    }
    command -v bash >/dev/null 2>&1 || {
        echo "bash is required to install Xray." >&2
        exit 2
    }

    echo "Xray is missing. Installing the official XTLS Xray-core release..."
    TMP_SCRIPT=$(mktemp)
    trap 'rm -f "$TMP_SCRIPT"' EXIT INT TERM
    curl -fL --retry 3 --connect-timeout 15 \
        https://github.com/XTLS/Xray-install/raw/main/install-release.sh \
        -o "$TMP_SCRIPT"
    $SUDO bash "$TMP_SCRIPT" install
    rm -f "$TMP_SCRIPT"
    trap - EXIT INT TERM

    # WProxy launches Xray itself. Do not leave the generic system service competing for the tunnel.
    $SUDO systemctl disable --now xray.service >/dev/null 2>&1 || true

    XRAY_PATH=$(find_xray 2>/dev/null || true)
    [ -n "$XRAY_PATH" ] || { echo "Xray installation finished but no xray binary was found." >&2; exit 3; }
    echo "Installed Xray: $XRAY_PATH"
    "$XRAY_PATH" version 2>/dev/null | head -n 1 || true
}

install_deps_if_needed
install_xray_if_needed

if [ "$DESKTOP" = kde ] && ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo 'Plasma 6 / kpackagetool6 is required. Install a Plasma 6 desktop first.' >&2
    exit 2
fi
if [ "$DESKTOP" = kde ] && command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get install -y qml6-module-org-kde-plasma-plasma5support
fi

command -v pkg-config >/dev/null 2>&1 || { echo "pkg-config is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }
command -v nmcli >/dev/null 2>&1 || { echo "NetworkManager/nmcli is required" >&2; exit 2; }

LIBDIR="$(pkg-config --variable=libdir libnm 2>/dev/null || true)"
[ -n "$LIBDIR" ] || LIBDIR=/usr/lib
LIBEXEC="$(pkg-config --variable=libexecdir NetworkManager 2>/dev/null || true)"
[ -n "$LIBEXEC" ] || LIBEXEC=/usr/libexec

if [ -d "$LIBDIR/NetworkManager/VPN" ]; then
    NM_VPN_DIR="$LIBDIR/NetworkManager/VPN"
elif [ -d "/usr/lib/NetworkManager/VPN" ]; then
    NM_VPN_DIR="/usr/lib/NetworkManager/VPN"
else
    NM_VPN_DIR="$LIBDIR/NetworkManager/VPN"
fi

NM_PLUGIN_DIR="$LIBDIR/NetworkManager"
EXT_DIR="/usr/share/gnome-shell/extensions/wproxy@wrench.local"
NM_CONF="/etc/NetworkManager/conf.d/90-wproxy-unmanaged.conf"
BACKUP="/var/backups/wproxy-$(date +%Y%m%d-%H%M%S)"

printf '%s\n' \
    "WProxy 2.3.1 installer" \
    "  libdir:       $LIBDIR" \
    "  libexec:      $LIBEXEC" \
    "  VPN metadata: $NM_VPN_DIR" \
    "  libnm plugin: $NM_PLUGIN_DIR" \
    "  GNOME ext:    $EXT_DIR"
echo "  desktop:      $DESKTOP"

echo
echo "Checking sources and dependencies..."
make check-deps
make check-python

echo
echo "Building NetworkManager service + GTK3/GTK4 editors..."
make clean
make LIBDIR="$LIBDIR" LIBEXECDIR="$LIBEXEC" NM_PLUGIN_DIR="$NM_PLUGIN_DIR"

echo
echo "Validating GTK-neutral libnm loader..."
./validate-plugin ./libnm-vpn-plugin-wproxy.so

echo
echo "Creating backup: $BACKUP"
$SUDO mkdir -p "$BACKUP"
$SUDO chmod 700 "$BACKUP"
backup_file() {
    f="$1"
    if [ -e "$f" ]; then
        safe_name=$(printf '%s' "$f" | tr '/' '_')
        $SUDO cp -a "$f" "$BACKUP/${safe_name}.bak"
    fi
}

NAME_FILE="$NM_VPN_DIR/nm-wproxy-service.name"
PLUGIN_FILE="$NM_PLUGIN_DIR/libnm-vpn-plugin-wproxy.so"
GTK3_EDITOR_FILE="$NM_PLUGIN_DIR/libnm-vpn-plugin-wproxy-editor.so"
GTK4_EDITOR_FILE="$NM_PLUGIN_DIR/libnm-gtk4-vpn-plugin-wproxy-editor.so"
SERVICE_FILE="$LIBEXEC/wproxy-service"
RUNNER_FILE="$LIBEXEC/wproxy-xray-runner"
DBUS_FILE="/etc/dbus-1/system.d/org.freedesktop.NetworkManager.wproxy.conf"

for f in "$NAME_FILE" "$PLUGIN_FILE" "$GTK3_EDITOR_FILE" "$GTK4_EDITOR_FILE" \
         "$SERVICE_FILE" "$RUNNER_FILE" "$DBUS_FILE" "$NM_CONF" \
         /usr/bin/wproxyctl /usr/bin/wproxy-manager \
         /usr/share/applications/wproxy-manager.desktop \
         /usr/share/icons/hicolor/scalable/apps/wproxy.svg "$EXT_DIR"; do
    backup_file "$f"
done

if [ "$DESKTOP" = gnome ] && [ -d "$TARGET_HOME/.local/share/gnome-shell/extensions/wproxy@wrench.local" ]; then
    backup_file "$TARGET_HOME/.local/share/gnome-shell/extensions/wproxy@wrench.local"
fi
if [ -f "$TARGET_HOME/.local/bin/wproxyctl" ]; then
    backup_file "$TARGET_HOME/.local/bin/wproxyctl"
fi

# Stop only this VPN before replacing its executable. Do not restart all of
# NetworkManager: that interrupts Wi-Fi and can retain the old VPN process.
if [ -x /usr/bin/wproxyctl ]; then $SUDO /usr/bin/wproxyctl nm down || true; fi
if [ -x "$RUNNER_FILE" ]; then $SUDO "$RUNNER_FILE" stop || true; fi
$SUDO pkill -TERM -x wproxy-service 2>/dev/null || true
attempt=0
while pgrep -x wproxy-service >/dev/null 2>&1 && [ "$attempt" -lt 50 ]; do
    sleep 0.1
    attempt=$((attempt + 1))
done
if pgrep -x wproxy-service >/dev/null 2>&1; then
    echo 'Old WProxy service did not stop. No program files replaced.' >&2
    exit 3
fi

# The 2.0 build put a GTK3-linked library directly in the generic plugin slot.
# Replace it atomically with the GTK-neutral loader and separate GTK3/GTK4 editors.
echo "Installing runtime and desktop integration..."
$SUDO mkdir -p "$LIBEXEC" "$NM_VPN_DIR" "$NM_PLUGIN_DIR" /etc/NetworkManager/conf.d
$SUDO install -Dm755 wproxy-service "$SERVICE_FILE"
$SUDO install -Dm755 service/wproxy-xray-runner "$RUNNER_FILE"
$SUDO install -Dm755 libnm-vpn-plugin-wproxy.so "$PLUGIN_FILE"
$SUDO install -Dm755 libnm-vpn-plugin-wproxy-editor.so "$GTK3_EDITOR_FILE"
$SUDO install -Dm755 libnm-gtk4-vpn-plugin-wproxy-editor.so "$GTK4_EDITOR_FILE"
$SUDO install -Dm755 wproxyctl /usr/bin/wproxyctl
if [ -f "$TARGET_HOME/.local/bin/wproxyctl" ]; then
    $SUDO install -m755 -o "$TARGET_UID" -g "$TARGET_GID" wproxyctl "$TARGET_HOME/.local/bin/wproxyctl"
fi
$SUDO install -Dm755 manager/wproxy-manager.py /usr/bin/wproxy-manager
$SUDO install -Dm644 data/org.freedesktop.NetworkManager.wproxy.conf "$DBUS_FILE"
$SUDO install -Dm644 data/wproxy-manager.desktop /usr/share/applications/wproxy-manager.desktop
$SUDO install -Dm644 icons/wproxy.svg /usr/share/icons/hicolor/scalable/apps/wproxy.svg

$SUDO install -Dm644 data/90-wproxy-unmanaged.conf "$NM_CONF"

if [ "$DESKTOP" = gnome ]; then
    $SUDO mkdir -p "$EXT_DIR"
    for name in metadata.json extension.js stylesheet.css; do
        $SUDO install -m644 "gnome-extension/wproxy@wrench.local/$name" "$EXT_DIR/$name"
    done
    USER_EXT="$TARGET_HOME/.local/share/gnome-shell/extensions/wproxy@wrench.local"
    if [ -d "$USER_EXT" ]; then
        for name in metadata.json extension.js stylesheet.css; do
            $SUDO install -m644 -o "$TARGET_UID" -g "$TARGET_GID" "gnome-extension/wproxy@wrench.local/$name" "$USER_EXT/$name"
        done
    fi
fi

sed \
    -e "s|@LIBEXECDIR@|$LIBEXEC|g" \
    -e "s|@NM_PLUGIN_DIR@|$NM_PLUGIN_DIR|g" \
    data/nm-wproxy-service.name.in |
    $SUDO tee "$NAME_FILE" >/dev/null
$SUDO chmod 644 "$NAME_FILE"

$SUDO busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
$SUDO nmcli general reload
nmcli connection reload >/dev/null 2>&1 || true

if command -v gtk4-update-icon-cache >/dev/null 2>&1; then
    $SUDO gtk4-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
elif command -v gtk-update-icon-cache >/dev/null 2>&1; then
    $SUDO gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

if [ "$DESKTOP" = gnome ] && command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions enable wproxy@wrench.local >/dev/null 2>&1 || true
fi

if [ "$DESKTOP" = kde ]; then
    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" bash "$PROJECT_DIR/scripts/install-kde-widget.sh"
    else
        bash "$PROJECT_DIR/scripts/install-kde-widget.sh"
    fi
fi

echo
[ -x /usr/bin/wproxyctl ] || { echo "Installation failed: /usr/bin/wproxyctl was not installed." >&2; exit 5; }
/usr/bin/wproxyctl --version

echo "Installed WProxy 2.3.1."
XRAY_PATH=$(find_xray 2>/dev/null || true)
[ -n "$XRAY_PATH" ] && "$XRAY_PATH" version 2>/dev/null | head -n 1 || true
if [ "$DESKTOP" = gnome ]; then
    echo 'Close/reopen GNOME Settings. Log out/in to load the new Quick Settings extension.'
fi
echo "Diagnostics: $PROJECT_DIR/scripts/diagnose.sh"
echo "Backup: $BACKUP"
