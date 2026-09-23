#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    command -v sudo >/dev/null 2>&1 || { echo "sudo is required" >&2; exit 2; }
    SUDO="sudo"
fi

LIBDIR="$(pkg-config --variable=libdir libnm 2>/dev/null || true)"
[ -n "$LIBDIR" ] || LIBDIR=/usr/lib

for f in \
    "$LIBDIR/NetworkManager/libnm-vpn-plugin-wproxy.so" \
    "$LIBDIR/NetworkManager/libnm-vpn-plugin-wproxy-editor.so" \
    "$LIBDIR/NetworkManager/libnm-gtk4-vpn-plugin-wproxy-editor.so" \
    "$LIBDIR/NetworkManager/VPN/nm-wproxy-service.name" \
    "/usr/lib/NetworkManager/VPN/nm-wproxy-service.name"; do
    [ -e "$f" ] && $SUDO rm -f "$f"
done

$SUDO systemctl restart NetworkManager

echo "The WProxy editor plugin was removed. Close GNOME Settings completely and reopen it."
echo "Your WProxy node store was not deleted. Run the new installer to restore WProxy safely."
