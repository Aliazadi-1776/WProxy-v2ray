# Test coverage

## 2.7.8 Linux recovery checks on 2026-10-30

The targeted profile load/combined modification added in 2.7.7 crashed the installed NetworkManager 1.58.1 with an assertion in `nm-settings-utils.c:103`, before VPN activation. Its service restart interrupted Wi-Fi. That Linux path and its new helper/CLI actions have been removed. The Linux helper and 85 shared functions, including sync, activation, disconnect, routing/config generation and HTTPS verification, match 2.7.6. Manager now handles Linux switching with an explicit active-connection condition: disconnect, verify the selected server, then invoke the existing connection helper. The SVG logo and progress feedback remain.

The full Python suite passed 84 tests after rollback. Metadata/routing checks passed after the 2.7.8 version bump; the optimized native Tauri build and production-asset check passed. Regression tests require the established full reload and separate routing/permission modifications, and reject the removed targeted-sync/Linux-connect arguments. Thirteen browser fixture scenarios passed: Linux down → verify → up ordering, no redundant initial disconnect, no activation after failed disconnect, disconnected state after a failed replacement probe, same-server no-op, the unchanged single-command Windows path and SVG/layout checks. Browser fixture tests do not replace native networking.

The installed 2.7.6 CLI and scoped helper were restored through the verified update installer and checked byte for byte against the known-good source before native Manager verification.

The actual optimized native Manager 2.7.8 then passed Connect A → Switch B → Switch A using AT-SPI button clicks with that restored backend, without a mocked bridge or manual Disconnect. All three selected-node/TUN/approval checks and six HTTPS probes passed. NetworkManager MainPID 199202 and its process birth remained unchanged across 613 monitoring samples. The independent guard restored the original `only` policy, profiles, disconnected state and saved data/preferences. Observed GUI completion was 14.4 seconds initially, 22.8 seconds A → B and 11.0 seconds B → A; this is correctness evidence, not a speed improvement claim.

