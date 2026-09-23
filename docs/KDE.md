# KDE Plasma 6

[English overview](../README.md) · [فارسی](../README.fa.md)

## What is included

`kde-plasmoid/org.wproxy.WProxy/` is a native QML Plasma 6 applet. It uses the same `/usr/bin/wproxyctl` backend as the GNOME extension. It can be added to a panel, the desktop, or the System Tray. Plasma 5 is not supported.

- Select a server row to connect; use the header switch to disconnect/reconnect.
- Scroll past the first three servers without moving the subscription/footer controls.
- Use the small refresh button to ping one endpoint, or **Ping all** for all endpoints.
- Paste an HTTP(S) subscription and choose **Add**, or use **Update**.
- **Manager** opens the GTK4 application. GTK dependencies are still needed on KDE.

The applet is independent of KDE's built-in Networks applet. It does not modify that applet's server list or automatically rearrange the panel.

## Installation

Install the common dependencies **and** the KDE-only packages for your distribution in the [English README](../README.md#2-install-your-distributions-dependencies) or [راهنمای فارسی](../README.fa.md). The common GTK dependencies are required even on KDE. Then, in a Plasma **6** session, from the source directory:

```bash
bash scripts/install.sh --desktop kde
```

On Debian/Ubuntu with the backend already installed:

```bash
sudo apt-get install kpackagetool6 qml6-module-org-kde-kirigami qml6-module-org-kde-plasma-plasma5support polkit-kde-agent-1
bash scripts/install-kde-widget.sh
```

Do not run the widget-only installer with sudo. It installs to the current user's Plasma packages using `kpackagetool6`. Other distributions have explicit KDE package commands in the READMEs. The module name Plasma5Support is correct for Plasma **6**; it does not mean this widget supports Plasma 5.

Then choose one:

1. **Configure System Tray → Entries → WProxy → Always shown**.
2. **Edit panel → Add Widgets → WProxy**; drag it beside **Networks**.

If you keep it as an automatically hidden tray entry, it may live under the tray's expand arrow while disconnected. Showing it permanently makes the connect button easy to reach.

## Permissions and dependencies

The applet runs as the desktop user, never root. Ordinary status/ping/connect operations call the CLI. New or updated subscription profiles use `pkexec /usr/bin/wproxyctl nm sync`, so the Plasma Polkit agent must be running. No password is collected by the widget itself.

The widget uses the **Plasma5Support `executable` data engine** to invoke safely quoted commands. Its module name contains “plasma5support” even on Plasma 6. If a distro/policy disables this engine, it must be available for the widget to work; do not mistake its absence for a server outage.

## Tests

```bash
bash scripts/test-kde.sh
```

The test requires Qt 6's `qmltestrunner`, QtTest QML, Qt Quick Controls/Layouts, Kirigami and Plasma5Support QML. `QMLTESTRUNNER=/path/to/qmltestrunner` can override tool discovery. Tests run offscreen using software rendering and synthetic data, including 100 servers, selection, fixed footer, scroll preservation and real command-runner quoting.

Full desktop placement, Polkit prompts and connection switching in an actual KDE login still need field testing. The shared NetworkManager/TUN backend has a successful host HTTPS report from GNOME; that is not an end-to-end KDE certification.

## Update / remove

```bash
bash scripts/install-kde-widget.sh
bash scripts/uninstall-kde-widget.sh
```

Remove/re-add the widget or log out/in if Plasma retains an older QML instance. Removing the widget leaves the backend, servers and subscriptions intact.

## Implementation references

- [Official Plasma 6 porting guide](https://develop.kde.org/docs/plasma/widget/porting_kf6/): PlasmoidItem and Plasma5Support APIs.
- [Official widget setup](https://develop.kde.org/docs/plasma/widget/setup/): package metadata and installation layout.
- [System Tray metadata](https://develop.kde.org/docs/plasma/widget/properties/): notification-area registration.
