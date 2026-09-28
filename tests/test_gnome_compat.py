"""GNOME 49/50/51 extension and installer compatibility checks."""
import json
import os
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
EXTENSION = ROOT / "gnome-extension/wproxy@wrench.local"
VERSION_CHECK = ROOT / "scripts/check-gnome-version.sh"


class GnomeCompatibilityTests(unittest.TestCase):
    def run_version_check(self, version):
        env = os.environ.copy()
        env["WPROXY_GNOME_SHELL_VERSION"] = version
        return subprocess.run(
            ["sh", VERSION_CHECK], text=True, capture_output=True, env=env
        )

    def test_metadata_targets_exact_supported_versions(self):
        metadata = json.loads((EXTENSION / "metadata.json").read_text())
        self.assertEqual(metadata["uuid"], "wproxy@wrench.local")
        self.assertEqual(metadata["version"], 11)
        self.assertEqual(metadata["shell-version"], ["49", "50", "51"])

    def test_removed_gnome_51_vertical_property_is_not_used(self):
        source = (EXTENSION / "extension.js").read_text()
        self.assertIsNone(re.search(r"\bvertical\s*:", source))
        self.assertEqual(
            source.count("orientation: Clutter.Orientation.VERTICAL"), 2
        )
        self.assertNotRegex(source, r"async\s+disable\s*\(")

    def test_supported_versions_are_accepted(self):
        for version in ("GNOME Shell 49.7", "GNOME Shell 50", "GNOME Shell 51.0"):
            with self.subTest(version=version):
                result = self.run_version_check(version)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), version.split()[2].split(".")[0])

    def test_unsupported_or_invalid_versions_are_rejected(self):
        for version in ("GNOME Shell 48.9", "GNOME Shell 52.0", "not-a-version"):
            with self.subTest(version=version):
                result = self.run_version_check(version)
                self.assertEqual(result.returncode, 2)
                self.assertTrue(result.stderr.strip())

    def test_installers_check_version_and_verify_copied_files(self):
        full = (ROOT / "scripts/install.sh").read_text()
        quick = (ROOT / "scripts/install-quick-settings-only.sh").read_text()
        upgrade = (ROOT / "scripts/apply-fix.sh").read_text()
        self.assertIn("check-gnome-version.sh", full)
        self.assertIn("--check", full)
        self.assertIn("cmp ", full)
        self.assertIn("check-gnome-version.sh", quick)
        self.assertIn("cmp ", quick)
        self.assertIn("check-gnome-version.sh", upgrade)
        self.assertIn("cmp ", upgrade)


if __name__ == "__main__":
    unittest.main()
