"""Documentation and clean source/widget archive regression checks."""
import importlib.util
import json
import os
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


def read_utf8(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ReleaseTests(unittest.TestCase):
    def test_linux_admin_helper_is_narrow_and_never_stores_passwords(self):
        helper = read_utf8("scripts/wproxy-admin")
        policy = read_utf8("data/io.github.aliazadi1776.wproxy.policy")
        installer = read_utf8("scripts/install.sh")
        for operation in ("authorize)", "revoke)", "sync)", "up)", "down)", "update)"):
            self.assertIn(operation, helper)
        self.assertIn("subject.active && subject.local", helper)
        self.assertIn("auth_admin_keep", policy)
        self.assertIn("io.github.aliazadi1776.wproxy.admin", policy)
        self.assertIn("/usr/libexec/wproxy-admin", installer)
        self.assertNotIn("org.freedesktop.policykit.exec\"", helper)
        self.assertNotRegex(helper.lower(), r"password\s*=")

    def test_linux_installer_has_a_non_mutating_build_dry_run(self):
        installer = read_utf8("scripts/install.sh")
        self.assertIn("--dry-run)", installer)
        self.assertIn("WProxy installer dry-run: PASS", installer)
        self.assertIn("No system files, NetworkManager profiles, packages, or desktop extensions were changed.", installer)
        self.assertLess(installer.index("WProxy installer dry-run: PASS"), installer.index("Creating backup:"))

    def test_tauri_desktop_exposes_primary_workflows(self):
        source = read_utf8("desktop/src/main.ts")
        for label in (
            "Servers", "Add connection", "Subscriptions", "Routing",
            "Choose application", "Test latency", "Use fastest", "Connect", "Remove",
        ):
            if label == "Use fastest":
                self.assertIn("fastest", source)
            else:
                self.assertIn(label, source)
        self.assertNotIn("Add typed path", source)
        self.assertIn("Quick connect", source)
        self.assertIn('open({ multiple: false, directory: false', source)

    def test_tauri_navigation_is_responsive_and_has_empty_states(self):
        source = read_utf8("desktop/src/main.ts")
        styles = read_utf8("desktop/src/styles.css")
        config = json.loads(read_utf8("desktop/src-tauri/tauri.conf.json"))
        for token in (
            "Main navigation", "No servers yet", "Split routing", "Automatic updates",
            "data-page", "routing-columns", "empty-state",
        ):
            self.assertIn(token, source)
        self.assertIn("minmax(0, 1fr)", styles)
        self.assertIn("prefers-reduced-motion", styles)
        self.assertEqual(config["app"]["windows"][0]["minWidth"], 960)
        self.assertEqual(config["app"]["windows"][0]["minHeight"], 640)
        workflow = read_utf8(".github/workflows/windows-release.yml")
        self.assertIn("cargo build --release", workflow)
        self.assertIn("Smoke test Tauri startup on Windows", workflow)
        self.assertIn("Start-Process -FilePath", workflow)

    def test_tauri_frontend_has_no_heavy_ui_framework(self):
        package = json.loads(read_utf8("desktop/package.json"))
        packages = set(package.get("dependencies", {})) | set(package.get("devDependencies", {}))
        self.assertFalse(packages.intersection({"electron", "react", "react-dom", "vue", "svelte"}))
        self.assertIn("@tauri-apps/api", packages)
        self.assertIn("vite", packages)

    def test_tauri_bridge_limits_commands_and_elevates_tunnel_only(self):
        source = read_utf8("desktop/src-tauri/src/lib.rs")
        for token in (
            "valid_ctl_args", "elevated_windows_ctl", "linux_admin", "wproxy-admin",
            "tunnel_status", "set_linux_authorization", "install_update",
        ):
            self.assertIn(token, source)
        self.assertNotIn("plugin-shell", read_utf8("desktop/package.json"))

    def test_tauri_auto_update_is_opt_in_verified_and_installed_by_native_bridge(self):
        source = read_utf8("desktop/src/main.ts")
        self.assertIn("state.preferences.auto_update", source)
        self.assertIn("runAutomaticUpdate", source)
        self.assertIn('"update", "download", "--json", "--platform"', source)
        self.assertIn('invoke<CliOutput>("install_update"', source)

    def test_repair_scripts_keep_the_tauri_manager(self):
        for name in ("scripts/repair-runtime.sh", "scripts/repair-gnome-vpn-editor.sh"):
            source = read_utf8(name)
            self.assertIn("make desktop", source)
            self.assertIn("desktop/src-tauri/target/release/wproxy-desktop", source)
            self.assertNotIn("install -Dm755 manager/wproxy-manager.py /usr/bin/wproxy-manager", source)

    def test_kde_widget_installer_repairs_duplicate_panel_icons(self):
        installer = read_utf8("scripts/install-kde-widget.sh")
        self.assertIn("kde-dedupe-widget.js", installer)
        self.assertIn("org.kde.PlasmaShell.evaluateScript", installer)
        self.assertIn("keeps one WProxy icon per panel", installer)

    def test_release_publishes_update_checksum_manifest(self):
        workflow = read_utf8(".github/workflows/windows-release.yml")
        self.assertIn("Create release checksum manifest", workflow)
        self.assertGreaterEqual(workflow.count("dist/SHA256SUMS"), 3)

    def test_desktop_managers_keep_linux_integration_and_tauri_shell(self):
        linux = read_utf8("manager/wproxy-manager.py")
        desktop = read_utf8("desktop/src/main.ts")

        for token in (
            "navigation-rail", "connection-card", "material-list", "Add connection",
            "self.window.set_titlebar(header)", "self.uri_entry.set_visibility(False)",
            "Gio.AppInfo.get_all()", "Choose application…", "all traffic stays direct",
        ):
            self.assertIn(token, linux)
        self.assertNotIn("root.append(header)", linux)

        for token in ("connection-hero", "server-list", "routing-layout", "Choose application"):
            self.assertIn(token, desktop)

    def test_gnome_51_layout_uses_orientation_property(self):
        source = read_utf8("gnome-extension/wproxy@wrench.local/extension.js")
        self.assertNotIn("vertical:", source)
        self.assertGreaterEqual(source.count("Clutter.Orientation.VERTICAL"), 2)

    @unittest.skipIf(os.name == "nt", "README Bash syntax is validated by the Linux job")
    def test_readme_shell_examples_parse_without_executing(self):
        for name in ("README.md", "README.fa.md"):
            blocks = re.findall(r"```bash\n(.*?)```", read_utf8(name), re.S)
            self.assertTrue(blocks, name)
            for index, block in enumerate(blocks):
                with self.subTest(readme=name, block=index):
                    result = subprocess.run(
                        ["bash", "-n"], input=block, text=True, capture_output=True
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_dependency_commands_match_between_languages(self):
        def commands(name):
            text = read_utf8(name).replace("\\\n", " ")
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
                self.assertEqual(
                    archive.read(prefix + "THIRD_PARTY_NOTICES.md"),
                    (ROOT / "THIRD_PARTY_NOTICES.md").read_bytes(),
                )
                for name in ("README.md", "README.fa.md", ".github/workflows/ci.yml",
                             ".github/workflows/windows-release.yml",
                             "docs/screenshots/gnome-quick-settings.png", "docs/screenshots/manager.png",
                             "desktop/package.json", "desktop/package-lock.json",
                             "desktop/src/main.ts", "desktop/src/styles.css",
                             "desktop/src-tauri/Cargo.toml", "desktop/src-tauri/Cargo.lock",
                             "desktop/src-tauri/src/lib.rs", "desktop/src-tauri/tauri.conf.json",
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
