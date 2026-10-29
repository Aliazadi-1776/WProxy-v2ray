# Test coverage

## 2.7.5 reliability regression checks on 2026-10-29

- `make test`: 71 Python cases, 5 C service cases, TypeScript/Vite and Rust checks passed. All three new C lifecycle regressions fail against the previous service and pass with this fix. Runner regressions cover replacement PID files and serialization of shared routing cleanup.
- Fedora 44 (PlasmaNM 6.7.5 / Qt 6.11.2 / KF 6.31) and Arch (PlasmaNM 6.8.2 / Qt 6.12 / KF 6.31): native Plasma plugin build, CTest, container installation and discovery from the actual system Qt plugin directory passed. Factory/editor/auth construction, unchanged VPN settings and masked URI were checked; dynamic dependencies resolved. The 5 C service tests and 20 Python runtime tests also passed on both distributions.
- In Fedora, real KPackage install and upgrade as an unprivileged user passed with verified sources beneath an inaccessible root directory. Update staging exposes only root-owned, read-only widget files; the verified source snapshot remains private.
- Plasma 6.7.5: 45 QML cases passed. Native Breeze light/dark viewer checks cover 100 servers, reaching the final row, fixed footer bounds, connected/error states and isolated KPackage lifecycle. A subprocess regression reproduced reused execution results before the fix; repeated identical requests now each execute once after completion. Manager launch returns without waiting for the GUI to close.
- [Native Windows run 40927771236](https://github.com/Aliazadi-1776/WProxy-v2ray/actions/runs/40927771236) passed actual installed WebView2 UI, two Automatic updates off/on checks through the real IPC/CLI, button-driven Connect/Disconnect, Wintun, DNS, HTTPS and failure rollback. This run precedes the final 2.7.5 version bump and manager visual changes.

- GNOME Shell 51: all 10 layout and 11 production-extension action/lifecycle scenarios passed again with 2.7.5 metadata in private sessions.
- Manager CSS: 14 browser cases passed at 1180×760 and 960×640, including all five pages, connected/disconnected states, long Unicode server names, visible keyboard focus and reduced motion. Primary blue and Disconnect controls have at least 4.7:1 text contrast.

Container Qt tests do not establish a complete KDE/Polkit login session or a live Fedora/Arch VPN session. The initial laptop baseline stopped after an HTTPS endpoint failure while NetworkManager and remembered authorization were still active; that result is not evidence of sudo expiry or a reproduced ten-minute disconnect.

## 2.7.4 verification on 2026-10-29

- Ubuntu host: the real `bash scripts/install.sh --desktop gnome --dry-run` completed its clean Make/C and optimized Tauri builds, embedded-asset check and libnm plugin validation without changing system files. Live full-tunnel preflight, only-empty, bypass-application, only-application and only-domain checks passed with actual saved servers and HTTPS; the original policy/profiles and disconnected state were verified after cleanup. An independent recovery process was authorized before route changes.
- Native Windows Server 2022 runner: [installer run 40767424143](https://github.com/Aliazadi-1776/WProxy-v2ray/actions/runs/40767424143) installed the actual Setup payload, rendered the real WebView2 frontend, called the Tauri/native CLI bridge, clicked the real Connect and Disconnect buttons through the Rust elevation bridge, saved/removed a server through the UI and checked routing layout at default and 960-pixel widths. Screenshots including the connected window and JSON results are available in the run's `WProxy-native-Windows-test-evidence` artifact.
- The same Windows run passed an actual Wintun/default-route/DNS/HTTPS test using a synthetic local Xray proxy with physical-interface egress. Server logs proved both DNS and HTTPS crossed the proxy. An unreachable-server test failed activation, removed the VPN route and restored HTTPS. A detached recovery watchdog was armed before activation; no personal servers or credentials were used.
- GNOME Shell 51: all 10 layout cases and 11 production-extension action/lifecycle scenarios passed in private headless sessions. The action suite uses real asynchronous subprocess execution with a fake CLI, while real Linux networking is covered separately by the host tests above.
- KDE Plasma 6.7.5 / Qt 6.11.2: all 29 QML cases passed with no failures or skips. The real isolated Plasma viewer loaded the unmodified widget with 100 fixture servers, exactly three visible rows, the final row reachable, fixed footer controls and exactly one applet. Temporary KPackage install/upgrade/remove/reinstall also passed.

These results do not cover interactive Windows UAC from a standard-user account, suspend/resume or every desktop/distribution version. Native Windows network tests are intentionally restricted to disposable GitHub Actions runners.

The native UI connection regression first reproduced the Windows busy-state hang: PowerShell `Start-Process -Wait` waited for the persistent Xray descendant after the controller had exited. Version 2.7.4 waits for the controller process handle only. The unchanged connection test now reaches Connected, keeps Xray running and successfully disconnects.

## 2.7.3 desktop, update and authorization regression checks

Connection regressions cover rejecting an open-port server that fails HTTPS, restoring the normal network when the full tunnel fails verification, and executing the real admin helper against an isolated system to check first-connect approval, revocation, invalid arguments and sync failure. Desktop Connect verifies the remote proxy before changing system routes. The Linux helper then verifies system DNS/HTTPS for All traffic and disconnects on failure. Empty Only selected routing is explained instead of claiming all traffic is protected.

The Linux updater regression replaces the caller's downloaded ZIP immediately after hashing and checks the script handed to the installation boundary. Only the verified private snapshot is installed; no real installer is executed by this test.

Source archives must preserve LF line endings for the Linux Makefile and shell entrypoints, including extensionless helpers. An isolated checkout with `core.autocrlf=true` reproduced the old CRLF packaging failure and confirmed that the universal `eol=lf` attribute preserves the tagged bytes. The archive test also checks these files directly.

On the Ubuntu host, 12 of 18 saved nodes passed an isolated real Xray/HTTPS test. A healthy node was then activated through NetworkManager with All traffic: route lookup used `wproxy0` and HTTPS returned 204 in 0.76 seconds. The tunnel was disconnected after the test. These are Linux host results, not physical Windows evidence.

The Linux runner builds the real Tauri/WebKitGTK release executable and the Windows runner builds and launches the real Tauri/WebView2 executable to detect immediate startup exits. The Windows startup smoke test does not assert rendered UI or successful native bridge calls. Frontend checks require the fixed navigation, responsive routing columns, native application picker, explicit empty states and a dependency set without Electron, React, Vue or Svelte. Fastest-server tie/timeout handling and verified update downloads are covered by backend tests. Source checks also require the fixed-operation Linux admin helper and active/local/user-scoped Polkit rule without password storage. The routing suite carries an exact `C:\Program Files\...\firefox.exe` selector through normalization and into the final Xray process rule. These checks complement parser and backend tests; they do not replace a final physical Windows TUN test with a real server.

## 2.6.0 desktop UI, Windows installer and live routing

Python tests cover the full-tunnel compatibility default, bypass and only rule ordering, independent domain/process rules, hostname/IP normalization, Windows executable-name normalization, invalid and oversized input, encoded policy round trips, NetworkManager profile embedding, quota/expiry announcement filtering, same-URI ownership across multiple subscriptions, JSON/mixed subscription extraction, ownership-safe stale-profile selection, corrupt-policy fallback without node loss, and Windows automatic TUN/WFP fields. The C service test verifies bounded `routing64` recovery from a NetworkManager keyfile. Xray's installed `run -test` validation covers generated Linux configs during runtime tests.

Windows GitHub Actions run shared parser, runtime, routing, updater and release tests, compile `wproxyctl.exe`, build and startup-smoke the Tauri application, verify the pinned official Xray archive, compile `Setup.exe`, and publish individual plus aggregate SHA-256 metadata. The current native CI additionally covers rendered UI, real button-driven connection, Wintun, DNS and HTTPS; interactive standard-user UAC, sleep and video playback remain unverified; runtime verification refuses to claim Connected without an adapter, IPv4 default route and HTTPS success.

## 2.3.1 transport correction

See [connection-fix evidence](CONNECTION-FIX-2.3.1.md) for the 2026-09-24 controlled comparison and real proxy HTTPS/YouTube checks. The wire regression uses a loopback fake server and the installed Xray core to assert that a WebSocket Upgrade is actually sent. It is explicitly skipped when Xray is absent. These results must not be described as full-system TUN or video-playback verification.

## Shared backend / GNOME

The 2.2.10 host report dated 2026-09-22 recorded:

- Remote proxy HTTPS: **PASS (204)**.
- NetworkManager activation: **PASS**.
- IPv4 and IPv6 assigned to `wproxy0`.
- Route lookup through `wproxy0`: **PASS**.
- HTTPS through the system tunnel: **PASS (204)**.

Version 2.6.0 retains this Linux TUN algorithm and adds a reversible live smoke test for full-tunnel preflight, only-empty, bypass-application, only-application and only-domain routing. It also regression-tests stable UUID mapping when NetworkManager suffixes duplicate profile names, GNOME 51 layout properties, announcement filtering, subscription-scoped node ownership and ownership-safe stale-profile selection. The original host report is intentionally **not** distributed: diagnostics belong on the local machine.

Automated C/Python tests cover profile lookup, NetworkManager gateway/IP/default-route encoding, compatibility with Xray 26.3.27's TUN fields, outbound-interface binding, endpoint pinning/SNI, gateway-file permissions, and explicit interface/address setup failures. `make test` also checks JavaScript/shell syntax, KDE command quoting and repository assets.

Release checks additionally parse every README Bash example without executing it, compare dependency commands between the English/Persian guides, and build temporary source/widget archives to verify MIT notices, screenshots and exclusion of generated data. These checks do not run APT, pacman, DNF or Zypper and do not certify installation on other distributions. Arch-family, Fedora and openSUSE recipes remain untested end to end.

An isolated GNOME Shell 51 test covers 0/1/3/4/100 rows at normal and 140% text size on a 1366×768 virtual display. It checks construction with GNOME 51's orientation API, three-row allocation, the last row, retained scroll position and fixed Ping/Update/Manager controls. It does not model every physical-device tile or theme.

The separate GNOME action test enables the production extension in a private Shell session and redirects WProxy subprocess calls to an isolated fake CLI. Its 11 scenarios cover server activation/disconnection, ping and duplicate suppression, Ping all/Update/Manager buttons, missing-profile sync and retry, authorization cancellation, subscription add/update/sync, and enable/disable/re-enable without duplicate indicators. It does not invoke the real NetworkManager or Polkit service.

## KDE

Qt Quick tests exercise the actual Popup, Backend and Plasma5Support CommandRunner components. Synthetic server data is used; tests do not modify real subscriptions or call `nm up`.

- Three-row allocation at 0/1/3/4/100 entries.
- Last-server access and preserving scroll position on ping updates.
- Row selection and a footer outside the scrolling viewport.
- Backend status, unchanged-list identity, latency state, invalid JSON and invalid subscription URL handling.
- Actual command execution with quoted shell metacharacters/newlines and nonzero exit propagation.
- Missing-profile synchronization/retry, Polkit cancellation, subscription update/sync ordering, and duplicate ping prevention, using a fake executor (no system changes).

KPackage install, upgrade, removal and reinstallation succeeded in a temporary user data directory. The real Plasma 6.7.5 viewer and desktop containment loaded the unmodified widget with 100 synthetic servers and captured the last three rows with fixed footer controls. `tests/kde-host-smoke.sh` reproduces this test with the Plasma SDK and desktop-containment dependencies installed. It uses private XDG directories and a separate session bus; it does not modify the real panel.

Tested development runtime: Qt **6.11.2** with Plasma libraries **6.7.5**. Qt Test reported **29 passed, 0 failed**, including compilation of the actual Plasma entrypoint with its real imports. The offscreen/extracted runtime emitted theme/platform/registration warnings; these are not represented as a full desktop pass. Test tools were extracted into an isolated development directory, not installed over the desktop.

**Not yet verified:** a complete KDE login with panel/tray placement, Polkit authentication, NetworkManager connect/disconnect and suspend/network-change behavior. GNOME-version declarations beyond the tested session are also not a guarantee of compatibility.

## Run locally

```bash
make all
make desktop-check
make test
bash scripts/install.sh --desktop preserve --dry-run
bash scripts/test-kde.sh
bash tests/kde-host-smoke.sh
bash tests/headless-smoke.sh
bash tests/headless-actions.sh
```

The KDE and GNOME tests need their corresponding desktop/test dependencies. CI runs the portable build, unit and source-release checks; it does not claim to exercise the host's root TUN or physical network.

For a real connection check on an existing GNOME install:

```bash
bash scripts/apply-fix.sh --test
```

That operation updates WProxy, temporarily stops its connection, tests actual saved nodes, and may leave a successful VPN connected. It needs sudo. Keep `verification.txt` private.

For a reversible split-routing check that never prints the public IP or server credentials:

```bash
python3 scripts/live-routing-smoke.py --confirm --timeout 20
```

The script temporarily changes the current routing policy, tests real HTTPS paths with two different processes and hostnames, and restores the original policy and NetworkManager profiles in a `finally` block.
