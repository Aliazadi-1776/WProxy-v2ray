# WProxy

**Xray/V2Ray connections in your Linux desktop panel.**

GNOME Quick Settings · KDE Plasma 6 widget · NetworkManager · GTK manager · CLI

[راهنمای فارسی](README.fa.md) · [KDE setup](docs/KDE.md) · [Testing](docs/TESTING.md) · [Changelog](CHANGELOG.md)

WProxy imports VLESS, VMess, Trojan and Shadowsocks share links and HTTP(S) subscriptions, runs Xray through a system TUN interface, and exposes connection controls through your desktop. Version **2.3.1** fixes a transport-selection bug that made WebSocket links fail while the tunnel could still appear connected. The Plasma 6 frontend was introduced in 2.3.0.

**Upgrade notice:** install this version to update the actual runtime; replacing a ZIP alone is not an upgrade. See the [connection fix and before/after tests](docs/CONNECTION-FIX-2.3.1.md).

## Screenshots

### GNOME Quick Settings

Three visible server rows, scrolling for the rest, per-server latency and selection, and fixed subscription/action controls.

![WProxy connected beside Wi-Fi in GNOME Quick Settings](docs/screenshots/gnome-quick-settings.png)

### Desktop manager

Manage servers and subscriptions independently of the panel widget.

![WProxy desktop manager showing imported servers](docs/screenshots/manager.png)

These supplied screenshots show the GNOME/GTK interface in version 2.2.10. They are not screenshots of the new KDE widget. No server credentials or subscription URL are displayed.

## Features

- Import VLESS, VMess, Trojan and Shadowsocks links; add and update subscriptions.
- Connect/disconnect through NetworkManager with the installed Xray core.
- GNOME: a V2Ray tile beside Wi-Fi, with WProxy duplicates hidden from GNOME's native VPN dropdown.
- KDE Plasma 6: a WProxy panel/System Tray widget with server selection, per-server and batch ping, subscription input, update, and manager access.
- Three-row scrolling lists keep controls visible as the server count grows.
- Display remaining subscription traffic when the provider supplies usage information.
- Separate GTK manager, CLI, and GTK3/GTK4 NetworkManager editors.

**Ping measures TCP connection latency to a server endpoint, not end-to-end VPN health.** A successful HTTPS-through-TUN test is stronger evidence than a ping result.

## Compatibility

WProxy is a **Linux** application, not a Windows/macOS application. It needs a normal, writable system installation, systemd, an active NetworkManager managing the uplink, and Linux TUN support. Installing GTK or Qt alone does not make the backend portable.

| Component / platform | Support and verification |
| --- | --- |
| GNOME Quick Settings | Metadata declares GNOME **45–51**; runtime/layout tested on **51.beta** only |
| KDE widget | Targets **Plasma 6**; Qt/Plasma component tests and isolated KPackage installation passed; a full KDE login/connection test is still pending |
| Backend | Linux + NetworkManager + Xray with native TUN + Python 3 + iproute2 |
| GTK manager and editors | GTK4/PyGObject manager, GTK3/GTK4 editors; GTK dependencies are needed even on KDE or with `--desktop none` |
| Ubuntu / Debian family | APT dependency fallback in the installer; live backend/GNOME verification was on Ubuntu **26.10 development**, x86_64, not every release |
| Arch / EndeavourOS / Manjaro | Manual dependency recipe below; installation and real connection not verified on these distributions |
| Fedora Workstation / KDE | Manual dependency recipe below; installation, SELinux integration and real connection not verified |
| openSUSE Tumbleweed | Manual dependency recipe below; installation, security-policy integration and real connection not verified |
| Cinnamon / Xfce / MATE / COSMIC / other desktops | No dedicated panel integration; `--desktop none` installs the backend + GTK manager; desktop-specific testing pending |
| Plasma 5 / GNOME outside 45–51 | No supported panel frontend in this release |
| Windows / macOS / BSD | Not supported |
| NixOS / Alpine / immutable systems | These installation scripts are not supported; no Nix module, OpenRC, rpm-ostree or transactional installation is supplied |
| ARM / other CPU architectures | Source builds may be possible with a suitable Xray binary, but are untested; do not treat this as a universal binary release |

The KDE widget does **not** inject rows into Plasma's built-in Networks applet, hide its VPN entries, or provide a Qt VPN editor. Place the separate WProxy widget beside Networks.

## Install

### 1. Open the source directory

Extract the ZIP, then open a terminal in the directory containing `Makefile` and `scripts/`. For this release archive:

```bash
cd WProxy-2.3.1
```

A GitHub “Download ZIP” may use a different folder name; enter that extracted folder instead. Run as your **normal desktop account**, not a root login, and leave Python virtual environments/Conda first. You need working Internet and permission to use `sudo`.

Use an already installed GNOME or Plasma desktop. Check **only the command for your desktop**:

