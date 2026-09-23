"""Documentation and clean source/widget archive regression checks."""
import importlib.util
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("release_builder", ROOT / "scripts/build-release.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class ReleaseTests(unittest.TestCase):
    def test_readme_shell_examples_parse_without_executing(self):
        for name in ("README.md", "README.fa.md"):
            blocks = re.findall(r"```bash\n(.*?)```", (ROOT / name).read_text(), re.S)
            self.assertTrue(blocks, name)
            for index, block in enumerate(blocks):
                with self.subTest(readme=name, block=index):
                    result = subprocess.run(
                        ["bash", "-n"], input=block, text=True, capture_output=True
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_dependency_commands_match_between_languages(self):
        def commands(name):
            text = (ROOT / name).read_text().replace("\\\n", " ")
            return [
                " ".join(line.split())
                for line in text.splitlines()
                if line.startswith(("sudo apt-get ", "sudo pacman ", "sudo dnf ", "sudo zypper "))
            ]
        english = commands("README.md")
        self.assertGreaterEqual(len(english), 8)
        self.assertEqual(english, commands("README.fa.md"))

    def test_archives_include_license_assets_and_no_generated_data(self):
        with tempfile.TemporaryDirectory(prefix="wproxy-release-test-") as directory:
            BUILDER.build(Path(directory))
            with zipfile.ZipFile(Path(directory) / "WProxy-2.3.0-GitHub.zip") as archive:
                self.assertIsNone(archive.testzip())
                prefix = "WProxy-2.3.0/"
                self.assertEqual(archive.read(prefix + "LICENSE"), (ROOT / "LICENSE").read_bytes())
                for name in ("README.md", "README.fa.md", ".github/workflows/ci.yml",
                             "docs/screenshots/gnome-quick-settings.png", "docs/screenshots/manager.png"):
                    self.assertEqual(archive.read(prefix + name), (ROOT / name).read_bytes())
                for name in archive.namelist():
                    path = Path(name)
                    self.assertTrue(name.startswith(prefix), name)
                    self.assertFalse(BUILDER.EXCLUDED.intersection(path.parts), name)
                    self.assertNotIn(path.suffix, {".pyc", ".pyo", ".so", ".o", ".log", ".nmconnection", ".pid"})
                    self.assertNotIn("dist", path.parts)
            with zipfile.ZipFile(Path(directory) / "WProxy-2.3.0-Plasma6.plasmoid") as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(archive.read("LICENSE"), (ROOT / "LICENSE").read_bytes())
                self.assertIn("metadata.json", archive.namelist())
                self.assertIn("contents/ui/main.qml", archive.namelist())


if __name__ == "__main__":
    unittest.main()
