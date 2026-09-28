#!/bin/sh
set -eu

# Tests and packagers may provide the version string explicitly. Normal
# installs always inspect the gnome-shell binary on the target system.
VERSION_TEXT=${WPROXY_GNOME_SHELL_VERSION:-}
if [ -z "$VERSION_TEXT" ]; then
    command -v gnome-shell >/dev/null 2>&1 || {
        echo 'GNOME Shell is not installed or is not in PATH.' >&2
        exit 2
    }
    VERSION_TEXT=$(gnome-shell --version 2>/dev/null || true)
fi

MAJOR=$(printf '%s\n' "$VERSION_TEXT" |
    sed -n 's/^[^0-9]*\([0-9][0-9]*\)\([.][0-9][0-9]*\)\{0,1\}.*$/\1/p')

case "$MAJOR" in
    49|50|51)
        printf '%s\n' "$MAJOR"
        ;;
    '')
        echo "Could not parse the GNOME Shell version: $VERSION_TEXT" >&2
        exit 2
        ;;
    *)
        echo "Unsupported GNOME Shell $MAJOR. WProxy supports GNOME Shell 49, 50 and 51." >&2
        exit 2
        ;;
esac