```bash
gnome-shell --version
```

```bash
plasmashell --version
```

The GNOME extension requires 45–51; the KDE widget requires Plasma 6. A distro name alone does not imply either version. Do not install a second desktop just to satisfy the commands below.

### 2. Install your distribution's dependencies

Choose **one** distribution block. Install the common dependencies even on KDE: the current build includes the GTK manager and both editors. The KDE-only block is additional, not a replacement. These commands install dependencies; step 3 installs **WProxy itself**.

#### Debian / Ubuntu / Kubuntu / Linux Mint

For currently maintained Debian/Ubuntu-based systems with these packages available:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential pkg-config libglib2.0-dev libgtk-3-dev libgtk-4-dev libnm-dev \
  network-manager python3 python3-gi gir1.2-gtk-4.0 \
  curl ca-certificates unzip iproute2 procps util-linux sudo pkexec
```

**Plasma 6 only**, also install:

```bash
sudo apt-get install -y \
  kpackagetool6 qml6-module-org-kde-kirigami \
  qml6-module-org-kde-plasma-plasma5support polkit-kde-agent-1
```

If these Plasma 6 packages are unavailable, stop: do not substitute Plasma 5 packages or mix repositories from another distro release. Use `--desktop none` or a distribution release with Plasma 6. Mint's default Cinnamon is **not** GNOME; use `--desktop none` there unless you separately run a supported desktop. If Ubuntu reports a missing package, check that the official repositories for your release (including Universe where applicable) are enabled.

#### Arch Linux / EndeavourOS / Manjaro

```bash
sudo pacman -Syu --needed \
  base-devel pkgconf glib2 glib2-devel gtk3 gtk4 libnm networkmanager \
  python python-gobject curl ca-certificates unzip iproute2 \
  procps-ng util-linux sudo polkit
```

This also performs a system upgrade; read the package manager's proposed transaction. Avoid partial upgrades. On derivatives, use their own repositories and update guidance.

**Plasma 6 only**, also install:

```bash
sudo pacman -S --needed kpackage kirigami plasma5support polkit-kde-agent
```

Arch's package names and PyGObject setup are documented in the [official GLib development package](https://archlinux.org/packages/core/x86_64/glib2-devel/), [KPackage file list](https://archlinux.org/packages/extra/x86_64/kpackage/files/) and [PyGObject installation guide](https://pygobject.gnome.org/getting_started.html).

#### Fedora Workstation / Fedora KDE (traditional, DNF-based installation)

```bash
sudo dnf install \
  gcc make pkgconf-pkg-config glib2-devel gtk3-devel gtk4-devel \
  NetworkManager NetworkManager-libnm-devel python3 python3-gobject gtk4 \
  curl ca-certificates unzip iproute procps-ng util-linux sudo polkit
```

**Plasma 6 only**, also install:

```bash
sudo dnf install kf6-kpackage kf6-kirigami plasma5support polkit-kde
```

Package references: [NetworkManager development files](https://packages.fedoraproject.org/pkgs/NetworkManager/NetworkManager-libnm-devel/), [KPackage](https://packages.fedoraproject.org/pkgs/kf6-kpackage/kf6-kpackage/), [Plasma5Support](https://packages.fedoraproject.org/pkgs/plasma5support/plasma5support/). These instructions do **not** cover Silverblue, Kinoite, other Atomic variants, RHEL or CentOS. Keep SELinux enabled; investigate policy denials instead of disabling it to force an installation.

#### openSUSE Tumbleweed (traditional installation)

```bash
sudo zypper refresh
sudo zypper install \
  gcc make pkg-config glib2-devel gtk3-devel gtk4-devel 'pkgconfig(libnm)' \
  NetworkManager python3 python3-gobject python3-gobject-Gdk typelib-1_0-Gtk-4_0 \
  curl ca-certificates unzip iproute2 procps util-linux sudo polkit
