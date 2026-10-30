# 2.7.7

- Switch servers from Manager with one click and one authorization request. Check the replacement after stopping the old tunnel, and restore the previous saved connection if the replacement fails.
- Sync only the selected Linux profile during Connect, using two NetworkManager commands instead of scanning and rewriting every saved profile. Explicit full synchronization and the existing tunnel/routing lifecycle remain available unchanged.
- Show Connecting/Switching feedback and use the existing WProxy SVG logo in the sidebar and About card.
- Add shared connection/rollback regressions and a native Windows UI test that switches between two servers without clicking Disconnect.

# 2.7.6

- Allow a bounded DNS readiness interval after NetworkManager activation instead of immediately tearing down an otherwise healthy tunnel. Require an actual HTTPS 204 response, retain failure rollback and report the final curl reason.
- Explicitly publish stable releases as latest so automatic update discovery does not stay on an older stable version.
- Add a native Windows regression that upgrades the previously published app through its actual Automatic updates checkbox, preserving settings and servers.

# 2.7.5

- Restyle only the Manager with the requested rounded navy surfaces, blue controls and clearer connected state, preserving its navigation and actions.

- Install native Plasma VPN support so Fedora/Arch KDE Networks can activate WProxy profiles; preserve installed GNOME and KDE integrations during updates.
- Run each Plasma command with a fresh execution identity, use remembered WProxy authorization for connect/sync/disconnect, and detach Manager launches to avoid false timeouts.
- Prevent delayed cleanup or stale service callbacks from stopping a replacement tunnel; keep Disconnect pending until the owned runtime has exited.
- Keep the Plasma popup aligned under native light/dark themes and distinguish successful disconnects from errors.
- Check for updates whenever Automatic updates is enabled, prevent duplicate installations and keep the desktop responsive while installing.

# 2.7.4

- Fix Windows Connect and Quick connect remaining busy after a successful connection: wait for the elevated command controller to exit while the detached Xray tunnel continues running.
- Expand Windows checks to exercise the installed WebView interface and the native TUN, route, DNS and HTTPS path with an isolated local server.
- Add repeatable GNOME Quick Settings action tests in a private Shell session, alongside the existing layout checks and Linux installer dry-run.
- Validate the real Plasma widget host and temporary package install/upgrade/remove lifecycle alongside the Qt Quick suite.
- Preserve LF line endings in Linux Makefiles and extensionless helpers when source archives are built on Windows.

# 2.7.3

- Check actual HTTPS through Xray before desktop connection or automatic server selection, so an open TCP port cannot make a broken server the preferred VPN.
- Restore the normal network automatically when a desktop full-tunnel connection fails its DNS/HTTPS check.
- Remember limited Linux WProxy authorization on first connection by default, with a Settings switch to revoke it; sync current routing before activation.
- Verify and install Linux updates from the same administrator-private snapshot so replacing the original download cannot change the code being installed.
- Keep the desktop responsive during connection checks and explain empty "Only selected" routing before connecting.
- Embed the compiled frontend in Linux and Windows Tauri release binaries instead of accidentally loading the Vite development server from `localhost:1420`.
- Reject release binaries that do not embed the compiled frontend assets before they can be installed or published.

# 2.7.2

- Stop the KDE Plasma widget from launching three CLI refresh commands every five seconds while collapsed; refresh only when the popup opens or after explicit actions.
- Suspend the command watchdog while no command is running, eliminating idle timer wakeups without weakening the 120-second timeout for active commands.

# 2.7.1

- Repair repeated WProxy Plasma panel icons during KDE installation and upgrades: duplicate System Tray entries and standalone panel copies are collapsed to one icon per panel.
- Stop instructing users to add a second standalone panel widget when the System Tray integration is already active.

# 2.7.0

- Replace the legacy Windows PowerShell/WinForms and standalone GTK managers with one compact Tauri 2 shell for Linux and Windows, using the system WebView rather than Electron.
- Add responsive server, subscription, import, split-routing and settings pages, explicit empty/error/loading states, a native application picker and a focused sushTun-inspired graphite-and-blue visual system.
- Add **Quick connect / Use fastest**: test every saved endpoint concurrently, ignore timeouts and connect to the lowest-latency responder with deterministic tie handling.
- Remove periodic desktop polling entirely; status refreshes only at startup or after explicit user actions, avoiding repeated frozen-engine launches while idle.
- Add opt-in automatic updates on Linux and Windows. Release assets are downloaded over HTTPS and must match the tagged `SHA256SUMS` manifest before installation.
- Add an opt-in Linux **Remember authorization** control backed by a local, active-session Polkit rule for a fixed allowlisted WProxy helper. No sudo password is stored and arbitrary root commands are never authorized.
- Keep the GNOME Quick Settings source and Linux tunnel algorithm unchanged; build the actual optimized Tauri binary during the Linux installer dry-run and on real Windows CI.
- Keep repair scripts on the Tauri manager so a later repair cannot silently restore the retired GTK interface.

