#!/usr/bin/env bash
set -euo pipefail
if [ "$(id -u)" -eq 0 ]; then
    echo 'Run as your normal KDE desktop user, without sudo.' >&2
    exit 2
fi
kpackagetool6 --type Plasma/Applet --remove org.wproxy.WProxy
echo 'The KDE widget was removed. WProxy servers, subscriptions and backend were kept.'
