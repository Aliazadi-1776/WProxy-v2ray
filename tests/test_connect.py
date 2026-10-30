"""A Manager connection switches, verifies and rolls back in one privileged command."""
import contextlib
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, call, patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wproxy_connect", ROOT / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ctl)


class ConnectTests(unittest.TestCase):
    def setUp(self):
        self.old_id = "0123456789abcdef"
        self.new_id = "fedcba9876543210"
        self.old_node = {"id": self.old_id, "name": "Previous", "uri": "trojan://old@example.com:443"}
        self.new_node = {"id": self.new_id, "name": "Selected", "uri": "trojan://new@example.net:443"}
        self.store = {"nodes": [self.old_node, self.new_node], "routing": {"mode": "all"}}
        self.previous = {"active": True, "node_id": self.old_id}

    def isolated(self, previous=None):
        stack = contextlib.ExitStack()
        operations = Mock()
        for name, value in {
            "status_json": previous if previous is not None else self.previous,
            "windows_state": previous if previous is not None else self.previous,
            "require_windows_admin": None, "nm_sync_node": None,
            "nm_down": True, "windows_down": None,
            "verify_node_https": 20, "nm_up": None, "windows_up": None,
        }.items():
            operations.attach_mock(stack.enter_context(patch.object(ctl, name, return_value=value)), name)
        return stack, operations

    def prefix(self, platform):
        if platform == "windows":
            return [call.require_windows_admin(), call.windows_state()]
        return [call.status_json(self.store), call.nm_sync_node(self.store, self.new_id)]

    def down(self, platform):
        return call.windows_down() if platform == "windows" else call.nm_down()

    def up(self, platform, node_id):
        return call.windows_up(self.store, node_id) if platform == "windows" else call.nm_up(self.store, node_id, verify=True)

    def test_switch_stops_previous_before_verifying_and_activating_target(self):
        for platform in ("linux", "windows"):
            stack, operations = self.isolated()
            with self.subTest(platform=platform), stack:
                ctl.connect_node(self.store, self.new_id, platform)
            self.assertEqual(operations.mock_calls, self.prefix(platform) + [
                self.down(platform), call.verify_node_https(self.new_node), self.up(platform, self.new_id),
            ])

    def test_initial_connection_needs_no_separate_disconnect(self):
        for platform in ("linux", "windows"):
            stack, operations = self.isolated({"active": False, "node_id": None})
            with self.subTest(platform=platform), stack:
                ctl.connect_node(self.store, self.new_id, platform)
            self.assertEqual(operations.mock_calls, self.prefix(platform) + [
                call.verify_node_https(self.new_node), self.up(platform, self.new_id),
            ])

    def test_failed_preflight_restores_previous_without_activating_bad_target(self):
        for platform in ("linux", "windows"):
            stack, operations = self.isolated()
            operations.verify_node_https.return_value = None
            with self.subTest(platform=platform), stack, self.assertRaisesRegex(RuntimeError, "HTTPS.*previous connection was restored"):
                ctl.connect_node(self.store, self.new_id, platform)
            self.assertEqual(operations.mock_calls, self.prefix(platform) + [
                self.down(platform), call.verify_node_https(self.new_node), self.up(platform, self.old_id),
            ])

    def test_failed_activation_restores_previous_through_existing_verified_up(self):
        for platform in ("linux", "windows"):
            stack, operations = self.isolated()
            up = operations.windows_up if platform == "windows" else operations.nm_up
            up.side_effect = [RuntimeError("selected tunnel failed"), None]
            with self.subTest(platform=platform), stack, self.assertRaisesRegex(RuntimeError, "selected tunnel failed.*previous connection was restored"):
                ctl.connect_node(self.store, self.new_id, platform)
            self.assertEqual(operations.mock_calls, self.prefix(platform) + [
                self.down(platform), call.verify_node_https(self.new_node),
                self.up(platform, self.new_id), self.up(platform, self.old_id),
            ])

    def test_restore_failure_reports_both_errors(self):
        for platform in ("linux", "windows"):
            stack, operations = self.isolated()
            up = operations.windows_up if platform == "windows" else operations.nm_up
            up.side_effect = [RuntimeError("selected tunnel failed"), OSError("previous unavailable")]
            with self.subTest(platform=platform), stack, self.assertRaisesRegex(RuntimeError, "selected tunnel failed.*could not be restored.*previous unavailable"):
                ctl.connect_node(self.store, self.new_id, platform)

    def test_sync_failure_leaves_previous_active(self):
        stack, operations = self.isolated()
        operations.nm_sync_node.side_effect = RuntimeError("profile load failed")
        with stack, self.assertRaisesRegex(RuntimeError, "profile load failed"):
            ctl.connect_node(self.store, self.new_id, "linux")
        self.assertEqual(operations.mock_calls, self.prefix("linux"))

    def test_incomplete_teardown_never_starts_or_probes_replacement(self):
        stack, operations = self.isolated()
        operations.nm_down.return_value = False
        with stack, self.assertRaisesRegex(RuntimeError, "previous WProxy tunnel"):
            ctl.connect_node(self.store, self.new_id, "linux")
        self.assertEqual(operations.mock_calls, self.prefix("linux") + [call.nm_down()])

    def test_invalid_or_unknown_target_leaves_previous_untouched(self):
        for platform in ("linux", "windows"):
            for node_id in ("bad", "", "aaaaaaaaaaaaaaaa"):
                stack, operations = self.isolated()
                with self.subTest(platform=platform, node_id=node_id), stack, self.assertRaises(ValueError):
                    ctl.connect_node(self.store, node_id, platform)
                self.assertEqual(operations.mock_calls, [])

    def test_unsaved_previous_node_is_never_guessed_during_rollback(self):
        for platform in ("linux", "windows"):
            stack, operations = self.isolated({"active": True, "node_id": "aaaaaaaaaaaaaaaa"})
            operations.verify_node_https.return_value = None
            with self.subTest(platform=platform), stack, self.assertRaisesRegex(RuntimeError, "HTTPS"):
                ctl.connect_node(self.store, self.new_id, platform)
            operations.windows_up.assert_not_called()
            operations.nm_up.assert_not_called()

    def test_cli_connect_dispatches_one_platform_transaction(self):
        for command, platform in (("nm", "linux"), ("windows", "windows")):
            with self.subTest(command=command), \
                    patch.object(ctl.sys, "argv", ["wproxyctl", command, "connect", self.new_id]), \
                    patch.object(ctl, "load_store", return_value=self.store), \
                    patch.object(ctl, "connect_node") as connect:
                ctl.main()
                connect.assert_called_once_with(self.store, self.new_id, platform=platform)


if __name__ == "__main__":
    unittest.main()
