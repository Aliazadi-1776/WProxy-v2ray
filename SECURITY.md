# Security notes

- Subscription URLs and proxy URIs often contain credentials. Never include the local store, generated configs, NetworkManager profiles, or raw diagnostics in an issue or commit.
- The current local JSON store is permission-restricted, not encrypted. System VPN profiles and runtime configs are also sensitive.
- Installation and NetworkManager profile synchronization need elevated privileges; the panel UIs do not run as root. TUN creation is performed by the root service.
- Review installer scripts, including the official Xray installation step when the core is absent, before executing them.
- Qt/KDE command arguments are individually shell-quoted. Do not replace this with raw string concatenation of node names, URLs or command arguments.
- A successful TCP ping is not proof that a proxy works or protects all traffic. Run an end-to-end HTTPS/TUN check.
- This release is not a security audit, a kill switch or an anonymity guarantee. DNS, IPv6, reconnect, suspend and network-change behavior should be tested for the target environment.

No project vulnerability-reporting address has been configured yet. Until a private reporting channel exists, do not publish credentials or exploitation details in public issues.
