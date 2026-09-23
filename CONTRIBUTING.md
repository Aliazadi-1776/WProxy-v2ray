# Contributing / publishing this snapshot

This directory is the repository root. Upload its contents—not the outer ZIP file—to a GitHub repository, including the hidden `.github`, `.gitignore` and `.gitattributes` entries. No GitHub account or remote URL has been assumed. WProxy source is distributed under the [MIT License](LICENSE); preserve its copyright and permission notice when redistributing it.

## Checks before a change

```bash
make all
make test
bash scripts/test-kde.sh          # with the Plasma/Qt test dependencies
bash tests/headless-smoke.sh     # with GNOME Shell 51
```

Use synthetic server names and credentials in tests. Never commit real subscription URLs, share links, generated Xray configs, connection profiles, diagnostic logs or personal connection reports. Include only screenshots you are authorized to publish and inspect them for sensitive information.

Desktop tests and shared backend tests are separate. Do not describe a passing Qt fixture as a verified connection in a complete KDE session, or a TCP ping as a full VPN health check.

## Build source / widget packages

```bash
python3 scripts/build-release.py
```

This creates `dist/WProxy-2.3.0-GitHub.zip` and `dist/WProxy-2.3.0-Plasma6.plasmoid` from a source allowlist. Generated binaries, caches, profiles and logs are excluded. Release artifacts can be attached to a GitHub Release instead of committed into the source repository.
