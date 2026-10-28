#!/usr/bin/env bash
set -eu
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d /tmp/wproxy-gnome-actions.XXXXXX)
export WPROXY_TEST_ROOT="$TEST_ROOT"
export WPROXY_TEST_SOURCE="$REPO_ROOT/gnome-extension/wproxy@wrench.local"
export WPROXY_TEST_FIXTURE="$REPO_ROOT/tests/action-test-extension/fake-ctl.py"
export WPROXY_TEST_PYTHON=$(command -v python3)
export WPROXY_TEST_MONITOR=${WPROXY_TEST_MONITOR:-1366x768}
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
export XDG_DATA_HOME="$TEST_ROOT/data"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_DATA_HOME/gnome-shell/extensions/wproxy-action-test@local" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
chmod 700 "$XDG_RUNTIME_DIR"
export GSETTINGS_BACKEND=keyfile
export LIBGL_ALWAYS_SOFTWARE=1
export GNOME_SHELL_SESSION_MODE=user
cp "$REPO_ROOT/tests/action-test-extension/metadata.json" "$XDG_DATA_HOME/gnome-shell/extensions/wproxy-action-test@local/"
cp "$REPO_ROOT/tests/action-test-extension/extension.js" "$XDG_DATA_HOME/gnome-shell/extensions/wproxy-action-test@local/extension.js"
gsettings set org.gnome.shell enabled-extensions "['wproxy-action-test@local']"
gsettings set org.gnome.shell disable-user-extensions false
echo "Test directory: $TEST_ROOT"
timeout 35s dbus-run-session --config-file="$REPO_ROOT/tests/session-bus.conf" -- bash -c '
    export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
    exec gnome-shell --headless --wayland --no-x11 --virtual-monitor "$WPROXY_TEST_MONITOR"
' > "$TEST_ROOT/shell.log" 2>&1 || true
if [ -f "$TEST_ROOT/result.json" ]; then
    cat "$TEST_ROOT/result.json"
    python3 -c 'import json,sys; sys.exit(not json.load(open(sys.argv[1]))["ok"])' "$TEST_ROOT/result.json"
else
    tail -40 "$TEST_ROOT/shell.log"
    exit 1
fi
