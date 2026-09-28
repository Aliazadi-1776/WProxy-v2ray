#!/usr/bin/env bash
set -eu
TEST_ROOT=$(mktemp -d /tmp/wproxy-shell-test.XXXXXX)
export WPROXY_TEST_ROOT="$TEST_ROOT"
export WPROXY_TEST_SOURCE="$PWD/gnome-extension/wproxy@wrench.local"
export WPROXY_TEST_MONITOR=${WPROXY_TEST_MONITOR:-1366x768}
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
export XDG_DATA_HOME="$TEST_ROOT/data"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
chmod 700 "$XDG_RUNTIME_DIR"
export GSETTINGS_BACKEND=keyfile
export LIBGL_ALWAYS_SOFTWARE=1
export GNOME_SHELL_SESSION_MODE=user

# Some development images update the schema XML before refreshing the compiled
# system cache. Keep that host packaging mismatch out of the extension test.
if ! gsettings range org.gnome.desktop.privacy privacy-screen >/dev/null 2>&1 &&
        grep -q 'name="privacy-screen"' \
            /usr/share/glib-2.0/schemas/org.gnome.desktop.privacy.gschema.xml; then
    TEST_SCHEMA_DIR="$TEST_ROOT/schemas"
    mkdir -p "$TEST_SCHEMA_DIR"
    cp /usr/share/glib-2.0/schemas/*.xml "$TEST_SCHEMA_DIR/"
    glib-compile-schemas "$TEST_SCHEMA_DIR"
    export GSETTINGS_SCHEMA_DIR="$TEST_SCHEMA_DIR"
fi

mkdir -p "$XDG_DATA_HOME/gnome-shell/extensions/wproxy-ui-test@local"
cp tests/ui-test-extension/* "$XDG_DATA_HOME/gnome-shell/extensions/wproxy-ui-test@local/"
gsettings set org.gnome.shell enabled-extensions "['wproxy-ui-test@local']"
gsettings set org.gnome.shell disable-user-extensions false
echo "Test directory: $TEST_ROOT"

# Do not leak GTK/GIO module paths from a Snap-hosted IDE into the nested Shell.
CLEAN_ENV=(env -i
    "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    "LANG=${LANG:-C.UTF-8}"
    "XDG_DATA_DIRS=/usr/local/share:/usr/share"
    "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" "XDG_DATA_HOME=$XDG_DATA_HOME"
    "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" "XDG_CACHE_HOME=$XDG_CACHE_HOME"
    "GSETTINGS_BACKEND=$GSETTINGS_BACKEND" "LIBGL_ALWAYS_SOFTWARE=$LIBGL_ALWAYS_SOFTWARE"
    "GNOME_SHELL_SESSION_MODE=$GNOME_SHELL_SESSION_MODE"
    "WPROXY_TEST_ROOT=$WPROXY_TEST_ROOT" "WPROXY_TEST_SOURCE=$WPROXY_TEST_SOURCE"
    "WPROXY_TEST_MONITOR=$WPROXY_TEST_MONITOR")
if [ -n "${GSETTINGS_SCHEMA_DIR:-}" ]; then
    CLEAN_ENV+=("GSETTINGS_SCHEMA_DIR=$GSETTINGS_SCHEMA_DIR")
fi
timeout 35s "${CLEAN_ENV[@]}" dbus-run-session --config-file=tests/session-bus.conf -- bash -c '
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
