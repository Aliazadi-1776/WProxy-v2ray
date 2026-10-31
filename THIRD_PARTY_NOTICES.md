# Third-party notices

## Independently executed VPN cores

WProxy runs the following unmodified official executables as separate processes;
their licenses do not replace the WProxy source license. Core archives are pinned
by release, platform and SHA-256 in `scripts/core-versions.json`.

- sing-box 1.14.4, copyright SagerNet / nekohasekai, GPL-3.0-or-later.
  [Corresponding upstream source and build definitions](https://github.com/SagerNet/sing-box/tree/v1.14.4),
  [source archive](https://github.com/SagerNet/sing-box/archive/refs/tags/v1.14.4.tar.gz).
  Its original additional naming/association notice is retained in
  `scripts/core-licenses/sing-box-LICENSE`.
- Mihomo 1.19.33, copyright MetaCubeX contributors, GNU GPL version 3.
  [Corresponding upstream source and build definitions](https://github.com/MetaCubeX/mihomo/tree/v1.19.33),
  [source archive](https://github.com/MetaCubeX/mihomo/archive/refs/tags/v1.19.33.tar.gz).
  The complete GNU GPL v3 text is retained in `scripts/core-licenses/mihomo-LICENSE`
  and applies to both GPL-covered executables.

Original core notices and version/source references are copied into the Windows
installer's `licenses` directory and `/usr/share/licenses/wproxy-cores` on Linux.
Redistributors must preserve these notices and provide the corresponding source
alongside their executable downloads as required by the applicable GPL terms.

Clash YAML is parsed with [PyYAML 6.0.3](https://github.com/yaml/pyyaml/tree/6.0.3)
(MIT); it is a system Python package on Linux and included by PyInstaller on
Windows. Xray-core and Wintun remain distributed with their original notices in
the existing Windows package.

## KDE plasma-nm interface headers

The optional native Plasma VPN plugin dynamically links the distribution's
`libplasmanm_editor`. Two unmodified interface headers from KDE plasma-nm
v6.7.5 are included in `plasma-nm/compat` under LGPL-2.1; their original
copyright notices, source attribution and license text are retained there.
No KDE implementation is bundled. These private interfaces require a matching
Plasma ABI and the native factory/widget test before installation.

## sushTun

The compact Windows navigation, color palette, and related interface direction
in WProxy are adapted from the open-source
[sushTun](https://github.com/soroushdeimi/sushTun) desktop client.

MIT License

Copyright (c) 2026 soroushdeimi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
