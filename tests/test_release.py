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
    def test_linux_admin_helper_is_narrow_and_never_stores_passwords(self):
        helper = (ROOT / "scripts/wproxy-admin").read_text()
        policy = (ROOT / "data/io.github.aliazadi1776.wproxy.policy").read_text()
        installer = (ROOT / "scripts/install.sh").read_text()
        for operation in ("authorize)", "revoke)", "sync)", "up)", "down)", "update)"):
            self.assertIn(operation, helper)
        self.assertIn("subject.active && subject.local", helper)
        self.assertIn("auth_admin_keep", policy)
        self.assertIn("io.github.aliazadi1776.wproxy.admin", policy)
        self.assertIn("/usr/libexec/wproxy-admin", installer)
        self.assertNotIn("org.freedesktop.policykit.exec\"", helper)
        self.assertNotRegex(helper.lower(), r"password\s*=")

    def test_windows_manager_handles_unicode_engine_failures_without_closing(self):
        source = (ROOT / "windows/WProxy.ps1").read_text()
        self.assertIn("$env:PYTHONIOENCODING = 'utf-8'", source)
        self.assertIn("$ErrorActionPreference = 'Continue'", source)
        self.assertIn("Application]::add_ThreadException", source)
        self.assertIn("WProxy is still running", source)

    def test_windows_manager_exposes_app_style_primary_workflows(self):
        source = (ROOT / "windows/WProxy.ps1").read_text()
        for label in (
            "Servers", "Add connection", "Subscriptions", "Routing",
            "Choose application...", "Ping all", "Connect", "Remove",
        ):
            self.assertIn(label, source)
        self.assertNotIn("Add typed path", source)
        self.assertIn("Secure connection", source)
        self.assertIn("$nodeList.Add_DoubleClick", source)

    def test_windows_navigation_is_dpi_safe_and_has_an_empty_state(self):
        source = (ROOT / "windows/WProxy.ps1").read_text()
        self.assertNotIn("System.Windows.Forms.TabControl", source)
        self.assertNotIn("System.Windows.Forms.TabPage", source)
        for token in (
            "NavigationRail", "PageHost", "function Show-Page", "$script:NavButtons",
            "ServersEmptyState", "No servers yet", "Show-Page 'add'",
            "$LayoutSmokeTest", "Windows navigation rail collapsed during layout.",
        ):
            self.assertIn(token, source)
        workflow = (ROOT / ".github/workflows/windows-release.yml").read_text()
        self.assertIn("-LayoutSmokeTest", workflow)

    def test_windows_idle_refresh_stops_while_hidden(self):
        source = (ROOT / "windows/WProxy.ps1").read_text()
        self.assertIn("$timer.Interval = 15000", source)
        self.assertIn("$timer.Stop()", source)
        self.assertNotIn("$timer.Interval = 3000", source)
        self.assertNotRegex(source, r"\$timer\.Start\(\)\s*\n\[System\.Windows\.Forms\.Application\]::add_ThreadException")

    def test_windows_shell_exposes_simple_vpn_actions(self):
        source = (ROOT / "windows/WProxy.ps1").read_text()
        for token in (
            "Quick connect", "Automatic updates", "VPN CONNECTION",
            "Start-AutomaticUpdate", "node', 'best'", "Accent = [System.Drawing.Color]::FromArgb(10, 132, 255)",
        ):
            self.assertIn(token, source)

    def test_release_publishes_update_checksum_manifest(self):
        workflow = (ROOT / ".github/workflows/windows-release.yml").read_text()
        self.assertIn("Create release checksum manifest", workflow)
        self.assertGreaterEqual(workflow.count("dist/SHA256SUMS"), 3)

    def test_desktop_managers_share_a_clear_material_app_shell(self):
        linux = (ROOT / "manager/wproxy-manager.py").read_text()
        windows = (ROOT / "windows/WProxy.ps1").read_text()

        for token in (
            "navigation-rail", "connection-card", "material-list", "Add connection",
            "self.window.set_titlebar(header)", "self.uri_entry.set_visibility(False)",
            "Gio.AppInfo.get_all()", "Choose application…", "all traffic stays direct",
        ):
            self.assertIn(token, linux)
        self.assertNotIn("root.append(header)", linux)

        for token in (
            "WProxy.SmoothButton", "WProxy.SmoothPanel", "SmoothingMode.AntiAlias",
            "NavigationRail", "PageHost", "OnAccent", "Online", "Secure connection",
            "Windows routing actions are clipped",
        ):
            self.assertIn(token, windows)

    def test_gnome_51_layout_uses_orientation_property(self):
        source = (ROOT / "gnome-extension/wproxy@wrench.local/extension.js").read_text()
        self.assertNotIn("vertical:", source)
        self.assertGreaterEqual(source.count("Clutter.Orientation.VERTICAL"), 2)

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
            with zipfile.ZipFile(Path(directory) / "WProxy-2.7.0-GitHub.zip") as archive:
                self.assertIsNone(archive.testzip())
                prefix = "WProxy-2.7.0/"
                self.assertEqual(archive.read(prefix + "LICENSE"), (ROOT / "LICENSE").read_bytes())
                for name in ("README.md", "README.fa.md", ".github/workflows/ci.yml",
                             ".github/workflows/windows-release.yml",
                             "docs/screenshots/gnome-quick-settings.png", "docs/screenshots/manager.png",
                             "windows/WProxy.ps1", "windows/WProxy.iss",
                             "windows/install-windows.ps1", "icons/wproxy.ico"):
                    self.assertEqual(archive.read(prefix + name), (ROOT / name).read_bytes())
                for name in archive.namelist():
                    path = Path(name)
                    self.assertTrue(name.startswith(prefix), name)
                    self.assertFalse(BUILDER.EXCLUDED.intersection(path.parts), name)
                    self.assertNotIn(path.suffix.lower(), {".pyc", ".pyo", ".so", ".o", ".log", ".nmconnection", ".pid", ".exe", ".dll"})
                    self.assertNotIn("dist", path.parts)
            with zipfile.ZipFile(Path(directory) / "WProxy-2.7.0-Plasma6.plasmoid") as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(archive.read("LICENSE"), (ROOT / "LICENSE").read_bytes())
                self.assertIn("metadata.json", archive.namelist())
                self.assertIn("contents/ui/main.qml", archive.namelist())


if __name__ == "__main__":
    unittest.main()
