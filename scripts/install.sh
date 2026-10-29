#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"
MIN_XRAY_VERSION=26.9.30

DESKTOP=auto
DRY_RUN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --desktop)
            [ "$#" -ge 2 ] || { echo 'Missing desktop: gnome, kde, none, auto, or preserve' >&2; exit 2; }
            DESKTOP=$2; shift 2 ;;
        --dry-run)
            DRY_RUN=1; shift ;;
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
case "$DESKTOP" in gnome|kde|none|preserve) ;; *) echo 'Invalid desktop selection.' >&2; exit 2 ;; esac
TARGET_USER=${SUDO_USER:-$(id -un)}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_GID=$(id -g "$TARGET_USER")
select_desktop_integrations() {
    INSTALL_GNOME=0
    INSTALL_KDE=0
    case "$DESKTOP" in
        gnome) INSTALL_GNOME=1 ;;
        kde) INSTALL_KDE=1 ;;
        preserve)
            if [ -d /usr/share/gnome-shell/extensions/wproxy@wrench.local ] || \
               [ -d "$TARGET_HOME/.local/share/gnome-shell/extensions/wproxy@wrench.local" ]; then
                INSTALL_GNOME=1
            fi
            if [ -d "$TARGET_HOME/.local/share/plasma/plasmoids/org.wproxy.WProxy" ] || \
               [ -d /usr/share/plasma/plasmoids/org.wproxy.WProxy ]; then
                INSTALL_KDE=1
            fi
            for plugin in /usr/lib/qt6/plugins/plasma/network/vpn/plasmanetworkmanagement_wproxyui.so \
                          /usr/lib64/qt6/plugins/plasma/network/vpn/plasmanetworkmanagement_wproxyui.so \
                          /usr/lib/*/qt6/plugins/plasma/network/vpn/plasmanetworkmanagement_wproxyui.so; do
                [ ! -f "$plugin" ] || INSTALL_KDE=1
            done
            if [ "$INSTALL_GNOME" -eq 0 ] && [ "$INSTALL_KDE" -eq 0 ]; then DESKTOP=none; fi
            ;;
    esac
}
select_desktop_integrations
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
    pkg-config --exists gio-2.0 glib-2.0 gmodule-2.0 libnm gtk+-3.0 gtk4 webkit2gtk-4.1
}

install_deps_if_needed() {
    if have_build_deps && command -v python3 >/dev/null 2>&1 && command -v nmcli >/dev/null 2>&1 && \
       command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && \
       command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo 'Dry-run failed: build/runtime dependencies are missing; no packages were installed.' >&2
        exit 2
    fi

    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing WProxy build/runtime dependencies (Debian/Ubuntu)..."
        $SUDO apt-get update
        $SUDO apt-get install -y \
            build-essential pkg-config libglib2.0-dev libgtk-3-dev libgtk-4-dev libnm-dev \
            libwebkit2gtk-4.1-dev librsvg2-dev libssl-dev \
            network-manager python3 python3-gi gir1.2-gtk-4.0 curl ca-certificates iproute2 \
            nodejs npm cargo
        return 0
    fi

    echo "Missing build dependencies. Install libnm, GTK3/GTK4, WebKitGTK 4.1, Node.js, npm, Rust/Cargo, Python 3 and NetworkManager, then re-run." >&2
    exit 2
}

find_xray() {
    for candidate in /usr/local/bin/xray /usr/bin/xray /opt/xray/xray; do
        [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done
    command -v xray 2>/dev/null || return 1
}

xray_version() {
    "$1" version 2>/dev/null | sed -n '1s/^Xray \([0-9][0-9.]*\).*/\1/p'
}

version_at_least() {
    [ -n "$1" ] &&
    [ "$(printf '%s\n%s\n' "$MIN_XRAY_VERSION" "$1" | sort -V | head -n 1)" = "$MIN_XRAY_VERSION" ]
}

