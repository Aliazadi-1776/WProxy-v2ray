"""Connect syncs one profile without scanning or changing other saved connections."""
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
class SelectedProfileSyncTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.node = {"id": "0123456789abcdef", "name": "Selected", "uri": "trojan://test@example.com:443"}
        self.store = {
            "nodes": [self.node] + [
                {"id": f"{index:016x}", "name": f"Other {index}", "uri": "trojan://other@example.net:443"}
                for index in range(100)
            ],
            "routing": {"mode": "only", "domains": ["example.org"], "apps": ["firefox"]},
        }
        self.success = SimpleNamespace(returncode=0, stdout="", stderr="")

    def isolated(self):
        stack = contextlib.ExitStack()
        stack.enter_context(patch.object(ctl, "require_root"))
        stack.enter_context(patch.object(ctl, "original_user", return_value=SimpleNamespace(pw_uid=1000)))
        stack.enter_context(patch.object(ctl, "Path", return_value=self.directory))
        stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        return stack

    def test_connect_updates_only_selected_profile_in_two_commands(self):
        untouched = ["wproxy-1000-stale.nmconnection", "wproxy-2000-other.nmconnection", "unrelated.nmconnection"]
        for name in untouched:
            (self.directory / name).write_text("preserve me")
        profile = self.directory / f"wproxy-1000-{self.node['id']}.nmconnection"
        commands = []

        def run(args, capture=False):
            self.assertTrue(capture)
            self.assertEqual(profile.stat().st_mode & 0o777, 0o600)
            commands.append(args)
            return self.success

        with self.isolated(), patch.object(ctl, "run", side_effect=run), \
                patch.object(ctl, "loaded_owned_wproxy_uuids") as global_scan:
            ctl.nm_sync_node(self.store, self.node["id"])
            profile_uuid = ctl.deterministic_uuid(self.node["id"])
        self.assertEqual(commands, [
            ["nmcli", "connection", "load", str(profile)],
            ["nmcli", "connection", "modify", "uuid", profile_uuid,
             "+vpn.data", f"routing64={ctl.encode_routing_policy(self.store['routing'])}",
             "connection.permissions", ""],
        ])
        global_scan.assert_not_called()
        self.assertIn(f"routing64={ctl.encode_routing_policy(self.store['routing'])}", profile.read_text())
        self.assertIn("uri=" + self.node["uri"], profile.read_text())
        self.assertEqual({path.name for path in self.directory.iterdir()}, {*untouched, profile.name})
        self.assertTrue(all((self.directory / name).read_text() == "preserve me" for name in untouched))

    def test_invalid_or_unknown_node_never_writes_or_calls_networkmanager(self):
        with patch.object(ctl, "require_root"), patch.object(ctl, "Path") as directory, \
                patch.object(ctl, "run") as command:
            for node_id in ("", "../invalid", "fedcba9876543210"):
                with self.subTest(node_id=node_id), self.assertRaises(ValueError):
                    ctl.nm_sync_node(self.store, node_id)
        directory.assert_not_called()
        command.assert_not_called()

    def test_profile_load_failure_stops_before_modify(self):
        failure = SimpleNamespace(returncode=1, stdout="", stderr="profile load failed")
        with self.isolated(), patch.object(ctl, "run", return_value=failure) as command:
            with self.assertRaisesRegex(RuntimeError, "profile load failed"):
                ctl.nm_sync_node(self.store, self.node["id"])
        self.assertEqual(command.call_count, 1)

    def test_routing_update_failure_is_propagated(self):
        failure = SimpleNamespace(returncode=1, stdout="", stderr="routing update failed")
        with self.isolated(), patch.object(ctl, "run", side_effect=(self.success, failure)):
            with self.assertRaisesRegex(RuntimeError, "routing update failed"):
                ctl.nm_sync_node(self.store, self.node["id"])

    def test_sync_dispatch_preserves_full_sync_without_id(self):
        for arguments, selected in (([], False), (["--id", self.node["id"]], True)):
            with self.subTest(arguments=arguments), \
                    patch.object(ctl.sys, "argv", ["wproxyctl", "nm", "sync", *arguments]), \
                    patch.object(ctl, "load_store", return_value=self.store), \
                    patch.object(ctl, "nm_sync") as full_sync, patch.object(ctl, "nm_sync_node") as selected_sync:
                ctl.main()
                if selected:
                    selected_sync.assert_called_once_with(self.store, self.node["id"])
                    full_sync.assert_not_called()
                else:
                    full_sync.assert_called_once_with(self.store)
                    selected_sync.assert_not_called()


if __name__ == "__main__":
    unittest.main()
