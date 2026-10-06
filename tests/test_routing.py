import base64
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wproxyctl_routing", ROOT / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ctl)
URI = "trojan://test-password@example.com:443?security=tls"


class RoutingPolicyTests(unittest.TestCase):
    def test_missing_policy_preserves_full_tunnel_default(self):
        config = ctl.xray_config(URI)
        self.assertEqual(config["routing"]["rules"], [
            {"type": "field", "ip": ctl.PRIVATE_NETWORKS, "outboundTag": "direct"}
        ])

    def test_bypass_is_union_of_domains_and_processes(self):
        config = ctl.xray_config(URI, routing={
            "mode": "bypass",
            "domains": ["https://YouTube.com/watch?v=1", "203.0.113.8"],
            "apps": ["firefox", "/usr/bin/curl"],
        })
        rules = config["routing"]["rules"]
        self.assertIn({"type": "field", "domain": ["domain:youtube.com"], "outboundTag": "direct"}, rules)
        self.assertIn({"type": "field", "ip": ["203.0.113.8"], "outboundTag": "direct"}, rules)
        self.assertIn({"type": "field", "process": ["firefox", "/usr/bin/curl"], "outboundTag": "direct"}, rules)
        self.assertNotIn("network", rules[-1])

    def test_only_mode_proxies_matches_then_routes_everything_else_direct(self):
        config = ctl.xray_config(URI, routing={
            "mode": "only", "domains": ["example.org"], "apps": ["curl"]
        })
        rules = config["routing"]["rules"]
        self.assertEqual(rules[-1], {
            "type": "field", "network": "tcp,udp", "outboundTag": "direct"
        })
        self.assertIn({"type": "field", "domain": ["domain:example.org"], "outboundTag": "proxy"}, rules)
        self.assertIn({"type": "field", "process": ["curl"], "outboundTag": "proxy"}, rules)

    def test_policy_round_trip_and_profile_embedding(self):
        policy = {"mode": "bypass", "domains": ["Example.COM"], "apps": ["firefox"]}
        encoded = ctl.encode_routing_policy(policy)
        self.assertNotIn("=", encoded)
        self.assertEqual(ctl.decode_routing_policy(encoded), {
            "version": 1, "mode": "bypass", "domains": ["example.com"], "apps": ["firefox"]
        })
        keyfile = ctl.nm_keyfile({"id": "node", "name": "Node", "uri": URI}, policy)
        self.assertIn(f"routing64={encoded}\n", keyfile)
        self.assertIn("wproxy-version=2.4.1\n", keyfile)

    def test_invalid_or_oversized_policy_is_rejected(self):
        with self.assertRaises(ValueError):
            ctl.normalize_routing_policy({"mode": "unknown", "domains": [], "apps": []})
        with self.assertRaises(ValueError):
            ctl.normalize_domain("https://user:secret@example.com")
        with self.assertRaises(ValueError):
            ctl.normalize_app("relative/path")
        with self.assertRaises(ValueError):
            ctl.normalize_routing_policy({"mode": "bypass", "domains": [f"x{i}.test" for i in range(257)], "apps": []})
        with self.assertRaises(ValueError):
            ctl.decode_routing_policy("not+base64")

    def test_corrupt_stored_policy_falls_back_to_all_proxy_without_losing_nodes(self):
        with tempfile.TemporaryDirectory() as directory:
            store = Path(directory) / "store.json"
            store.write_text(json.dumps({
                "nodes": [{"id": "n", "name": "Node", "uri": URI}],
                "subs": [],
                "routing": {"mode": "only", "domains": "not-a-list", "apps": []},
            }))
            with patch.object(ctl, "store_path", return_value=store):
                loaded = ctl.load_store()
        self.assertEqual(len(loaded["nodes"]), 1)
        self.assertEqual(loaded["routing"], ctl.default_routing_policy())

    def test_windows_tun_uses_automatic_system_routes(self):
        config = ctl.xray_config(URI, routing={"mode": "all"}, platform="windows")
        tun = config["inbounds"][0]["settings"]
        self.assertEqual(tun["desc"], "WProxy")
        self.assertEqual(tun["autoSystemRoutingTable"], ["0.0.0.0/0", "::/0"])
        self.assertEqual(tun["autoOutboundsInterface"], "auto")

    @unittest.skipUnless(shutil.which("xray"), "installed Xray is required")
    def test_installed_xray_accepts_domain_and_process_rules(self):
        policy = {"mode": "bypass", "domains": ["example.org"], "apps": ["curl"]}
        config = ctl.xray_config(URI, routing=policy)
        # Schema validation does not need a live TUN and remains usable in CI sandboxes.
        config["inbounds"] = []
        with tempfile.TemporaryDirectory(prefix="wproxy-routing-xray-") as directory:
            path = Path(directory) / "xray.json"
            path.write_text(json.dumps(config), encoding="utf-8")
            result = subprocess.run(
                [shutil.which("xray"), "run", "-test", "-c", str(path)],
                text=True, capture_output=True,
            )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)


if __name__ == "__main__":
    unittest.main()
