"""Keep Linux on its proven full-sync NetworkManager command sequence."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wproxy_sync", ROOT / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ctl)


@unittest.skipIf(os.name == "nt", "NetworkManager profile sync runs on Linux")
class LinuxFullSyncTests(unittest.TestCase):
    def test_full_sync_uses_separate_routing_and_permission_updates(self):
        nodes = [{"id": "0123456789abcdef", "name": "First", "uri": "trojan://test@example.com:443"},
                 {"id": "fedcba9876543210", "name": "Second", "uri": "trojan://test@example.net:443"}]
        store = {"nodes": nodes, "routing": {"mode": "only", "domains": ["example.org"], "apps": ["firefox"]}}
        success = SimpleNamespace(returncode=0, stdout="", stderr="")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            untouched = directory / "unrelated.nmconnection"
            untouched.write_text("preserve me")
            with patch.object(ctl, "require_root"), patch.object(ctl, "original_user", return_value=SimpleNamespace(pw_uid=1000)), \
                    patch.object(ctl, "Path", return_value=directory), \
                    patch.object(ctl, "loaded_owned_wproxy_uuids", return_value=[]), \
                    patch.object(ctl, "run", return_value=success) as command, contextlib.redirect_stdout(io.StringIO()):
                ctl.nm_sync(store)
                expected = [["nmcli", "connection", "reload"]]
                for node in nodes:
                    profile_uuid = ctl.deterministic_uuid(node["id"])
                    expected.extend([
                        ["nmcli", "connection", "modify", "uuid", profile_uuid, "+vpn.data", f"routing64={ctl.encode_routing_policy(store['routing'])}"],
                        ["nmcli", "connection", "modify", "uuid", profile_uuid, "connection.permissions", ""],
                    ])
                expected.append(["nmcli", "connection", "reload"])
                self.assertEqual([args.args[0] for args in command.call_args_list], expected)
            for node in nodes:
                profile = directory / f"wproxy-1000-{node['id']}.nmconnection"
                self.assertEqual(profile.stat().st_mode & 0o777, 0o600)
                self.assertIn(f"routing64={ctl.encode_routing_policy(store['routing'])}", profile.read_text())
            self.assertEqual(untouched.read_text(), "preserve me")

    def test_removed_linux_connect_and_targeted_sync_flags_are_rejected(self):
        for arguments in (("nm", "connect", "0123456789abcdef"), ("nm", "sync", "--id", "0123456789abcdef")):
            with self.subTest(arguments=arguments), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                ctl.build_parser().parse_args(arguments)


if __name__ == "__main__":
    unittest.main()