```

`pkgconfig(libnm)` asks the package manager for the package providing the libnm development files.

**Plasma 6 only**, also install:

```bash
sudo zypper install kf6-kpackage kf6-kirigami-imports plasma5support6 polkit-kde-agent-6
```

See the [upstream PyGObject/openSUSE instructions](https://pygobject.gnome.org/getting_started.html#opensuse) and [openSUSE Plasma5Support package](https://build.opensuse.org/package/show/openSUSE:Factory/plasma5support6). This is an **untested Tumbleweed recipe**, not a promise for every Leap/SUSE version. If a package is unavailable in your enabled official repositories, resolve the package/version difference first; do not add arbitrary third-party repositories. MicroOS/Aeon/Kalpa and transactional installations are not covered.

### 3. Check prerequisites, then install WProxy

Back in the source directory, these checks must succeed:

```bash
make check-deps
python3 -c "import gi; gi.require_version('Gtk', '4.0'); from gi.repository import Gtk; print('GTK4 / PyGObject: OK')"
command -v pkexec
nmcli general status
systemctl is-active NetworkManager
```

NetworkManager must already manage your Internet connection. If you currently use another network manager, follow your distro's migration instructions first; enabling two competing managers can disconnect you. On an already configured NetworkManager system where its service is merely stopped, use `sudo systemctl enable --now NetworkManager`.

For KDE, additionally check `kpackagetool6 --version` and keep the desktop's Polkit authentication agent running.

**Finally, run exactly one of the following installation commands:**

GNOME 45–51:

```bash
bash scripts/install.sh --desktop gnome
```

KDE Plasma 6:

```bash
bash scripts/install.sh --desktop kde
```

Backend + GTK manager, without a panel frontend:

```bash
bash scripts/install.sh --desktop none
```

Or, inside a supported GNOME/Plasma session, `bash scripts/install.sh` detects the desktop automatically. The explicit forms above avoid ambiguity on derivatives.

The installer compiles the service/editors and uses sudo for system files. **Automatic missing-dependency installation is APT-only**; Arch/Fedora/openSUSE must complete step 2 first. If Xray is absent, the script downloads and runs the [official XTLS installer](https://github.com/XTLS/Xray-install) as root; review that trust decision before continuing. Existing Xray is not automatically upgraded. It must support native TUN; the tested core was **26.3.27**, not a guarantee for every older/newer version.

Replaced WProxy files are backed up under `/var/backups/`. An upgrade stops WProxy temporarily but does not restart all of NetworkManager. This is a source installer, not a distro-managed DEB/RPM/Flatpak.

### 4. Load the desktop controls

**GNOME:** log out/in once, then run `gnome-extensions enable wproxy@wrench.local` if the tile is not enabled. Close/reopen GNOME Settings before using its VPN editor.

**KDE:** choose **Configure System Tray → Entries → WProxy → Always shown**, or **Edit panel → Add Widgets → WProxy** and drag it beside Networks. Log out/in or remove/re-add an older widget if Plasma caches it. See [KDE setup](docs/KDE.md).

Check installation with `wproxyctl --version`, then open `wproxy-manager`, add your own subscription/server and connect. No working server credentials are bundled, and a successful installation alone does not prove a VPN connection works.

### Upgrade an existing GNOME WProxy installation

```bash
bash scripts/apply-fix.sh --test
```

This updates the GNOME/runtime copies together, probes saved servers over local SOCKS, selects a working candidate, and checks NetworkManager activation, the actual TUN route and HTTPS. It saves a **local-only** `verification.txt`; do not commit diagnostic reports. It leaves a successful test connection active and disconnects after failed route/HTTPS checks.

## Use

Open **WProxy** from the application menu, or run:

```bash
wproxy-manager

# Add a subscription
wproxyctl sub add 'https://example.com/subscription'
wproxyctl sub update
sudo wproxyctl nm sync

# Inspect servers, then connect by ID
wproxyctl node list
wproxyctl node ping --all
wproxyctl nm up NODE_ID
wproxyctl nm down
wproxyctl status --json
```

Panel controls request Polkit authentication when new/changed subscription profiles must be synced. This is expected. Keep a Polkit authentication agent running in your desktop session.

## Build and test

The installation dependencies above do not include every developer test tool. Install Node.js from your distribution for `make test`; Qt/GNOME integration tests need the extra tools listed in [test coverage](docs/TESTING.md).

```bash
make check-deps
make all
make test

# Requires Qt 6 test tools, Kirigami and Plasma5Support QML
bash scripts/test-kde.sh

# Requires GNOME Shell 51; runs an isolated headless fixture
bash tests/headless-smoke.sh
```

The GitHub Actions workflow builds the backend/editors and runs unit, syntax, shell-quoting and package checks. Desktop integration tests are separate. See [test coverage and limitations](docs/TESTING.md).

## Troubleshooting and removal

```bash
bash scripts/diagnose.sh
sudo tail -n 60 /run/wproxy/xray.log
journalctl -u NetworkManager -b

# Remove only the Plasma widget (no sudo)
bash scripts/uninstall-kde-widget.sh

# Remove WProxy program files and its generated NM profiles
bash scripts/uninstall.sh
```

The main uninstaller keeps the saved store in `~/.config/wproxy/` and the separately installed Xray core. Remove the KDE widget separately if installed. On GNOME, log out/in after extension changes.

## Privacy and security

The local store contains subscription URLs and proxy credentials. Do not publish `~/.config/wproxy/`, NetworkManager profiles, generated Xray configs, or unredacted logs. This repository includes source, synthetic test fixtures and the supplied screenshots—not a user's configuration store. See [security notes](SECURITY.md).

## License

WProxy source is licensed under the [MIT License](LICENSE). Xray, NetworkManager, GNOME, KDE and Qt remain separate projects under their own licenses; their binaries are not bundled here.