# 2.6.1

- Replace the Windows owner-drawn tab strip, which could collapse into a thin line on real Windows DPI/theme combinations, with a fixed navigation rail and independent page host matching the Linux manager structure.
- Add a clear empty-server state with a direct **Add connection** action, then return to Servers automatically after a successful link or subscription import.
- Tighten action sizing at the minimum supported window width while keeping large touch/click targets and the persistent system-tunnel status card.
- Add a native Windows WinForms layout smoke test to the release workflow so collapsed navigation or content fails the build before an installer is published.

# 2.6.0

- Redesign the GTK4 manager with a spacious Material You-inspired shell, clear navigation, status and content cards, masked import fields, responsive action placement and an explicit empty-only routing warning.
- Add a searchable Linux installed-application picker plus executable browsing; resolve selected commands to absolute paths for reliable Xray process matching.
- Fix stale in-memory NetworkManager routing policies by updating `routing64` through `nmcli`, and map/stop active WProxy profiles by deterministic UUID when NetworkManager suffixes duplicate names.
- Make Linux application routing functional by running only the official Xray process outside NetworkManager's capability sandbox, with deterministic transient-unit cleanup and rapid reconnect race protection.
- Require and verify Xray 26.9.30 or newer during Linux installation; add a reversible live routing smoke test that preserves the user's original policy and never prints public IPs or credentials.
- Bring the Windows manager into the same palette, rounded component language and roomier default layout while retaining its UAC-scoped TUN backend and verified adapter/route/HTTPS connection state.

# 2.5.1

- Redesign the Windows manager as a DPI-aware dark desktop application with a persistent tunnel-status card, clearer server/subscription/routing pages, improved list and action styling, keyboard shortcuts, double-click connect and direct server removal.
- Prevent Unicode server or subscription names from closing the Windows manager by forcing UTF-8 command streams, treating native stderr as an operation result and catching UI-thread failures without terminating the tray process.
- Add a Windows CI smoke test that round-trips an emoji server name through the frozen command engine and PowerShell JSON parser.

# 2.5.0

- Add a one-click Windows x64 Inno Setup installer that bundles a standalone PyInstaller command engine and the pinned official Xray 26.9.30/Wintun runtime; end users no longer install Python or Xray separately.
- Refuse false-positive Windows connections: require a supported Xray version, Wintun adapter, adapter-owned IPv4 default route and successful no-explicit-proxy HTTPS request before storing verified connected state.
- Add Xray Windows automatic IPv4/IPv6 routes, outbound-interface selection, 1400 MTU and Windows Filtering Platform DNS/misconfiguration leak controls.
- Add a Windows application picker for running processes and browsed EXE files; normalize name-only `.exe` selectors to Xray process-matching semantics.
- Give subscription nodes source-scoped IDs so identical links from multiple subscriptions remain independently visible and cannot be removed by updating/deleting another subscription.
- Show source subscription names on nodes and imported-server counts on subscription pages in the Windows and GTK managers.
- Parse supported links from plain/base64, JSON and mixed subscription responses, deduplicate within one response, and reject responses larger than 8 MiB.
- Add a tagged GitHub release workflow that builds `WProxy-2.5.0-Setup.exe`, verifies the upstream Xray SHA-256, uploads the installer/checksum artifact and publishes them on tag `v2.5.0`.

# 2.4.1

- Restore the unchanged WProxy Quick Settings card on GNOME 51 by replacing the removed `St.BoxLayout.vertical` property with `Clutter.Orientation.VERTICAL`; Ping all, per-node ping, Update and Manager remain in their previous positions.
- Remove already-loaded stale WProxy NetworkManager connections as well as their deleted keyfiles, while proving ownership from the deterministic UUID before deletion so unrelated VPNs and other users' WProxy profiles remain untouched.
- Filter quota, expiry and renewal announcements encoded as fake proxy links by subscription providers so they cannot be selected as VPN servers.
- Add regressions for GNOME 51 layout construction, subscription-announcement filtering and ownership-safe stale-profile discovery.

