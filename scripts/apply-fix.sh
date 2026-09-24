#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(id -u)" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi
cd "$PROJECT_DIR"

TARGET_USER=${SUDO_USER:-}
if [ -z "$TARGET_USER" ] && [ -n "${PKEXEC_UID:-}" ]; then
    TARGET_USER=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
fi
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = root ]; then
    echo 'Run this script from your normal desktop account with sudo.' >&2
    exit 2
fi
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_GID=$(id -g "$TARGET_USER")
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
USER_EXT="$TARGET_HOME/.local/share/gnome-shell/extensions/wproxy@wrench.local"
SYSTEM_EXT=/usr/share/gnome-shell/extensions/wproxy@wrench.local
LIBEXEC=$(pkg-config --variable=libexecdir NetworkManager 2>/dev/null || true)
[ -n "$LIBEXEC" ] || LIBEXEC=/usr/libexec

make wproxy-service wproxyctl
BACKUP=$(mktemp -d /var/backups/wproxy-2.3.1.XXXXXX)
chmod 700 "$BACKUP"
for name in wproxy-service wproxy-xray-runner; do
    if [ -f "$LIBEXEC/$name" ]; then cp -a "$LIBEXEC/$name" "$BACKUP/$name"; fi
done
if [ -f /usr/bin/wproxyctl ]; then cp -a /usr/bin/wproxyctl "$BACKUP/system-wproxyctl"; fi
if [ -f "$TARGET_HOME/.local/bin/wproxyctl" ]; then
    cp -a "$TARGET_HOME/.local/bin/wproxyctl" "$BACKUP/user-wproxyctl"
fi
if [ -d "$USER_EXT" ]; then cp -a "$USER_EXT" "$BACKUP/user-extension"; fi
if [ -d "$SYSTEM_EXT" ]; then cp -a "$SYSTEM_EXT" "$BACKUP/system-extension"; fi

desktop() {
    runuser -u "$TARGET_USER" -- env \
        XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" "$@"
}

# Stop only WProxy. Restarting NetworkManager left the old plugin process alive.
desktop /usr/bin/wproxyctl nm down || true
if [ -x "$LIBEXEC/wproxy-xray-runner" ]; then
    "$LIBEXEC/wproxy-xray-runner" stop || true
fi
if pgrep -x wproxy-service >/dev/null; then
    pkill -TERM -x wproxy-service
fi
for ((attempt = 0; attempt < 50; attempt++)); do
    if ! pgrep -x wproxy-service >/dev/null; then break; fi
    sleep 0.1
done
if pgrep -x wproxy-service >/dev/null; then
    echo 'WProxy did not stop; installation aborted. No files replaced.' >&2
    exit 3
fi

install -m755 wproxy-service "$LIBEXEC/wproxy-service"
install -m755 service/wproxy-xray-runner "$LIBEXEC/wproxy-xray-runner"
install -m755 wproxyctl /usr/bin/wproxyctl
install -Dm755 -o "$TARGET_UID" -g "$TARGET_GID" wproxyctl "$TARGET_HOME/.local/bin/wproxyctl"
install -d -o "$TARGET_UID" -g "$TARGET_GID" "$USER_EXT"
install -d "$SYSTEM_EXT"
for name in extension.js metadata.json stylesheet.css; do
    install -m644 -o "$TARGET_UID" -g "$TARGET_GID" \
        "gnome-extension/wproxy@wrench.local/$name" "$USER_EXT/$name"
    install -m644 "gnome-extension/wproxy@wrench.local/$name" "$SYSTEM_EXT/$name"
done

"$LIBEXEC/wproxy-service" --version
/usr/bin/wproxyctl --version
echo "Backup: $BACKUP"
echo 'Log out and back in once to load UI version 9 (exactly 3 server rows + scroll).'
echo 'Disabling/enabling the extension alone may keep the old JavaScript cached.'

if [ "${1:-}" != --test ]; then exit 0; fi

# The report contains status and exit codes, never subscription URLs or URIs.
REPORT="$PROJECT_DIR/verification.txt"
exec > >(tee "$REPORT") 2>&1
echo "WProxy 2.3.1 host check: $(date -Is)"
echo 'Testing real HTTPS through the saved servers before enabling system routing...'
if ! NODE_ID=$(desktop python3 scripts/test-proxy-https.py --select); then
    echo 'No saved server passed the Xray HTTPS test; TUN was not enabled.'
    exit 4
fi
echo 'Remote proxy HTTPS: PASS (204)'
if desktop /usr/bin/wproxyctl nm up "$NODE_ID"; then
    echo 'NetworkManager activation: PASS'
else
    echo 'NetworkManager activation: FAIL'
    journalctl -b -u NetworkManager --since '2 minutes ago' --no-pager -o cat | \
        awk '/wproxy|WProxy|VPN gateway|valid IP|config:/{print}'
    desktop /usr/bin/wproxyctl nm down || true
    exit 5
fi

ip -4 -o address show dev wproxy0
ip -6 -o address show dev wproxy0

ROUTE=$(ip -4 route get 1.1.1.1)
case "$ROUTE" in
    *'dev wproxy0'*) echo 'Route through wproxy0: PASS' ;;
    *) echo 'Route through wproxy0: FAIL'; desktop /usr/bin/wproxyctl nm down; exit 6 ;;
esac
if HTTP_CODE=$(curl --noproxy '*' --connect-timeout 8 --max-time 20 -sS \
    -o /dev/null -w '%{http_code}' https://www.gstatic.com/generate_204) && [ "$HTTP_CODE" = 204 ]; then
    echo 'HTTPS through tunnel: PASS (204)'
    echo 'The tested server remains connected.'
else
    echo "HTTPS through tunnel: FAIL (${HTTP_CODE:-no response})"
    desktop /usr/bin/wproxyctl nm down
    exit 7
fi
