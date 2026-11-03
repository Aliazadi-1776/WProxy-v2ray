# Security review: Linux connection hotfix

## Scope

The review covers dynamic Linux TUN address selection, propagation into the core configuration, and the shared privileged connection path used by Manager and GNOME Quick Settings.

## Findings

- The GNOME extension invokes the fixed `/usr/libexec/wproxy-admin` path; it does not execute a helper path supplied by settings or subscription data.
- The privileged helper accepts only a 16-character lowercase hexadecimal node identifier before handing it to `wproxyctl`.
- `WPROXY_TUN_IPV4` is generated from a fixed candidate list in the root runner. The Python adapter independently rejects values that are not the first host of a private IPv4 `/30`.
- The runner quotes every selected address and network passed to `ip`; no `eval`, shell interpolation of subscription content, or arbitrary command execution was introduced.
- Repository secret-pattern review found no tracked private keys, API keys, or OpenAI-style tokens outside test and documentation fixtures.
- `npm audit --omit=dev --audit-level=high` reported zero vulnerabilities.

## Residual checks

No Rust advisory scanner is installed in the development environment, so the locked Cargo graph was compiled but not checked against the RustSec database. Fedora SELinux and Windows runtime acceptance require their respective target systems and are not inferred from the Ubuntu target result.
