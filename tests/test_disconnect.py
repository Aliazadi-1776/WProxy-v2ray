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
