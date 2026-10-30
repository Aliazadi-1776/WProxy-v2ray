"""The Windows Manager replaces a tunnel through one privileged command."""
import contextlib
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, call, patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wproxy_connect", ROOT / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ctl)


class WindowsConnectTests(unittest.TestCase):
    def setUp(self):
        self.old_id = "0123456789abcdef"
        self.new_id = "fedcba9876543210"
        self.old_node = {"id": self.old_id, "name": "Previous", "uri": "trojan://old@example.com:443"}
        self.new_node = {"id": self.new_id, "name": "Selected", "uri": "trojan://new@example.net:443"}
        self.store = {"nodes": [self.old_node, self.new_node], "routing": {"mode": "all"}}

    def isolated(self, previous=None):
        stack = contextlib.ExitStack()
        operations = Mock()
        for name, value in {
            "windows_state": previous if previous is not None else {"active": True, "node_id": self.old_id},
            "require_windows_admin": None, "windows_down": None,
            "verify_node_https": 20, "windows_up": None,
        }.items():
            operations.attach_mock(stack.enter_context(patch.object(ctl, name, return_value=value)), name)
        return stack, operations

    def test_switch_stops_previous_before_verifying_and_activating_target(self):
        stack, operations = self.isolated()
        with stack:
            ctl.windows_connect(self.store, self.new_id)
        self.assertEqual(operations.mock_calls, [call.require_windows_admin(), call.windows_state(),
            call.windows_down(), call.verify_node_https(self.new_node), call.windows_up(self.store, self.new_id)])

    def test_initial_connection_needs_no_separate_disconnect(self):
        stack, operations = self.isolated({"active": False, "node_id": None})
        with stack:
            ctl.windows_connect(self.store, self.new_id)
        operations.windows_down.assert_not_called()
        operations.windows_up.assert_called_once_with(self.store, self.new_id)

    def test_failed_preflight_restores_previous_without_activating_bad_target(self):
        stack, operations = self.isolated()
        operations.verify_node_https.return_value = None
        with stack, self.assertRaisesRegex(RuntimeError, "HTTPS.*previous connection was restored"):
            ctl.windows_connect(self.store, self.new_id)
        operations.windows_up.assert_called_once_with(self.store, self.old_id)

    def test_failed_activation_restores_previous_through_existing_verified_up(self):
        stack, operations = self.isolated()
        operations.windows_up.side_effect = [RuntimeError("selected tunnel failed"), None]
        with stack, self.assertRaisesRegex(RuntimeError, "selected tunnel failed.*previous connection was restored"):
            ctl.windows_connect(self.store, self.new_id)
        self.assertEqual(operations.windows_up.call_args_list,
                         [call(self.store, self.new_id), call(self.store, self.old_id)])

    def test_restore_failure_reports_both_errors(self):
        stack, operations = self.isolated()
        operations.windows_up.side_effect = [RuntimeError("selected tunnel failed"), OSError("previous unavailable")]
        with stack, self.assertRaisesRegex(RuntimeError, "selected tunnel failed.*could not be restored.*previous unavailable"):
            ctl.windows_connect(self.store, self.new_id)

    def test_invalid_or_unknown_target_leaves_previous_untouched(self):
        for node_id in ("bad", "", "aaaaaaaaaaaaaaaa"):
            stack, operations = self.isolated()
            with self.subTest(node_id=node_id), stack, self.assertRaises(ValueError):
                ctl.windows_connect(self.store, node_id)
            self.assertEqual(operations.mock_calls, [])

    def test_unsaved_previous_node_is_never_guessed_during_rollback(self):
        stack, operations = self.isolated({"active": True, "node_id": "aaaaaaaaaaaaaaaa"})
        operations.verify_node_https.return_value = None
        with stack, self.assertRaisesRegex(RuntimeError, "HTTPS"):
            ctl.windows_connect(self.store, self.new_id)
        operations.windows_up.assert_not_called()

    def test_cli_connect_dispatches_one_windows_transaction(self):
        with patch.object(ctl.sys, "argv", ["wproxyctl", "windows", "connect", self.new_id]), \
                patch.object(ctl, "load_store", return_value=self.store), \
                patch.object(ctl, "windows_connect") as connect:
            ctl.main()
        connect.assert_called_once_with(self.store, self.new_id)


if __name__ == "__main__":
    unittest.main()
