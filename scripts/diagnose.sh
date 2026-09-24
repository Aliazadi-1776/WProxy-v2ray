#!/bin/sh
set -u

echo "=== WProxy 2.3.1 diagnostic ==="
echo

echo "[NetworkManager]"
nmcli --version 2>/dev/null || true
systemctl is-active NetworkManager 2>/dev/null || true
echo

echo "[GNOME]"
gnome-shell --version 2>/dev/null || true
gnome-control-center --version 2>/dev/null || true
echo

echo "[Xray]"
XRAY=""
for candidate in /usr/local/bin/xray /usr/bin/xray /opt/xray/xray; do
    if [ -x "$candidate" ]; then XRAY="$candidate"; break; fi
done
if [ -z "$XRAY" ] && command -v xray >/dev/null 2>&1; then XRAY=$(command -v xray); fi
if [ -n "$XRAY" ]; then
    echo "binary: $XRAY"
    "$XRAY" version 2>/dev/null | head -n 3 || true
else
    echo "MISSING: xray"
fi
echo

echo "[CLI]"
if command -v wproxyctl >/dev/null 2>&1; then
    wproxyctl --version 2>/dev/null || true
    wproxyctl status --json 2>/dev/null || true
    echo "Nodes:"
    wproxyctl node list 2>/dev/null | sed -n '1,10p' || true
else
    echo "MISSING: /usr/bin/wproxyctl"
fi
echo

LIBDIR="$(pkg-config --variable=libdir libnm 2>/dev/null || echo /usr/lib)"
LIBEXEC="$(pkg-config --variable=libexecdir NetworkManager 2>/dev/null || echo /usr/libexec)"
[ -n "$LIBEXEC" ] || LIBEXEC=/usr/libexec

for VPN_DIR in "$LIBDIR/NetworkManager/VPN" "/usr/lib/NetworkManager/VPN"; do
    if [ -f "$VPN_DIR/nm-wproxy-service.name" ]; then
        echo "[VPN metadata] $VPN_DIR/nm-wproxy-service.name"
        cat "$VPN_DIR/nm-wproxy-service.name"
        echo
    fi
done

for plugin in \
    "$LIBDIR/NetworkManager/libnm-vpn-plugin-wproxy.so" \
    "$LIBDIR/NetworkManager/libnm-vpn-plugin-wproxy-editor.so" \
    "$LIBDIR/NetworkManager/libnm-gtk4-vpn-plugin-wproxy-editor.so"; do
    echo "[Plugin] $plugin"
    if [ -f "$plugin" ]; then
        file "$plugin" 2>/dev/null || true
        ldd "$plugin" 2>/dev/null | grep -E 'not found|libnm|gtk|glib' || true
    else
        echo "MISSING"
    fi
    echo
done

echo "[Service runtime]"
test -x "$LIBEXEC/wproxy-service" && echo "OK: $LIBEXEC/wproxy-service" || echo "MISSING: $LIBEXEC/wproxy-service"
test -x "$LIBEXEC/wproxy-xray-runner" && echo "OK: $LIBEXEC/wproxy-xray-runner" || echo "MISSING: $LIBEXEC/wproxy-xray-runner"
ip link show wproxy0 2>/dev/null || echo "wproxy0 is not active"
if [ -f /run/wproxy/xray.log ]; then
    echo "--- /run/wproxy/xray.log ---"
    tail -n 50 /run/wproxy/xray.log 2>/dev/null || true
fi
if [ -f /run/wproxy/test.log ]; then
    echo "--- /run/wproxy/test.log ---"
    tail -n 50 /run/wproxy/test.log 2>/dev/null || true
fi
echo

echo "[GNOME extension]"
if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions info wproxy@wrench.local 2>/dev/null || echo "Extension not visible to this GNOME session yet."
else
    echo "gnome-extensions command not installed"
fi
echo

echo "[NetworkManager WProxy logs]"
journalctl -u NetworkManager -b --no-pager 2>/dev/null |
    grep -iE 'wproxy|vpn.*plugin|editor.*plugin' |
    tail -n 160 || true
echo

echo "[D-Bus policy]"
test -f /etc/dbus-1/system.d/org.freedesktop.NetworkManager.wproxy.conf &&
    echo "OK: D-Bus policy exists" || echo "MISSING: D-Bus policy"
echo

echo "[Unmanaged TUN rule]"
test -f /etc/NetworkManager/conf.d/90-wproxy-unmanaged.conf &&
    cat /etc/NetworkManager/conf.d/90-wproxy-unmanaged.conf || echo "MISSING"
echo

echo "[Connections]"
nmcli -f NAME,UUID,TYPE,DEVICE connection show 2>/dev/null |
    grep -i 'WProxy ·' || echo "No WProxy NetworkManager profiles yet."
echo

echo "=== End diagnostic ==="


echo "--- WProxy runtime ---"
printf 'xray: '; command -v xray || true
printf 'wproxyctl: '; command -v wproxyctl || true
printf 'service: '; pgrep -af wproxy-service || true
printf 'runner: '; pgrep -af wproxy-xray-runner || true
printf 'xray process: '; pgrep -af '[x]ray run' || true
echo "--- TUN ---"
ip addr show wproxy0 2>&1 || true
echo "--- routes ---"
ip route show 2>&1 | head -n 80 || true
ip rule show 2>&1 | head -n 80 || true
echo "--- Xray test log ---"
sudo cat /run/wproxy/test.log 2>/dev/null || true
echo "--- Xray runtime log ---"
sudo tail -n 120 /run/wproxy/xray.log 2>/dev/null || true
echo "--- NetworkManager WProxy journal ---"
sudo journalctl -u NetworkManager -n 180 --no-pager 2>/dev/null | grep -iE 'wproxy|vpn|xray|tun' | tail -n 120 || true
