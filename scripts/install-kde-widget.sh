#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WIDGET_ID=org.wproxy.WProxy

if [ "$(id -u)" -eq 0 ]; then
    echo 'Run this script as your normal KDE desktop user, without sudo.' >&2
    exit 2
fi
if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo 'Plasma 6 and kpackagetool6 are required. Plasma 5 is not supported.' >&2
    exit 3
fi
if [ ! -x /usr/bin/wproxyctl ]; then
    echo 'Install the backend first: bash scripts/install.sh --desktop kde' >&2
    exit 4
fi

if kpackagetool6 --type Plasma/Applet --show "$WIDGET_ID" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$PROJECT_DIR/kde-plasmoid/$WIDGET_ID"
else
    kpackagetool6 --type Plasma/Applet --install "$PROJECT_DIR/kde-plasmoid/$WIDGET_ID"
fi

QDBUS=
if command -v qdbus6 >/dev/null 2>&1; then
    QDBUS=qdbus6
elif command -v qdbus >/dev/null 2>&1; then
    QDBUS=qdbus
fi
if [ -n "$QDBUS" ] && $QDBUS org.kde.plasmashell /PlasmaShell >/dev/null 2>&1; then
    if ! $QDBUS org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "$(cat "$PROJECT_DIR/scripts/kde-dedupe-widget.js")"; then
        echo 'Warning: WProxy was updated, but duplicate panel widgets could not be cleaned automatically.' >&2
    fi
fi

echo 'WProxy Plasma 6 widget installed.'
echo 'Configure System Tray → Entries → WProxy → Always shown.'
echo 'The installer keeps one WProxy icon per panel and removes duplicate copies.'
echo 'For cached QML after an update, log out and back in once.'