# 2.4.0

- Add validated split routing for sites and local applications with full-tunnel, bypass-list and only-list modes; full-tunnel remains the backward-compatible default.
- Persist one versioned policy in the existing user store and embed it into every NetworkManager profile so the root runner receives the same policy without reading another user's home directory.
- Add a GTK Routing page, CLI management commands, bounded input validation, automatic GUI profile synchronization and focused Python/C regression tests.
- Add an experimental Windows 10/11 notification-area frontend using Xray native TUN, with per-user installer, UAC-scoped connect/disconnect, server/subscription/ping controls and shared routing rules.
- Document that arbitrary Win+A Quick Settings tiles are not supported by a public Windows extension API; do not patch Explorer or claim native Quick Settings integration.
- Synchronize version 2.4.0 across CLI, service, GNOME, Plasma, installers, source packager, tests, English/Persian guides and release artifacts.

# 2.3.1

- Fix Xray transport selection: emit streamSettings.network rather than the ignored method field, which caused WebSocket and other non-TCP links to run as plain TCP.
- Preserve TCP HTTP camouflage Host/path fields, including VMess, and decode URI query fields only once.
- Reject removed/unknown transports and unknown security values instead of silently downgrading to TCP/none.
- Add per-node/custom-target HTTPS probes and a real loopback Xray WebSocket handshake regression test.
- Record real before/after proxy HTTPS and YouTube response checks, separately from system TUN verification.

# 2.3.0

- Document separate Debian/Ubuntu, Arch-family, Fedora and openSUSE Tumbleweed dependency recipes, the final desktop-specific install command, and tested versus untested support levels in English and Persian.
- Distribute WProxy source and the standalone widget archive under the MIT license.
- Add a Plasma 6 panel/System Tray widget with the shared WProxy CLI backend, connect/disconnect, server selection, per-node/batch TCP latency, subscription add/update, and manager access.
- Keep exactly three visible KDE server rows; preserve the scroll position during latency/status updates and keep subscription/footer controls outside the list.
- Shell-quote every command argument and handle Polkit cancellation, malformed JSON, command failures, duplicate in-flight work and timeouts.
- Add desktop selection to the full installer (`--desktop gnome|kde|none|auto`) and widget-only KDE installation/removal scripts.
- Stop only WProxy during upgrades; refresh NetworkManager configuration without restarting the user's entire network stack. Update pre-existing user-local GNOME/CLI copies too.
- Add English/Persian README files with supplied screenshots, security/testing/KDE documentation, GitHub CI, release checks and a reproducible source packager.
- No change to the 2.2.10 TUN connection algorithm in this release.

# 2.2.10

- Fix compatibility with installed Xray 26.3.27: only emit supported TUN fields; explicitly bring up/address the TUN and let NetworkManager own default routes and DNS.
- Bind proxy/direct sockets to the physical outbound interface and pin the pre-resolved server IP while preserving TLS SNI / transport Host.
- Allocate exactly three actual server rows in St.ScrollView's preferred-height implementation; compact fixed subscription/footer controls. UI version 8, visible release 2.2.10.
- Test actual HTTPS via an unprivileged local SOCKS listener before choosing a node for the host TUN test.
- Add regression tests for an existing TUN without an address, configuration failures, endpoint pinning, NetworkManager defaults, and a real isolated GNOME Shell layout test with 100 rows.
- Mark intentionally unused D-Bus callback arguments; the service now builds without the reported warnings.

# 2.2.9

- Report a resolved external gateway and the actual IPv4/IPv6 TUN addresses to NetworkManager, including DNS configuration and no competing default route.
- Exit the VPN service when NetworkManager disappears; update the service, runner and CLI together after stopping the old process.
- Bound the server list in its own scroll view, keeping subscription and action controls outside it and preserving scroll/focus during periodic ping updates.
- Preserve actual activation errors instead of requesting profile sync after every runtime failure.
- Add a host installer with backups and an optional activation, TUN-route and HTTPS check.

# 2.2.8