install_xray_if_needed() {
    if XRAY_PATH=$(find_xray 2>/dev/null); then
        INSTALLED_XRAY_VERSION=$(xray_version "$XRAY_PATH")
        if version_at_least "$INSTALLED_XRAY_VERSION"; then
            echo "Xray already installed: $XRAY_PATH"
            "$XRAY_PATH" version 2>/dev/null | head -n 1 || true
            return 0
        fi
        echo "Xray $INSTALLED_XRAY_VERSION is too old for reliable app routing; upgrading to $MIN_XRAY_VERSION..."
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Dry-run failed: Xray $MIN_XRAY_VERSION or newer is not installed; no download was attempted." >&2
        exit 2
    fi

    command -v curl >/dev/null 2>&1 || {
        echo "curl is required to install Xray." >&2
        exit 2
    }
    command -v bash >/dev/null 2>&1 || {
        echo "bash is required to install Xray." >&2
        exit 2
    }

    echo "Installing the verified official XTLS Xray-core $MIN_XRAY_VERSION release..."
    TMP_SCRIPT=$(mktemp)
    trap 'rm -f "$TMP_SCRIPT"' EXIT INT TERM
    curl -fL --retry 3 --connect-timeout 15 \
        https://github.com/XTLS/Xray-install/raw/main/install-release.sh \
        -o "$TMP_SCRIPT"
    $SUDO bash "$TMP_SCRIPT" install --version "v$MIN_XRAY_VERSION"
    rm -f "$TMP_SCRIPT"
    trap - EXIT INT TERM

    # WProxy launches Xray itself. Do not leave the generic system service competing for the tunnel.
    $SUDO systemctl disable --now xray.service >/dev/null 2>&1 || true

    XRAY_PATH=$(find_xray 2>/dev/null || true)
    [ -n "$XRAY_PATH" ] || { echo "Xray installation finished but no xray binary was found." >&2; exit 3; }
    INSTALLED_XRAY_VERSION=$(xray_version "$XRAY_PATH")
    version_at_least "$INSTALLED_XRAY_VERSION" || {
        echo "Xray $MIN_XRAY_VERSION or newer is required; found ${INSTALLED_XRAY_VERSION:-unknown}." >&2
        exit 3
    }
    echo "Installed Xray: $XRAY_PATH"
    "$XRAY_PATH" version 2>/dev/null | head -n 1 || true
}

install_deps_if_needed
install_xray_if_needed

install_kde_deps_if_needed() {
    [ "$INSTALL_KDE" -eq 1 ] || return 0
    if command -v cmake >/dev/null 2>&1 &&
       cmake -S plasma-nm -B build/plasma-nm -DCMAKE_INSTALL_PREFIX=/usr >/dev/null 2>&1; then
        return 0
    fi
    if [ "$DRY_RUN" -eq 0 ] && command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get install -y cmake extra-cmake-modules qt6-base-dev \
            libkf6coreaddons-dev libkf6networkmanagerqt-dev libkf6widgetsaddons-dev plasma-nm \
            kpackagetool6 qml6-module-org-kde-kirigami qml6-module-org-kde-plasma-plasma5support polkit-kde-agent-1
    elif [ "$DRY_RUN" -eq 0 ] && command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y cmake gcc-c++ extra-cmake-modules qt6-qtbase-devel \
            kf6-kcoreaddons-devel kf6-networkmanager-qt-devel kf6-kwidgetsaddons-devel plasma-nm \
            kf6-kpackage kf6-kirigami plasma5support polkit-kde
    else
        echo 'KDE integration needs CMake, ECM, Qt6 base and KF6 CoreAddons/NetworkManagerQt/WidgetsAddons development packages, plus plasma-nm. See the KDE-only dependency command in README.md.' >&2
        if command -v pacman >/dev/null 2>&1; then
            echo 'On Arch, update the system first and install: cmake extra-cmake-modules qt6-base kcoreaddons networkmanager-qt kwidgetsaddons plasma-nm kpackage kirigami plasma5support polkit-kde-agent' >&2
        fi
        exit 2
    fi
    cmake -S plasma-nm -B build/plasma-nm -DCMAKE_INSTALL_PREFIX=/usr
}
install_kde_deps_if_needed

if [ "$INSTALL_KDE" -eq 1 ] && ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo 'Plasma 6 / kpackagetool6 is required. Install a Plasma 6 desktop first.' >&2
    exit 2
