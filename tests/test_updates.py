import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wproxyctl_updates", ROOT / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ctl)


class FastestServerTests(unittest.TestCase):
    def test_fastest_ignores_timeouts_and_keeps_first_tie(self):
        rows = [
            {"id": "off", "name": "Offline", "latency_ms": None},
            {"id": "one", "name": "One", "latency_ms": 42},
            {"id": "two", "name": "Two", "latency_ms": 42},
        ]
        self.assertEqual(ctl.fastest_ping(rows)["id"], "one")

    def test_ping_results_preserve_configured_order(self):
        nodes = [{"id": "slow", "name": "Slow"}, {"id": "fast", "name": "Fast"}]
        with patch.object(ctl, "ping_node", side_effect=lambda node, _timeout: {"slow": 80, "fast": 10}[node["id"]]):
            rows = ctl.ping_nodes(nodes, 0.1)
        self.assertEqual([row["id"] for row in rows], ["slow", "fast"])
        self.assertEqual(ctl.fastest_ping(rows)["id"], "fast")

    def test_fastest_verified_rejects_open_port_with_broken_proxy(self):
        nodes = [{"id": str(index), "name": str(index)} for index in range(5)]
        rows = [{**node, "latency_ms": index + 1} for index, node in enumerate(nodes)]
        responses = {"0": None, "1": None, "2": None, "3": 120, "4": 90}
        with patch.object(ctl, "verify_node_https", side_effect=lambda node, _timeout: responses[node["id"]]):
            best = ctl.fastest_verified_node(nodes, rows)
        self.assertEqual(best["id"], "4")
        self.assertTrue(best["verified"])

    def test_no_verified_proxy_never_returns_a_tcp_only_result(self):
        nodes = [{"id": "open", "name": "Open port"}]
        rows = [{**nodes[0], "latency_ms": 1}]
        with patch.object(ctl, "verify_node_https", return_value=None):
            self.assertIsNone(ctl.fastest_verified_node(nodes, rows))


class UpdateTests(unittest.TestCase):
    def release(self, version="9.8.7"):
        names = [f"WProxy-{version}-GitHub.zip", f"WProxy-{version}-Setup.exe", "SHA256SUMS"]
        return {
            "tag_name": f"v{version}",
            "assets": [
                {"name": name, "browser_download_url": f"https://github.com/example/{name}"}
                for name in names
            ],
        }

    def test_update_check_uses_stable_semver(self):
        payload = json.dumps(self.release()).encode()
        with patch.object(ctl, "_read_https", return_value=payload):
            status = ctl.update_status()
        self.assertTrue(status["update_available"])
        self.assertEqual(status["latest_version"], "9.8.7")
        with self.assertRaisesRegex(ValueError, "stable semantic version"):
            ctl.parse_release_version("v9.8.7-rc1")

    def test_download_requires_manifest_hash(self):
        archive = b"signed release payload"
        digest = hashlib.sha256(archive).hexdigest()
        release = json.dumps(self.release()).encode()

        def response(url, _limit, _timeout=15.0):
            if url == ctl.RELEASE_API:
                return release
            if url.endswith("SHA256SUMS"):
                return f"{digest}  WProxy-9.8.7-GitHub.zip\n".encode()
            self.fail(url)

        def download(url, destination, _limit, _timeout=30.0):
            self.assertTrue(url.endswith("GitHub.zip"))
            destination.write_bytes(archive)

        with tempfile.TemporaryDirectory() as directory, \
                patch.object(ctl, "_read_https", side_effect=response), \
                patch.object(ctl, "_download_https", side_effect=download), \
                patch.object(ctl, "config_home", return_value=Path(directory)):
            result = ctl.download_update("linux")
            path = Path(result["path"])
            self.assertEqual(path.read_bytes(), archive)
            self.assertEqual(result["sha256"], digest)

    def test_safe_extract_rejects_traversal(self):
        release = {"version": "9.8.7"}
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "bad.zip"
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("WProxy-9.8.7/../../escape", "no")
            with self.assertRaisesRegex(RuntimeError, "unsafe path"):
                ctl._safe_extract_update(archive, Path(directory) / "out", release)

    def test_preferences_default_to_opt_in_updates(self):
        self.assertEqual(ctl.normalize_preferences(None), {"auto_update": False, "remember_authorization": True})
        self.assertEqual(ctl.normalize_preferences({"auto_update": 1}), {"auto_update": True, "remember_authorization": True})
        self.assertFalse(ctl.normalize_preferences({"remember_authorization": False})["remember_authorization"])


if __name__ == "__main__":
    unittest.main()
