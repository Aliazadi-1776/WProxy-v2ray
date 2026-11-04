# Installed Linux connection verification — 2026-11-04

Scope: the installed Linux controller, admin helper, NetworkManager VPN service
and Xray on the user's laptop (NetworkManager 1.58.1). The measurements below
precede source publication; no release artifact is certified by this report.

## Reproduced failures

- An earlier full-tunnel YouTube request timed out after 20 seconds with only
  about 60 KB received. A successful empty HTTPS probe was insufficient evidence
  that normal browsing worked.
- Switching through the installed helper failed with `Unknown reason` and
  restored the previous connection.
- Saving a freshly loaded VPN profile with `nmcli connection modify` triggered
  NetworkManager's `nm-settings-utils.c:103` assertion and an ABRT/restart. This
  reproduced the reported message-bus-disconnected error.

## Changes under verification

- Connect syncs only the requested profile and no longer persistently modifies
  profiles after loading/reloading them.
- The VPN service prefers routing from the root-owned WProxy keyfile over an
  older cached routing dictionary in the Connect payload.
- The privileged connection path waits for plugin teardown as well as interface
  removal before starting a replacement.
- Manager refreshes connection state on Servers and other visible pages, and
  performs status reads outside its UI thread.
- Browser design preview is labelled and cannot report a simulated successful
  connection.
- A trial bulk-download requirement was removed from Quick Connect; full-site
  transfer checks remain in the live diagnostic script.

## Installed-path results after the final installation

These use `/usr/bin/wproxyctl` and `/usr/libexec/wproxy-admin`, with a temporary
All traffic policy. The script disconnects and restores the original policy.

| Scenario | Result |
| --- | --- |
| Connect to first saved server | PASS, 3.1 s |
| Receive complete YouTube homepage on first server | PASS, 995,831 characters, 1.7 s |
| Switch to a second server through the installed helper | PASS, 3.3 s |
| Receive complete YouTube homepage after switch | PASS, 1,001,393 characters, 1.8 s |
| Exact Quick Connect selection command used by the UI | PASS, verified response 657 ms |
| Connect to the automatically selected server | PASS, 3.0 s |
| Receive complete YouTube homepage on the automatically selected server | PASS, 1,011,119 characters, 1.9 s |
| NetworkManager after final installation and checks | Same process; no new assertion/restart |
| Restore original routing policy | PASS, Only selected; original application list preserved |
| Installed CLI/service/manager match built artifacts | PASS, SHA-256 equality |

A subsequent user-requested **Bypass selected** check excluded the actual
ChatGPT/Codex executables before connection. A separately excluded diagnostic
process retained its direct exit address, while an ordinary curl process used
a different VPN exit address. Connection completed in 0.9 s, YouTube returned
HTTP 200 with 1,003,907 bytes in 2.65 s, and its JPEG thumbnail returned HTTP 200
with 15,921 bytes in 2.93 s. ICMP returned four replies with no loss; the tunnel
ICMP RTT is not used as a measurement of remote YouTube latency. NetworkManager
did not restart. At the user's request this final connection was left active,
with only ChatGPT/Codex bypassed; no private configuration links or public IP
addresses are included in the published report.

Focused verification: 27 Python checks and 5 C service checks passed, frontend
production build passed, Rust release compiled, and embedded production assets
passed validation. A separate debug Rust test rebuild was stopped; it is not
reported as a passing test.

Before source publication, the shared Python suite covered 104 checks: 103
passed in the sandbox, and the actual loopback WebSocket handshake check passed
separately on the host after sandbox socket creation was denied. The 5 C checks,
frontend build, release/package metadata, Fedora guide shell syntax and relative
links passed. The source telemetry reader additionally filters systemd-run
wrappers so their RSS is not mistaken for the core's RSS; a synthetic process
fixture covers that selection. No new live Fedora or Windows result is claimed.

## Limits

The YouTube checks downloaded and checked the complete homepage through the
installed full tunnel. Browser rendering and video playback were not verified:
browser automation was disabled in Work settings. Some other saved servers
also stalled while fetching YouTube through a local HTTP proxy without TUN;
the results above do not certify every saved server. Windows, Fedora and KDE
were not live-tested in this verification session.

Re-run the installed-path checks:

```sh
python3 scripts/live-installed-smoke.py --confirm --quick --temporary-all
python3 scripts/live-installed-smoke.py --confirm --node NODE_A --switch-node NODE_B --temporary-all
```