[Native Windows 2.7.8 run 41088447551](https://github.com/Aliazadi-1776/WProxy-v2ray/actions/runs/41088447551) and [shared build/test run 41088447354](https://github.com/Aliazadi-1776/WProxy-v2ray/actions/runs/41088447354) passed at `3ee99b5`. Actual installed UI switching took 7.277 seconds; Wintun, DNS, HTTPS, rollback and restoration passed. The SVG and 2.7.8 version were visually checked. All payload hashes and all 134 source archive members matched that tested commit.

After stable publication, the actual installed Manager's automatic updater installed 2.7.8. CLI, service and helper matched the released source; automatic updates and remembered authorization stayed enabled. The exact installed-GUI rerun stopped before any connection click because the accessibility application reference became unavailable, despite the Manager process remaining alive with no crash log. Its cleanup restored the original state, and this rerun is not counted as a passed GUI test. The separate native three-click proof above remains the GUI verification result.

A separate actual installed-backend smoke then passed the fixed helper sequence up A → automated down → up B, with both real remote servers, the correct selected node/TUN/remembered approval and four HTTPS 204 responses. NetworkManager MainPID 199202 and process birth stayed unchanged across 372 monitoring samples. Helper activation took 11.108 and 11.774 seconds; disconnect took 0.547 seconds. The independent guard restored the original policy, profiles, disconnected state, saved data and preferences; installed CLI/helper hashes were unchanged. This is backend-only verification and is not presented as an installed-GUI rerun.

## 2.7.7 verification and installed Linux failure

Pre-publication checks passed 90 Python tests, C/build checks and the optimized Linux installer dry-run. [Native Windows run 41055336222](https://github.com/Aliazadi-1776/WProxy-v2ray/actions/runs/41055336222) passed actual installed UI Connect/Switch/Disconnect, Wintun, DNS, HTTPS and rollback; its switch took 7.271 seconds. The 134 source archive members matched commit `233e2a7`.

The Linux source candidate also passed real A → B → A activation and a failed-server rollback with ten HTTPS 204 responses. However, it delegated profile synchronization to the old installed helper and therefore did **not** exercise the new targeted-sync operation. The subsequent installed 2.7.7 test failed on its first targeted profile modification, before any activation or HTTPS check; NetworkManager's assertion/restart was captured in the system journal. Its cleanup restored the original policy, profiles, disconnected state and unchanged nodes/subscriptions/preferences. Neither the candidate run nor the Windows results establish a successful installed Linux 2.7.7 result.

## 2.7.6 DNS readiness regression checks on 2026-10-30

The installed 2.7.5 tunnel stayed active for 780 seconds with all 54 HTTPS probes successful and remembered authorization valid. Its first reconnect then failed the single immediate system HTTPS check. Guarded follow-up captured curl error 6 (DNS resolution failure) immediately after activation, with both default and IPv4 requests. Authorization remained valid; all tests restored the original policy/profiles and preserved nodes/subscriptions.

The bounded readiness retry candidate then passed an initial activation and three reconnects. A separate 780-second run passed all 27 samples (54 HTTPS 204 responses), maintained the selected NetworkManager profile, tunnel route and remembered approval throughout, and passed three further reconnects with both HTTPS probes successful. The final restore verified the original `only` policy, disconnected state and unchanged nodes/subscriptions. The candidate used the normal user's source CLI for activation and the installed scoped helper for sync/cleanup; installed files were not modified for this candidate test.

The three regressions fail against the previous verifier and pass with the fix: recovery after initial DNS failure; rollback with the actual reason after all attempts fail; rejection of HTTP 200 instead of the required 204. The Python suite now has 73 passing tests. The tunnel algorithm and authorization policy are unchanged by this patch.

The actual installed Linux Automatic updates checkbox upgraded 2.7.4 to 2.7.5. The downloaded ZIP matched the checksum-verified CI archive byte for byte; installed CLI, runner and admin helper matched source. Manager idle measurement on this host: 0% CPU across 10 seconds, about 192.5 MiB proportional memory (three frontend processes; RSS sums shared pages and was about 386 MiB). This is a local idle measurement, not a guarantee for active traffic or other machines.

With that preference enabled, the installed Manager then downloaded and installed stable 2.7.6 through its real automatic updater; no terminal installation command was used. The installed CLI matched the released source, and the service and reopened Manager reported 2.7.6. Automatic updates and remembered approval remained enabled. The installed scoped administrator helper passed an initial activation and three disconnect/reconnect cycles, with both HTTPS endpoints returning 204 after every activation and remembered approval valid before and after every operation. The original `only` routing policy, profiles, saved servers/subscriptions and disconnected state were restored.

[The 2.7.6 native Windows installer run](https://github.com/Aliazadi-1776/WProxy-v2ray/actions/runs/41033172492) passed the installed WebView2 UI, actual Connect/Disconnect controls, Wintun, DNS, HTTPS and failure rollback. [The tagged build/test run](https://github.com/Aliazadi-1776/WProxy-v2ray/actions/runs/41033172494) also passed. These checks use a disposable Windows Server 2022 administrator runner; they do not cover standard-user UAC or suspend/resume.

[The real Windows automatic-upgrade run](https://github.com/Aliazadi-1776/WProxy-v2ray/actions/runs/41047284446) passed a separately installed, checksum-pinned published 2.7.4 baseline upgraded to 2.7.6 by clicking its Automatic updates checkbox once. The test observed exactly one real download request and native installation request, verified the downloaded Setup against the published SHA256SUMS, waited for Setup to exit, and checked the CLI at the original installation path. Reopening the installed Manager showed 2.7.6 with automatic updates enabled and the existing server configuration preserved. No update responses or installation calls were simulated; no VPN routes were changed by this upgrade test.

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
# 2.8.0 focused multi-engine verification

Verification was intentionally limited to the new behavior:

- 17 focused selection/import/switch regressions passed.
- Python/shell/native service, TypeScript/Vite and Rust/Tauri build checks passed.
- One real local process exercise passed a request while switching in order: sing-box 1.14.4 → Xray 26.9.30 → Mihomo 1.19.33.
- The tagged v2.8.0 Windows run passed the installed Tauri UI/elevation bridge, one-click server replacement, Wintun/default-route/DNS/HTTPS path, synthetic-proxy access and failed-server rollback.

The local multi-core smoke uses loopback proxies and does not modify system routes. The tagged Windows run is the native Windows TUN check and retains downloadable evidence in GitHub Actions. Linux privileged TUN remains a separate on-machine runtime check; schema validation alone is never reported as a live connection.
