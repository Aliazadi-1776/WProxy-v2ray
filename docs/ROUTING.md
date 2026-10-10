# Site and application routing

WProxy 2.5.1 stores one routing policy in the existing private `store.json`. The field is additive: stores created by older releases load as `all`, so upgrading does not change which traffic uses the VPN.

## Modes

| Mode | Listed sites/apps | Everything else |
| --- | --- | --- |
| `all` | VPN | VPN |
| `bypass` | Direct, outside VPN | VPN |
| `only` | VPN | Direct, outside VPN |

Private, loopback and link-local networks stay direct in every mode. `all` is the default and the fallback when an old or malformed policy is read. Selecting `bypass` or `only` is a privacy decision: some traffic intentionally does not use the proxy.

Open `wproxy-manager` and use the **Routing** tab, or use the CLI:

```bash
wproxyctl routing show
wproxyctl routing mode bypass
wproxyctl routing domain add youtube.com
wproxyctl routing domain add 'https://example.org/path'
wproxyctl routing app add firefox
wproxyctl routing app add /usr/bin/curl
sudo wproxyctl nm sync
```

The manager requests Polkit permission and synchronizes every WProxy NetworkManager profile after a change. CLI changes are local until `sudo wproxyctl nm sync` succeeds. Disconnect and reconnect an active tunnel to load the new Xray configuration.

To return to the full-tunnel default without deleting saved lists:

```bash
wproxyctl routing mode all
sudo wproxyctl nm sync
```

## Matching and validation

- A site entry accepts a hostname or URL. WProxy stores only the normalized hostname and matches it plus its subdomains.
- Literal IPv4/IPv6 addresses are accepted. Credentials in URLs, invalid hostnames, control characters and lists above 256 entries are rejected.
- An application entry is a case-sensitive process name or absolute executable path. On Windows, use **Choose apps…** to enumerate running programs or browse for an EXE; exact paths are preferred. Backslashes are normalized to forward slashes and a name-only `.exe` suffix is removed to match Xray semantics.
- Domain and application entries are separate Xray rules, so they form a union; an item does not need to match both.
- Domain routing uses Xray protocol sniffing. Applications using encrypted DNS, unsupported protocols or IP-only connections may not expose a hostname. Use application routing or an IP entry where appropriate.

The policy is encoded into every generated NetworkManager profile. The root VPN service accepts only a bounded base64url value and passes it to the runner through a root-only runtime file. Xray rejects the generated configuration before the tunnel is marked ready.

## فارسیِ کوتاه

حالت `all` همه‌چیز را از VPN می‌فرستد و پیش‌فرض امن است. در `bypass` سایت‌ها و برنامه‌های داخل لیست مستقیم می‌روند. در `only` فقط موارد داخل لیست از VPN می‌روند و بقیه مستقیم هستند. بعد از تغییر با CLI حتماً `sudo wproxyctl nm sync` و سپس قطع/وصل را انجام بده. تب Routing در برنامه sync را خودکار انجام می‌دهد.
