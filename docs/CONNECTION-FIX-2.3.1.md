# Connection fix in 2.3.1

## Cause

The converter used `streamSettings.method` to select a transport. Xray 26.3.27 reads `streamSettings.network` and defaults to TCP when it is absent. An unknown `method` key was silently ignored, even though a configuration syntax check succeeded. Consequently WebSocket links were attempted as raw TCP connections.

This follows the [Xray 26.3.27 StreamConfig implementation](https://github.com/XTLS/Xray-core/blob/v26.3.27/infra/conf/transport_internet.go). The fix emits `network` for every supported transport. It also preserves TCP HTTP Host/path options, avoids decoding URI query values twice, and rejects unknown/removed transports instead of silently substituting TCP.

## Verification on 2026-09-24

On the same Linux host, using its existing Xray **26.3.27** and saved subscription entries:

| Check | Before | After |
| --- | --- | --- |
| HTTPS through a loopback SOCKS proxy, nine entries | 2 passed, 7 failed | 8 passed, 1 timed out |
| Controlled three-WebSocket comparison, changing only `method` to `network` | All three failed | All three returned HTTP 204 |
| YouTube homepage through two corrected WebSocket proxies | Not recorded | Both returned HTTP 200 |

No credentials, server addresses, subscription URLs or raw runtime logs are included in this report. The one timed-out entry remains a failed test; this release does not claim every entry works.

These probes used real remote proxies but **did not change system routes**. They prove proxy HTTPS, not a complete new NetworkManager/TUN test, DNS-leak audit, browser/video playback test, or a KDE-session test. Existing 2.2.10 TUN evidence is documented separately in [TESTING.md](TESTING.md).

## Regression coverage

`make test` covers the emitted transport key, VLESS/VMess WebSocket, encoded paths and early data, TCP HTTP camouflage, and unsupported transport/security rejection. When Xray is installed, an additional loopback test observes the real HTTP WebSocket Upgrade request rather than trusting JSON validation. Without Xray, that test is explicitly skipped.

## Upgrade and check

From the extracted **2.3.1** directory, as your normal desktop user:

```bash
# Choose only one, according to your desktop:
bash scripts/install.sh --desktop gnome
# Or:
bash scripts/install.sh --desktop kde
```

An existing installed 2.2.10/2.3.0 copy will not change just because the source ZIP is updated. The full installer refreshes `/usr/bin/wproxyctl` (used by the TUN runner) and a pre-existing `~/.local/bin/wproxyctl` too. On GNOME log out/in to reload the panel version.

To test only one saved server without changing routes:

```bash
wproxyctl node list
python3 scripts/test-proxy-https.py --node NODE_ID
python3 scripts/test-proxy-https.py --node NODE_ID --url https://www.youtube.com/ --expect-code 200 --timeout 20
```

Replace `NODE_ID` with an ID from the list. This does not update subscriptions, install software or connect the whole system to a VPN. Keep reports that contain your node IDs local.