- Recover the selected URI from the root-owned NetworkManager keyfile by connection UUID when NetworkManager strips custom VPN data from the activation payload.
- Validate recovered values against the supported VLESS, VMess, Trojan and Shadowsocks URI schemes.
- Place the dedicated V2Ray tile immediately after the built-in Wi-Fi tile in GNOME Quick Settings.

# 2.2.7

- Deserialize the activation payload with libnm instead of relying only on a hand-written GVariant layout.
- Recursively accept nested or normalized URI fields and fall back to the standard VPN user-name property.
- Store the URI in both WProxy data and the standard VPN property so Netplan round-trips cannot drop it.
- Manage subscriptions and run automatic server pings directly in GNOME Quick Settings.

# 2.2.6

- Fixed activation failing with `Missing WProxy URI`: NetworkManager sends VPN data as `a{ss}`, which the service now reads correctly while retaining `a{sv}` compatibility.
- Refreshed the GNOME Quick Settings UI with a Proxy status card, traffic summary, server latency states and active-server highlighting.
- Added an extension stylesheet and installed it from both the full and Quick Settings installers.

# 2.2.5

- Fixed NetworkManager service startup timeout. `wproxy-service` now uses `org.freedesktop.NetworkManager.wproxy` as its default D-Bus service name when launched without `--bus-name`, matching the normal NetworkManager VPN plugin launch model.
- Added `scripts/install-service-start-fix-only.sh` for a minimal runtime service repair.

# 2.2.5

- Fixed NetworkManager private/user-only profiles; WProxy profiles are now system-wide.
- Added repair script for existing private WProxy connections.

# 2.2.3

- Fixed VPN activation getting stuck on “Working”: NetworkManager Connect now returns immediately and Xray readiness is handled asynchronously.
- Config is emitted only after `wproxy0` is actually ready.
- Added proper VPN Failure signal on runtime failure/timeout.
- Added a 15-second runtime readiness timeout and a 25-second `nmcli` activation timeout.
- Expanded diagnostics for Xray/TUN/NetworkManager runtime state.

## 2.2.3

- Added a per-node ping button directly beside every server in GNOME Quick Settings.
- Clicking a server row connects to that server immediately.
- Added visible `Connecting…`, `…`, latency and timeout states in the Quick Settings list.
- Quick Settings automatically asks for NetworkManager sync through Polkit and retries once when a profile has not been synced yet.
- Kept `Ping all`, subscription update and manager actions.

## 2.2.1
- Fixed missing /usr/bin/wproxyctl after editor-only repair.
- Runtime repair now restores CLI, manager and runner.
- Manager no longer crashes with FileNotFoundError when the CLI is missing.

# Changelog

## 2.2.0
- Fix GNOME Settings integration: WProxy opens a native GTK4 editor from Settings > Network > VPN.
- Keep GTK3 editor for nm-connection-editor.
- Add a direct link to WProxy Manager from the native VPN editor for subscriptions/server management.
- Preserve existing subscription/node syncing and Xray runtime behavior.
- Installer continues to install Xray automatically when missing.

## 2.1.0

- Fixed GNOME Settings VPN editor integration by splitting the GTK-neutral loader from GTK3 and GTK4 editor modules.
- Installer now installs the official XTLS Xray-core when missing on Debian/Ubuntu.
- Added readiness handshake before reporting VPN activation.
- Added explicit physical outbound interface detection for Xray TUN routing.
- Marked `wproxy0` unmanaged by NetworkManager.
- Added `recover-vpn-settings.sh` for repairing systems affected by the older editor.
- Expanded diagnostics for Xray, GTK editor modules and runtime logs.

## 2.0.0

- Replaced the unfinished URI/runtime path with a real Xray TUN configuration generator.
- Added VLESS, VMess, Trojan and Shadowsocks single-link parsing.
- Added plain/base64 subscription import, refresh and quota parsing.
- Fixed NetworkManager keyfile serialization for VPN data items.
- Kept the Xray runner alive for the lifetime of the NetworkManager VPN connection.
- Added pre-route Xray configuration validation.
- Added automatic IPv4/IPv6 TUN routing and loop prevention through Xray's current Linux TUN options.
- Added GTK manager for single configurations and subscriptions.
- Added GNOME 45+ Quick Settings integration with node switching, latency, traffic status and subscription refresh.
- Added diagnostics, uninstall cleanup and safer secret handling in JSON responses used by the desktop UI.
- Updated the NetworkManager editor plugin to GTK3 for compatibility with nm-connection-editor while keeping the standalone manager on GTK4.
