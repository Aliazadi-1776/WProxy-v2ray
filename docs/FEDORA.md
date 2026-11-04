# Fedora connection troubleshooting

[راهنمای کامل فارسی](FEDORA.fa.md)

Applies to traditional DNF-based Fedora Workstation and Fedora KDE. This does
not establish support for Silverblue, Kinoite or other Atomic variants. Use the
[Fedora dependency recipe](../README.md#fedora-workstation--fedora-kde-traditional-dnf-based-installation)
before installing. The installed connection fix was verified on a laptop with
NetworkManager 1.58.1; a live Fedora SELinux-enforcing VPN session remains unverified.
See the [target verification report](verification/2026-11-04-linux-connection.md).

## Check the installed components

Run as the normal desktop user:

```bash
/usr/bin/wproxyctl --version
/usr/libexec/wproxy-service --version
/usr/bin/wproxyctl core list --json
/usr/bin/wproxyctl status --json
systemctl is-active NetworkManager
```

The controller and service versions must match; the selected core must be
available. Missing runtime logs before the first start do not prove that a core
is missing. The current runtime directory is `/run/NetworkManager/wproxy`, not
the legacy `/run/wproxy` location.

For mixed/old installations, install all components from the current source
directory after installing dependencies. For a Git checkout use `git pull
--ff-only` first; do not discard local changes. For a ZIP, use its extracted folder.

```bash
# Fedora KDE; use --desktop gnome instead on GNOME
bash scripts/install.sh --desktop kde
```

The installer creates backups. Start Manager as your normal user, not with sudo.

## Separate server failure from tunnel failure

```bash
/usr/bin/wproxyctl node list --json
# Replace NODE_ID with an ID from the preceding output
/usr/bin/wproxyctl node verify NODE_ID --timeout 8
```

This verifies HTTPS through a local core without changing system routes. An open
TCP port is not proof that browsing works. Check Routing as well: **Only selected**
proxies only matching items; **Bypass selected** keeps matching items direct.
Use **Choose application** to select the real executable. If ChatGPT/Codex is
bypassed to preserve support access, its embedded browser may also be direct;
test the VPN in a separate browser that is not bypassed.

## Capture an activation failure or disconnect

Immediately after reproducing the failure:

```bash
sudo journalctl -b -u NetworkManager --since '10 minutes ago' --no-pager -o cat
sudo journalctl -b _COMM=wproxy-service -n 80 --no-pager -o cat
sudo tail -n 80 /run/NetworkManager/wproxy/xray.log
systemctl show NetworkManager -p MainPID -p NRestarts
```

An empty individual log is not a diagnosis. `nm-settings-utils.c:103`, ABRT or
`Message recipient disconnected from message bus without replying` may mean
NetworkManager itself crashed during a profile save. The corrected WProxy path
loads/reloads keyfiles without a subsequent persistent `connection modify` and
reads current routing from its root-owned keyfile. Update the complete
installation rather than repeatedly modifying profiles by hand.

To clear a stuck WProxy runtime without restarting the whole network stack:

```bash
/usr/bin/wproxyctl nm down
sudo /usr/libexec/wproxy-xray-runner stop
sudo /usr/bin/wproxyctl nm sync
```

Then reconnect in Manager. Restarting NetworkManager can interrupt Wi-Fi and is
not a routine recovery step here. If the service is inactive, first repair the
base network connection.

## SELinux: inspect denials and restore default labels

Keep SELinux enforcing. If needed, `sudo dnf install audit policycoreutils`
provides the diagnostic tools on traditional Fedora installations.

```bash
getenforce
sudo ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -ts recent -i
sudo ls -Zd /run/NetworkManager /run/NetworkManager/wproxy
sudo matchpathcon -V /run/NetworkManager/wproxy
```

The runtime directory may exist only after an attempted connection. Compare
labels with the policy installed on that machine. If WProxy paths have the wrong
labels, restore only those paths and retry:

```bash
if [ -d /run/NetworkManager/wproxy ]; then
    sudo restorecon -Rv /run/NetworkManager/wproxy
fi
sudo restorecon -v /usr/libexec/wproxy-service /usr/libexec/wproxy-xray-runner /usr/bin/wproxyctl
```

If denial persists, report the relevant source/target types, denied operation and
WProxy path. Do not use blanket `audit2allow`, `chmod 777` or disable SELinux as a
general fix. References: [Fedora troubleshooting](https://fedoraproject.org/wiki/SELinux/Troubleshooting),
[Fedora file contexts](https://fedoraproject.org/wiki/SELinux/ManagingFileContext).

## Plasma support and authorization

“Plasma is missing support for wproxy VPN connections” can indicate a missing
native Plasma VPN plugin. Install the KDE dependencies, rerun the installer with
`--desktop kde`, then log out/in once. See [KDE integration](KDE.md). A widget's
“Command timed out” message needs the actual Manager/status/journal result; it
does not by itself prove a tunnel is healthy or broken.

In Manager Settings, enable **Ask for permission only once** and approve its
initial Polkit request. It remembers only scoped WProxy operations for the
active local account; it does not store the sudo password. Disable the setting
to revoke approval. If no prompt appears, check `systemctl status polkit
--no-pager` and use a desktop session with its authentication agent running.
Do not add general NOPASSWD rules. A ten-minute disconnect needs logs from that
time; sudo's timestamp expiring alone should not stop NetworkManager's core.

## Verify real traffic and report safely

Use an application that your current Routing policy sends through the VPN:

```bash
curl --noproxy '*' --location --fail --silent --show-error \
  --connect-timeout 8 --max-time 25 --output /dev/null \
  --write-out 'HTTP=%{http_code} bytes=%{size_download} time=%{time_total}s\n' \
  https://www.youtube.com/
ping -c 4 -W 2 www.youtube.com
```

Check the complete HTTPS response and browser playback; ping alone is not a
video-playback test. For an optional installed-path test, disconnect WProxy
first. These commands temporarily use All traffic and restore the prior mode
afterwards, so they can interrupt remote access:

```bash
python3 scripts/live-installed-smoke.py --confirm --quick --temporary-all
python3 scripts/live-installed-smoke.py --confirm --node NODE_A --switch-node NODE_B --temporary-all
```

Report the Fedora/desktop version, installation method, CLI/service versions,
core inventory, routing mode, HTTPS result and relevant journal/AVC records.
Review logs and `bash scripts/diagnose.sh` output before sharing. Never publish
the store, subscription/configuration URLs, core configs, NetworkManager
keyfiles, credentials or personal IP addresses.