fi
if [ "$INSTALL_KDE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ] && command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get install -y qml6-module-org-kde-plasma-plasma5support
fi

command -v pkg-config >/dev/null 2>&1 || { echo "pkg-config is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }
command -v nmcli >/dev/null 2>&1 || { echo "NetworkManager/nmcli is required" >&2; exit 2; }
command -v systemd-run >/dev/null 2>&1 || { echo "systemd-run is required for application routing" >&2; exit 2; }
command -v systemctl >/dev/null 2>&1 || { echo "systemctl is required for application routing" >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "Node.js is required to build the Tauri desktop" >&2; exit 2; }
command -v npm >/dev/null 2>&1 || { echo "npm is required to build the Tauri desktop" >&2; exit 2; }
command -v cargo >/dev/null 2>&1 || { echo "Rust/Cargo is required to build the Tauri desktop" >&2; exit 2; }
command -v rustc >/dev/null 2>&1 || { echo "rustc is required to build the Tauri desktop" >&2; exit 2; }
NODE_VERSION=$(node -p 'process.versions.node')
[ "$(printf '%s\n%s\n' 20.19.0 "$NODE_VERSION" | sort -V | head -n 1)" = 20.19.0 ] || {
    echo "Node.js 20.19 or newer is required for the Tauri frontend; found $NODE_VERSION." >&2
    exit 2
}
RUST_VERSION=$(rustc --version | awk '{print $2}')
[ "$(printf '%s\n%s\n' 1.90.0 "$RUST_VERSION" | sort -V | head -n 1)" = 1.90.0 ] || {
    echo "Rust 1.90 or newer is required for the Tauri desktop; found $RUST_VERSION." >&2
    exit 2
}

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
NAME_FILE="$NM_VPN_DIR/nm-wproxy-service.name"
PLUGIN_FILE="$NM_PLUGIN_DIR/libnm-vpn-plugin-wproxy.so"
GTK3_EDITOR_FILE="$NM_PLUGIN_DIR/libnm-vpn-plugin-wproxy-editor.so"
GTK4_EDITOR_FILE="$NM_PLUGIN_DIR/libnm-gtk4-vpn-plugin-wproxy-editor.so"
SERVICE_FILE="$LIBEXEC/wproxy-service"
RUNNER_FILE="$LIBEXEC/wproxy-xray-runner"
DBUS_FILE="/etc/dbus-1/system.d/org.freedesktop.NetworkManager.wproxy.conf"
ADMIN_HELPER="/usr/libexec/wproxy-admin"
POLKIT_POLICY="/usr/share/polkit-1/actions/io.github.aliazadi1776.wproxy.policy"
PLASMA_PLUGIN_FILE=

printf '%s\n' \
    "WProxy 2.7.5 installer" \
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
echo "Building lightweight Tauri desktop..."
make desktop
DESKTOP_BINARY="$PROJECT_DIR/desktop/src-tauri/target/release/wproxy-desktop"
[ -x "$DESKTOP_BINARY" ] || { echo 'Tauri desktop build did not produce an executable.' >&2; exit 3; }

echo
echo "Validating GTK-neutral libnm loader..."
./validate-plugin ./libnm-vpn-plugin-wproxy.so

if [ "$INSTALL_KDE" -eq 1 ]; then
    echo 'Building and validating native Plasma VPN integration...'
    command -v cmake >/dev/null 2>&1 || {
        echo 'KDE integration needs CMake, ECM, Qt6 base and KF6 CoreAddons/NetworkManagerQt/WidgetsAddons development packages, plus plasma-nm.' >&2
        exit 2
    }
    make plasma-plugin
    PLASMA_PLUGIN_FILE=$(cat build/plasma-nm/installed-plugin-path)
    case "$PLASMA_PLUGIN_FILE" in /*/plasma/network/vpn/plasmanetworkmanagement_wproxyui.so) ;;
        *) echo 'Invalid native Plasma VPN plugin installation path.' >&2; exit 3 ;;
    esac
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' \
        '' \
        'WProxy installer dry-run: PASS' \
        "  desktop:      $DESKTOP" \
        "  target user:  $TARGET_USER" \
        "  service:      $SERVICE_FILE" \
        "  runner:       $RUNNER_FILE" \
        "  admin helper: $ADMIN_HELPER" \
        "  policy:       $POLKIT_POLICY" \
        "  manager:      /usr/bin/wproxy-manager" \
        'No system files, NetworkManager profiles, packages, or desktop extensions were changed.'
    exit 0
fi

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

for f in "$NAME_FILE" "$PLUGIN_FILE" "$GTK3_EDITOR_FILE" "$GTK4_EDITOR_FILE" \
         "$SERVICE_FILE" "$RUNNER_FILE" "$DBUS_FILE" "$NM_CONF" \
         "$ADMIN_HELPER" "$POLKIT_POLICY" \
         "$PLASMA_PLUGIN_FILE" \
         /usr/bin/wproxyctl /usr/bin/wproxy-manager \
         /usr/share/applications/wproxy-manager.desktop \
         /usr/share/icons/hicolor/scalable/apps/wproxy.svg "$EXT_DIR"; do
    backup_file "$f"
done

if [ "$INSTALL_GNOME" -eq 1 ] && [ -d "$TARGET_HOME/.local/share/gnome-shell/extensions/wproxy@wrench.local" ]; then
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
$SUDO mkdir -p "$LIBEXEC" "$NM_VPN_DIR" "$NM_PLUGIN_DIR" /etc/NetworkManager/conf.d \
    /usr/libexec /usr/share/polkit-1/actions
$SUDO install -Dm755 wproxy-service "$SERVICE_FILE"
$SUDO install -Dm755 service/wproxy-xray-runner "$RUNNER_FILE"
$SUDO install -Dm755 scripts/wproxy-admin "$ADMIN_HELPER"
$SUDO install -Dm644 data/io.github.aliazadi1776.wproxy.policy "$POLKIT_POLICY"
$SUDO install -Dm755 libnm-vpn-plugin-wproxy.so "$PLUGIN_FILE"
$SUDO install -Dm755 libnm-vpn-plugin-wproxy-editor.so "$GTK3_EDITOR_FILE"
$SUDO install -Dm755 libnm-gtk4-vpn-plugin-wproxy-editor.so "$GTK4_EDITOR_FILE"
$SUDO install -Dm755 wproxyctl /usr/bin/wproxyctl
if [ -f "$TARGET_HOME/.local/bin/wproxyctl" ]; then
    $SUDO install -m755 -o "$TARGET_UID" -g "$TARGET_GID" wproxyctl "$TARGET_HOME/.local/bin/wproxyctl"
fi
$SUDO env SUDO_USER="$TARGET_USER" /usr/bin/wproxyctl nm sync
$SUDO install -Dm755 "$DESKTOP_BINARY" /usr/bin/wproxy-manager
$SUDO install -Dm644 data/org.freedesktop.NetworkManager.wproxy.conf "$DBUS_FILE"
$SUDO install -Dm644 data/wproxy-manager.desktop /usr/share/applications/wproxy-manager.desktop
$SUDO install -Dm644 icons/wproxy.svg /usr/share/icons/hicolor/scalable/apps/wproxy.svg

$SUDO install -Dm644 data/90-wproxy-unmanaged.conf "$NM_CONF"

if [ "$INSTALL_KDE" -eq 1 ]; then
    $SUDO cmake --install "$PROJECT_DIR/build/plasma-nm"
fi

if [ "$INSTALL_GNOME" -eq 1 ]; then
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

if [ "$INSTALL_GNOME" -eq 1 ] && command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions enable wproxy@wrench.local >/dev/null 2>&1 || true
fi

if [ "$INSTALL_KDE" -eq 1 ]; then
    install_kde_widget() {
        if [ "$(id -u)" -eq 0 ]; then
            # Verified updater sources live below a private root directory.
            KDE_STAGE=$(mktemp -d /tmp/wproxy-kde-install.XXXXXX)
            trap 'rm -rf -- "$KDE_STAGE"' 0
            trap 'exit 1' HUP INT TERM
            install -d -m755 "$KDE_STAGE/scripts" "$KDE_STAGE/kde-plasmoid"
            install -m644 "$PROJECT_DIR/scripts/install-kde-widget.sh" "$PROJECT_DIR/scripts/kde-dedupe-widget.js" "$KDE_STAGE/scripts/"
            cp -R "$PROJECT_DIR/kde-plasmoid/org.wproxy.WProxy" "$KDE_STAGE/kde-plasmoid/"
            chmod -R u=rwX,go=rX "$KDE_STAGE"
            runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
                DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" bash "$KDE_STAGE/scripts/install-kde-widget.sh"
            rm -rf -- "$KDE_STAGE"
            trap - 0 HUP INT TERM
        else
            bash "$PROJECT_DIR/scripts/install-kde-widget.sh"
        fi
    }
    install_kde_widget
fi

echo
[ -x /usr/bin/wproxyctl ] || { echo "Installation failed: /usr/bin/wproxyctl was not installed." >&2; exit 5; }
/usr/bin/wproxyctl --version

echo "Installed WProxy 2.7.5."
XRAY_PATH=$(find_xray 2>/dev/null || true)
[ -n "$XRAY_PATH" ] && "$XRAY_PATH" version 2>/dev/null | head -n 1 || true
if [ "$INSTALL_GNOME" -eq 1 ]; then
    echo 'Close/reopen GNOME Settings. Log out/in to load the new Quick Settings extension.'
fi
echo "Diagnostics: $PROJECT_DIR/scripts/diagnose.sh"
echo "Backup: $BACKUP"
