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

echo 'WProxy Plasma 6 widget installed.'
echo 'Configure System Tray → Entries → WProxy → Always shown.'
echo 'Or: Edit panel → Add Widgets → WProxy, then place it beside Networks.'
echo 'For updates, remove/re-add the widget or log out/in if Plasma keeps old QML cached.'
