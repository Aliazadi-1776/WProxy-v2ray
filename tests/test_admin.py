"""Run the real fixed-operation helper against an isolated fake system."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.name == "nt", "Polkit helper runs on Linux")
class AdminTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.log = self.base / "commands"
        self.rules = self.base / "rules"
        self.script("id", "printf '0\\n'")
        self.script("getent", "printf 'desktop:x:1000:1000:Desktop:/home/desktop:/bin/sh\\n'")
        ctl = self.script("ctl", 'printf "%s:%s\\n" "$SUDO_USER" "$*" >> "$ADMIN_TEST_LOG"\nif [ "${ADMIN_TEST_FAIL_SYNC:-}" = 1 ] && [ "$2" = sync ]; then exit 8; fi')
        source = (ROOT / "scripts/wproxy-admin").read_text()
        source = source.replace("CTL=/usr/bin/wproxyctl", f"CTL={ctl}")
        source = source.replace("RULE_DIR=/etc/polkit-1/rules.d", f"RULE_DIR={self.rules}")
        self.helper = self.base / "helper"
        self.helper.write_text(source)
        self.environment = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}",
                            "PKEXEC_UID": "1000", "ADMIN_TEST_LOG": str(self.log)}

    def script(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)
        return path

    def run_helper(self, *args, **environment):
        return subprocess.run(["sh", str(self.helper), *args], env={**self.environment, **environment},
                              capture_output=True, text=True)

    def test_first_connect_remembers_only_wproxy_for_active_local_user(self):
        result = self.run_helper("up-remember", "0123456789abcdef")
        self.assertEqual(result.returncode, 0, result.stderr)
        rule = (self.rules / "49-wproxy-1000.rules").read_text()
        self.assertIn('action.id == "io.github.aliazadi1776.wproxy.admin"', rule)
        self.assertIn('subject.active && subject.local && subject.user == "desktop"', rule)
        self.assertEqual(self.log.read_text().splitlines(), [
            "desktop:nm sync", "desktop:nm up 0123456789abcdef --verify",
        ])
        self.assertEqual(self.run_helper("revoke").returncode, 0)
        self.assertFalse((self.rules / "49-wproxy-1000.rules").exists())

    def test_normal_connect_does_not_create_persistent_approval(self):
        self.assertEqual(self.run_helper("up", "0123456789abcdef").returncode, 0)
        self.assertFalse(self.rules.exists())

    def test_invalid_input_cannot_create_rule_or_start_command(self):
        for args in (("up-remember", "bad"), ("up-remember", "0123456789abcdef", "extra")):
            self.assertNotEqual(self.run_helper(*args).returncode, 0)
        self.assertFalse(self.rules.exists())
        self.assertFalse(self.log.exists())

    def test_failed_sync_never_activates_stale_profile(self):
        result = self.run_helper("up", "0123456789abcdef", ADMIN_TEST_FAIL_SYNC="1")
        self.assertEqual(result.returncode, 8)
        self.assertEqual(self.log.read_text().splitlines(), ["desktop:nm sync"])


if __name__ == "__main__":
    unittest.main()
