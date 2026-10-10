# Test coverage

## 2.5.1 Windows installer, multi-subscription ownership and routing

Python tests cover the full-tunnel compatibility default, bypass and only rule ordering, independent domain/process rules, hostname/IP normalization, Windows executable-name normalization, invalid and oversized input, encoded policy round trips, NetworkManager profile embedding, quota/expiry announcement filtering, same-URI ownership across multiple subscriptions, JSON/mixed subscription extraction, ownership-safe stale-profile selection, corrupt-policy fallback without node loss, and Windows automatic TUN/WFP fields. The C service test verifies bounded `routing64` recovery from a NetworkManager keyfile. Xray's installed `run -test` validation covers generated Linux configs during runtime tests.

Windows GitHub Actions run shared tests, compile `wproxyctl.exe`, execute its version check, verify the pinned official Xray archive, parse the PowerShell frontend, compile `Setup.exe`, and publish a SHA-256 artifact. A real Windows UAC/Wintun/DNS/sleep/YouTube test is still required; runtime verification now refuses to claim Connected without an adapter, IPv4 default route and HTTPS success.

## 2.3.1 transport correction

See [connection-fix evidence](CONNECTION-FIX-2.3.1.md) for the 2026-09-24 controlled comparison and real proxy HTTPS/YouTube checks. The wire regression uses a loopback fake server and the installed Xray core to assert that a WebSocket Upgrade is actually sent. It is explicitly skipped when Xray is absent. These results must not be described as full-system TUN or video-playback verification.

## Shared backend / GNOME

The 2.2.10 host report dated 2026-09-22 recorded:

- Remote proxy HTTPS: **PASS (204)**.
- NetworkManager activation: **PASS**.
- IPv4 and IPv6 assigned to `wproxy0`.
- Route lookup through `wproxy0`: **PASS**.
- HTTPS through the system tunnel: **PASS (204)**.

Version 2.5.1 retains this Linux TUN algorithm and routing behavior. It also regression-tests GNOME 51 layout properties, announcement filtering, subscription-scoped node ownership and ownership-safe stale-profile selection. The original host report is intentionally **not** distributed: diagnostics belong on the local machine.

Automated C/Python tests cover profile lookup, NetworkManager gateway/IP/default-route encoding, compatibility with Xray 26.3.27's TUN fields, outbound-interface binding, endpoint pinning/SNI, gateway-file permissions, and explicit interface/address setup failures. `make test` also checks JavaScript/shell syntax, KDE command quoting and repository assets.

Release checks additionally parse every README Bash example without executing it, compare dependency commands between the English/Persian guides, and build temporary source/widget archives to verify MIT notices, screenshots and exclusion of generated data. These checks do not run APT, pacman, DNF or Zypper and do not certify installation on other distributions. Arch-family, Fedora and openSUSE recipes remain untested end to end.

An isolated GNOME Shell 51 test covers 0/1/3/4/100 rows at normal and 140% text size on a 1366×768 virtual display. It checks construction with GNOME 51's orientation API, three-row allocation, the last row, retained scroll position and fixed Ping/Update/Manager controls. It does not model every physical-device tile or theme.

## KDE

Qt Quick tests exercise the actual Popup, Backend and Plasma5Support CommandRunner components. Synthetic server data is used; tests do not modify real subscriptions or call `nm up`.

- Three-row allocation at 0/1/3/4/100 entries.
- Last-server access and preserving scroll position on ping updates.
- Row selection and a footer outside the scrolling viewport.
- Backend status, unchanged-list identity, latency state, invalid JSON and invalid subscription URL handling.
- Actual command execution with quoted shell metacharacters/newlines and nonzero exit propagation.
- Missing-profile synchronization/retry, Polkit cancellation, subscription update/sync ordering, and duplicate ping prevention, using a fake executor (no system changes).

KPackage installation succeeded in a temporary user data directory. A full plasmoidviewer desktop could not be exercised without the host's missing desktop-containment package; this is not reported as a successful full-session test.

Tested development runtime: Qt **6.11.2** with Plasma libraries **6.7.5**. Qt Test reported **29 passed, 0 failed**, including compilation of the actual Plasma entrypoint with its real imports. The offscreen/extracted runtime emitted theme/platform/registration warnings; these are not represented as a full desktop pass. Test tools were extracted into an isolated development directory, not installed over the desktop.

**Not yet verified:** a complete KDE login with panel/tray placement, Polkit authentication, NetworkManager connect/disconnect and suspend/network-change behavior. GNOME-version declarations beyond the tested session are also not a guarantee of compatibility.

## Run locally

```bash
make all
make test
bash scripts/test-kde.sh
bash tests/headless-smoke.sh
```

The KDE and GNOME tests need their corresponding desktop/test dependencies. CI runs the portable build, unit and source-release checks; it does not claim to exercise the host's root TUN or physical network.

For a real connection check on an existing GNOME install:

```bash
bash scripts/apply-fix.sh --test
```

That operation updates WProxy, temporarily stops its connection, tests actual saved nodes, and may leave a successful VPN connected. It needs sudo. Keep `verification.txt` private.
