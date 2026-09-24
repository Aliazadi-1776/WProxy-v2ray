#!/usr/bin/env python3
"""Offline source-package checks; no access to a user's WProxy store."""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
widget = root / "kde-plasmoid/org.wproxy.WProxy"
metadata = json.loads((widget / "metadata.json").read_text())
assert metadata["KPlugin"]["Id"] == widget.name
assert metadata["KPlugin"]["Version"] == "2.3.1"
assert metadata["KPlugin"]["License"] == "MIT"
license_text = (root / "LICENSE").read_text()
assert license_text.startswith("MIT License\n")
assert (widget / "LICENSE").read_text() == license_text
assert metadata["X-Plasma-API-Minimum-Version"] == "6.0"
assert metadata["KPackageStructure"] == "Plasma/Applet"
assert (widget / "contents/ui/main.qml").is_file()
assert json.loads((root / "gnome-extension/wproxy@wrench.local/metadata.json").read_text())["version"] == 10

for readme in (root / "README.md", root / "README.fa.md"):
    text = readme.read_text()
    assert "[MIT](LICENSE)" in text or "[MIT License](LICENSE)" in text
    for command in ("sudo apt-get install", "sudo pacman -Syu", "sudo dnf install", "sudo zypper install"):
        assert command in text, (readme.name, command)
    for desktop in ("gnome", "kde", "none"):
        assert f"bash scripts/install.sh --desktop {desktop}" in text
    images = re.findall(r"!\[[^\]]*\]\(([^)]+)\)", text)
    assert len(images) == 2, f"Both supplied screenshots must be in {readme.name}"
    for target in re.findall(r"\]\(([^)]+)\)", text):
        if "://" in target or target.startswith("#"):
            continue
        assert (readme.parent / target.split("#")[0]).is_file(), target
    for target in images:
        assert (readme.parent / target).read_bytes().startswith(b"\x89PNG\r\n\x1a\n")

for source in list((root / "scripts").glob("*.sh")) + list((root / "cli").glob("*.py")):
    text = source.read_text()
    assert "/home/wrench/" not in text, source
    assert "/tmp/codex-clipboard" not in text, source
print("Release metadata, MIT notices, distro guides, README links, screenshots and portable paths: PASS")
