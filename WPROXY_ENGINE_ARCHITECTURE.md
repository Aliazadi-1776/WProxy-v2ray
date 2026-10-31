# WProxy multi-engine architecture

Status: implemented v1 baseline, 2026-10-31. Existing connections and desktop integrations remain compatible.

## Boundaries

Tauri UI → allowlisted Rust bridge → shared wproxyctl → engine adapter → one owned core process → platform TUN.

The existing Python controller already serves the Manager, GNOME, KDE and privileged NetworkManager runner. Keep engine selection there rather than duplicating it in Rust. Rust remains the typed, asynchronous desktop boundary; a later language migration must preserve this contract.

## Configuration and selection

Keep the exact original URI, JSON or YAML in the store. Native documents use a versioned `wproxy-config://` envelope (base64url JSON containing format and original text), allowing existing NetworkManager profiles to carry the same immutable input. Never normalize one native core document into another core's format.

URI adapters generate a runtime document. Native adapters deep-copy the supplied document and replace only WProxy-owned ingress, local control listeners, TUN and platform routing. Keep outbounds, proxy groups, providers and protocol-specific options. Unsupported combinations fail explicitly, never downgrade security or silently bypass routing.

Candidates are platform-aware: ordinary supported URIs prefer sing-box on Linux; Windows keeps the proven Xray/Wintun path for classic VLESS/VMess/Trojan/Shadowsocks links and retains sing-box as fallback. REALITY/Vision/XHTTP and Xray-specific settings require Xray. Native sing-box JSON stays sing-box; native Xray JSON stays Xray; Clash YAML/JSON stays Mihomo. Installed binary version and the core's own validator determine actual compatibility, not just a protocol table. Missing/incompatible cores produce an actionable error before starting a tunnel. No automatic fallback that discards options.

Import accepts links, native JSON/YAML and subscription bodies through the same detector. File import uses a native file chooser. QR images decode into this same import path; image decoding must be available before advertising it.

## Binary management

Three official runtimes only: SagerNet/sing-box, XTLS/Xray-core, MetaCubeX/mihomo. Pin OS/architecture-specific releases and SHA-256 values. Download over HTTPS, verify before extracting, install with non-user-writable ownership for elevated execution, retain licenses. Do not accept binaries specified by an imported document. Installed core inventory exposes engine, version and availability without launching a connection. Core updates travel with a verified WProxy release, not unverified latest downloads at connect time.

## Lifecycle and switching

One lock owns the active network tunnel. Resolve server endpoints and validate the prospective runtime config before changing routes. Stop the old core, await its TUN cleanup, then start the selected new core. Never run two active TUN cores. A temporary loopback probe has no TUN or system proxy and is terminated before starting the real core.

Linux keeps the working NetworkManager VPN lifecycle, gateway metadata, physical interface binding, scoped Polkit helper and remembered authorization. Do not reintroduce targeted nmcli profile modifications that crashed NetworkManager in 2.7.7. Windows keeps its UAC boundary, Wintun readiness, HTTPS verification and previous-connection recovery. PID ownership checks recognize the selected executable; stop only WProxy's own process.

## TUN, DNS and routing

Linux NetworkManager owns system routes and DNS; engine auto-route is disabled. The existing service still reports wproxy0 and 172.19.0.1/30. Bind core egress to the physical interface to prevent routing loops. Windows engine TUN owns routes/DNS and uses wproxy. Native profile providers may resolve several gateways; physical-interface binding must cover every outbound/provider.

Translate WProxy all/bypass/only rules in each adapter, including application paths, without silently ignoring rules. Native Clash rules and groups stay intact; explicitly unsupported overlays fail before connection. System proxy remains unchanged when using TUN. Loopback probes expose only a local HTTP proxy.

## Frontend contract and monitoring

Keep `node list`, `node add/import`, `node verify`, `tunnel up/down` and status JSON. Add selected-engine metadata to node rows/status and an inventory command. Never return raw configs or credentials to lists/logs. Long operations remain asynchronous and buttons remain disabled while switching.

Existing status and on-demand HTTPS latency checks remain the first monitoring layer. Automatic failover/recovery and continuous traffic telemetry require explicit opt-in, bounded retries, generation ownership and a real failure signal; they must not reset a healthy VPN or create a busy polling loop. These are follow-up capabilities, not prerequisites for basic multi-engine connections.

## Errors and verification

Report import format errors, missing core, rejected config, failed startup, failed HTTPS and cleanup/recovery distinctly. Core diagnostics may contain credentials: keep detailed logs private and show bounded/redacted summaries. No arbitrary shell execution from a profile.

Verification is intentionally small: one focused adapter/import regression check, actual native-core validation, and a loopback connection/switch exercise across the three engines. Native Windows TUN and KDE/GNOME session coverage must be stated separately from Linux config validation. Never count monitoring samples as separate tests or claim an unavailable environment passed.

## Official references

- [sing-box configuration](https://sing-box.sagernet.org/configuration/)
- [sing-box TUN](https://sing-box.sagernet.org/configuration/inbound/tun/)
- [Xray-core](https://github.com/XTLS/Xray-core)
- [Mihomo configuration](https://wiki.metacubex.one/en/config/)
- [Mihomo TUN](https://wiki.metacubex.one/en/config/inbound/tun/)
