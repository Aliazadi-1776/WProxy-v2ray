# Security notes

- Subscription URLs and proxy URIs often contain credentials. Never include the local store, generated configs, NetworkManager profiles, or raw diagnostics in an issue or commit.
- The current local JSON store is permission-restricted, not encrypted. System VPN profiles and runtime configs are also sensitive.
- Installation and NetworkManager profile synchronization need elevated privileges; the panel UIs do not run as root. TUN creation is performed by the root service.
- **Remember authorization** never saves a sudo password. It installs a per-UID Polkit rule that requires a local, active session and authorizes only `/usr/libexec/wproxy-admin`; that helper accepts the fixed `sync`, `up`, `down`, verified `update`, `authorize` and `revoke` operations. Disable the option to remove the rule.
- Automatic updates are opt-in. WProxy accepts only stable-version release asset names, downloads over HTTPS and verifies SHA-256 against the release-wide `SHA256SUMS` before starting either installer. This detects corruption and asset mix-ups; it is not a substitute for signed release provenance or Windows Authenticode.
- Review installer scripts, including the official Xray installation step when the core is absent, before executing them.
- Qt/KDE command arguments are individually shell-quoted. Do not replace this with raw string concatenation of node names, URLs or command arguments.
- A successful TCP ping is not proof that a proxy works or protects all traffic. Run an end-to-end HTTPS/TUN check.
- This release is not a security audit, a kill switch or an anonymity guarantee. DNS, IPv6, reconnect, suspend and network-change behavior should be tested for the target environment.
- Routing mode `all` is the backward-compatible default. `bypass` and `only` intentionally send some traffic outside the VPN; review the list and reconnect before assuming protection.
- Windows stores its generated Xray configuration under `%LOCALAPPDATA%\WProxy\run`; it contains proxy credentials. The installer pins and verifies the official Xray archive and connection startup checks adapter/route/HTTPS state, but a complete real-host DNS/IPv6/WFP/suspend leak test is still required.

No project vulnerability-reporting address has been configured yet. Until a private reporting channel exists, do not publish credentials or exploitation details in public issues.
