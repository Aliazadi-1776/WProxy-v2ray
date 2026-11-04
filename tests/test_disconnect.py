import contextlib
import importlib.util
import io
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("wproxy_disconnect", Path(__file__).resolve().parents[1] / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ctl)


class DisconnectTests(unittest.TestCase):
    def test_interface_removal_waits_for_plugin_cleanup(self):
        with patch.object(ctl.shutil, "which", return_value="/usr/bin/ip"), \
                patch.object(ctl, "run", return_value=SimpleNamespace(returncode=1)), \
                patch.object(ctl, "linux_plugin_stopped", side_effect=[False, True]) as stopped, \
                patch.object(ctl.time, "sleep"):
            self.assertTrue(ctl.wait_for_linux_tun_removal())
        self.assertEqual(stopped.call_count, 2)

    def test_plugin_disconnecting_state_is_not_ready_for_a_replacement(self):
        with patch.object(ctl, "_is_root", return_value=True), \
                patch.object(ctl.shutil, "which", return_value="/usr/bin/busctl"), \
                patch.object(ctl, "run", return_value=SimpleNamespace(returncode=0, stdout="u 5\n")):
            self.assertFalse(ctl.linux_plugin_stopped())

    def test_successful_deactivation_with_lingering_tun_explains_cleanup_failure(self):
        stderr = io.StringIO()
        with patch.object(ctl, "active_wproxy_connections", return_value=[{"uuid": "fixture"}]), \
                patch.object(ctl, "run", return_value=SimpleNamespace(returncode=0)), \
                patch.object(ctl, "wait_for_linux_tun_removal", return_value=False), \
                contextlib.redirect_stderr(stderr):
            self.assertFalse(ctl.nm_down())
        self.assertIn("cleaning up", stderr.getvalue())

    def test_incomplete_teardown_cannot_start_a_replacement_connection(self):
        node = {"id": "0123456789abcdef", "name": "Fixture"}
        with patch.object(ctl, "nm_down", return_value=False), patch.object(ctl, "run") as command:
            with self.assertRaisesRegex(RuntimeError, "previous WProxy tunnel"):
                ctl.nm_up({"nodes": [node]}, node["id"])
        command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
