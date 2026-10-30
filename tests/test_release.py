"""Documentation and clean source/widget archive regression checks."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import tomllib
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
        for operation in ("authorize)", "revoke)", "sync)", "up|up-remember)", "down)", "update)"):
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

    def test_tauri_release_embeds_assets_instead_of_loading_the_dev_server(self):
        cargo = tomllib.loads(read_utf8("desktop/src-tauri/Cargo.toml"))
        self.assertIn("custom-protocol", cargo["features"]["default"])
        self.assertEqual(cargo["features"]["custom-protocol"], ["tauri/custom-protocol"])
        checker = "tests/check-tauri-production.py"
        self.assertIn(checker, read_utf8("Makefile"))
        self.assertIn(checker, read_utf8(".github/workflows/windows-release.yml"))

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

    @unittest.skipIf(os.name == "nt", "Linux desktop installer")
    def test_update_preserves_both_installed_desktop_integrations(self):
        source = read_utf8("scripts/install.sh")
        function = re.search(r"^select_desktop_integrations\(\) \{\n.*?^\}", source, re.M | re.S).group(0)
        with tempfile.TemporaryDirectory(prefix="wproxy-desktop-selection-") as directory:
            fixture = Path(directory)
            function = function.replace("/usr/share/", str(fixture / "usr/share") + "/")
            function = function.replace("/usr/lib", str(fixture / "usr/lib"))
            home = fixture / "home"
            (home / ".local/share/gnome-shell/extensions/wproxy@wrench.local").mkdir(parents=True)
            kde = home / ".local/share/plasma/plasmoids/org.wproxy.WProxy"
            kde.mkdir(parents=True)
            command = function + '\nDESKTOP=preserve\nTARGET_HOME="$1"\nselect_desktop_integrations\nprintf "%s %s\\n" "$INSTALL_GNOME" "$INSTALL_KDE"\n'
            result = subprocess.run(["sh", "-eu", "-c", command, "installer-test", str(home)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "1 1")

    @unittest.skipIf(os.name == "nt", "Linux root-to-user desktop installer")
    def test_kde_update_stages_public_read_only_files_outside_private_sources(self):
        source = read_utf8("scripts/install.sh")
        function = re.search(r"    install_kde_widget\(\) \{\n.*?^    \}", source, re.M | re.S).group(0)
        with tempfile.TemporaryDirectory(prefix="wproxy-private-update-") as directory:
            fixture = Path(directory)
            project = fixture / "private/source"
            scripts = project / "scripts"
            widget = project / "kde-plasmoid/org.wproxy.WProxy"
            scripts.mkdir(parents=True)
            widget.mkdir(parents=True)
            (fixture / "private").chmod(0o700)
            (scripts / "install-kde-widget.sh").write_text("# fixture installer\n")
            (scripts / "kde-dedupe-widget.js").write_text("// fixture deduplication\n")
            (widget / "metadata.json").write_text('{"KPlugin":{"Id":"org.wproxy.WProxy"}}')
            fakebin = fixture / "bin"
            fakebin.mkdir()
            (fakebin / "id").write_text("#!/bin/sh\nprintf '0\\n'\n")
            log = fixture / "stage.json"
            (fakebin / "runuser").write_text(f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
stage = pathlib.Path(sys.argv[-1]).parent.parent
assert str(stage).startswith('/tmp/wproxy-kde-install.')
for item in [stage, *stage.rglob('*')]:
    mode = item.stat().st_mode
    assert not mode & 0o022, (item, oct(mode))
    assert mode & 0o004, (item, oct(mode))
    if item.is_dir(): assert mode & 0o001, (item, oct(mode))
assert (stage / 'scripts/kde-dedupe-widget.js').is_file()
assert (stage / 'kde-plasmoid/org.wproxy.WProxy/metadata.json').is_file()
pathlib.Path(os.environ['STAGE_LOG']).write_text(json.dumps({'stage': str(stage)}))
''')
            for executable in fakebin.iterdir():
                executable.chmod(0o755)
            command = function + f'\nPROJECT_DIR={shlex.quote(str(project))}\nTARGET_USER=fixture\nTARGET_UID=1000\ninstall_kde_widget\n'
            result = subprocess.run(["sh", "-eu", "-c", command], text=True, capture_output=True,
                                    env={**os.environ, "PATH": str(fakebin) + os.pathsep + os.environ["PATH"], "STAGE_LOG": str(log)})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(Path(json.loads(log.read_text())["stage"]).exists())
            self.assertTrue((scripts / "install-kde-widget.sh").is_file())

    def test_kde_widget_is_idle_until_opened_or_used(self):
        backend = read_utf8("kde-plasmoid/org.wproxy.WProxy/contents/ui/Backend.qml")
        runner = read_utf8("kde-plasmoid/org.wproxy.WProxy/contents/ui/CommandRunner.qml")
        main = read_utf8("kde-plasmoid/org.wproxy.WProxy/contents/ui/main.qml")

        self.assertNotIn("interval: 5000", backend)
        self.assertNotIn("Component.onCompleted", backend)
        self.assertIn("onExpandedChanged: if (expanded) controller.refresh()", main)
        self.assertIn("running: runner.activeJobs > 0", runner)
        self.assertNotIn("running: true", runner)

    def test_release_publishes_update_checksum_manifest(self):
        workflow = read_utf8(".github/workflows/windows-release.yml")
        self.assertIn("Create release checksum manifest", workflow)
        self.assertGreaterEqual(workflow.count("dist/SHA256SUMS"), 3)
        version = re.search(
            r'^VERSION = "([^"]+)"$', read_utf8("scripts/build-release.py"), re.M
        ).group(1)
        self.assertIn(f"WPROXY_VERSION: '{version}'", workflow)

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
            with zipfile.ZipFile(Path(directory) / "WProxy-2.7.8-GitHub.zip") as archive:
                self.assertIsNone(archive.testzip())
                prefix = "WProxy-2.7.8/"
                self.assertEqual(archive.read(prefix + "LICENSE"), (ROOT / "LICENSE").read_bytes())
                self.assertEqual(
                    archive.read(prefix + "THIRD_PARTY_NOTICES.md"),
                    (ROOT / "THIRD_PARTY_NOTICES.md").read_bytes(),
                )
                for name in ("Makefile", "scripts/wproxy-admin", "service/wproxy-xray-runner",
                             "scripts/install.sh", "cli/wproxyctl.py"):
                    self.assertNotIn(b"\r", archive.read(prefix + name), name)
                for name in ("README.md", "README.fa.md", ".github/workflows/ci.yml",
                             ".github/workflows/windows-release.yml",
                             "docs/screenshots/gnome-quick-settings.png", "docs/screenshots/manager.png",
                             "desktop/package.json", "desktop/package-lock.json",
                             "desktop/src/main.ts", "desktop/src/styles.css",
                             "desktop/src-tauri/Cargo.toml", "desktop/src-tauri/Cargo.lock",
                             "desktop/src-tauri/src/lib.rs", "desktop/src-tauri/tauri.conf.json",
                             "windows/WProxy.ps1", "windows/WProxy.iss",
                             "windows/install-windows.ps1", "icons/wproxy.ico",
                             "plasma-nm/CMakeLists.txt", "plasma-nm/wproxy.cpp", "plasma-nm/metadata.json",
                             "plasma-nm/compat/vpnuiplugin.h", "plasma-nm/compat/settingwidget.h",
                             "plasma-nm/compat/COPYING.LGPL-2.1", "plasma-nm/compat/README.md"):
                    self.assertEqual(archive.read(prefix + name), (ROOT / name).read_bytes())
                for name in archive.namelist():
                    path = Path(name)
                    self.assertTrue(name.startswith(prefix), name)
                    self.assertFalse(BUILDER.EXCLUDED.intersection(path.parts), name)
                    self.assertNotIn(path.suffix.lower(), {".pyc", ".pyo", ".so", ".o", ".log", ".nmconnection", ".pid", ".exe", ".dll"})
                    self.assertNotIn("dist", path.parts)
            with zipfile.ZipFile(Path(directory) / "WProxy-2.7.8-Plasma6.plasmoid") as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(archive.read("LICENSE"), (ROOT / "LICENSE").read_bytes())
                self.assertIn("metadata.json", archive.namelist())
                self.assertIn("contents/ui/main.qml", archive.namelist())


if __name__ == "__main__":
    unittest.main()
