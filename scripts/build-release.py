#!/usr/bin/env python3
"""Build clean GitHub source and Plasma widget archives; never include user data."""
import argparse
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "2.3.1"
SOURCE_ENTRIES = [
    "README.md", "README.fa.md", "CHANGELOG.md", "SECURITY.md", "CONTRIBUTING.md", "LICENSE",
    "Makefile", ".gitignore", ".gitattributes", ".github", "docs", "cli", "data",
    "examples", "gnome-extension", "kde-plasmoid", "icons", "manager", "plugin",
    "scripts", "service", "tests",
]
EXCLUDED = {"__pycache__", ".git", "store.json", "verification.txt", "xray.json", "gateway"}


def source_files(base):
    for path in sorted(base.rglob("*")) if base.is_dir() else [base]:
        if not path.is_file() or path.is_symlink():
            continue
        if EXCLUDED.intersection(path.relative_to(ROOT).parts):
            continue
        if path.suffix in {".pyc", ".pyo", ".log", ".so", ".o", ".nmconnection", ".pid"}:
            continue
        yield path


def build(output):
    license_text = (ROOT / "LICENSE").read_bytes()
    widget = ROOT / "kde-plasmoid/org.wproxy.WProxy"
    if (widget / "LICENSE").read_bytes() != license_text:
        raise ValueError("Widget and project license notices must match")
    output.mkdir(parents=True, exist_ok=True)
    source_zip = output / f"WProxy-{VERSION}-GitHub.zip"
    widget_zip = output / f"WProxy-{VERSION}-Plasma6.plasmoid"
    # Rebuilding a chosen release output is explicit; never touch the source tree.
    with zipfile.ZipFile(source_zip, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in SOURCE_ENTRIES:
            for path in source_files(ROOT / name):
                archive.write(path, f"WProxy-{VERSION}/{path.relative_to(ROOT).as_posix()}")
    with zipfile.ZipFile(widget_zip, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in source_files(widget):
            archive.write(path, path.relative_to(widget).as_posix())
    for path in (source_zip, widget_zip):
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
        print(path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    build(parser.parse_args().output.resolve())
