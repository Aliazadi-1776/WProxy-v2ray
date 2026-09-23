#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

if ! command -v wproxyctl >/dev/null 2>&1; then
  echo "wproxyctl not found. Install WProxy first." >&2
  exit 1
fi

echo "Rebuilding WProxy profiles as system-wide NetworkManager VPN connections..."
wproxyctl nm sync

# Defensive cleanup for profiles already loaded in NetworkManager.
nmcli -t -f UUID,TYPE,NAME connection show | while IFS=: read -r uuid type name; do
  [ "$type" = "vpn" ] || continue
  case "$name" in
    WProxy\ *)
      nmcli connection modify uuid "$uuid" connection.permissions "" >/dev/null 2>&1 || true
      ;;
  esac
done

nmcli connection reload

echo "Done. WProxy profiles are now system-wide (not private)."
echo "Try: wproxyctl nm up <real-node-id>"
