#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "$0")/.."
RUNNER=${QMLTESTRUNNER:-}
if [ -z "$RUNNER" ]; then
    for candidate in /usr/lib/qt6/bin/qmltestrunner /usr/lib64/qt6/bin/qmltestrunner; do
        if [ -x "$candidate" ]; then RUNNER=$candidate; break; fi
    done
fi
if [ -z "$RUNNER" ]; then
    echo 'Install Qt 6 declarative dev tools, QtTest QML, Kirigami and Plasma5Support QML.' >&2
    exit 2
fi
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen}
export QT_QUICK_BACKEND=software
export QT_QUICK_CONTROLS_STYLE=Basic
"$RUNNER" -input tests/qml "$@"
