"""Focused import/selection and native preservation regressions (no system routes)."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "cli"))
import wproxy_engines as engines

spec = importlib.util.spec_from_file_location("engine_test_legacy", ROOT / "cli/wproxyctl.py")
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)


class EnginesTests(unittest.TestCase):
    def test_selection_respects_features_and_native_format(self):
        base = "vless://11111111-1111-4111-8111-111111111111@example.com:443"
        self.assertEqual(engines.analyze(base)["engine"], "sing-box")
        self.assertEqual(engines.candidate_engines(base, "linux")[0], "sing-box")
        self.assertEqual(engines.candidate_engines(base, "windows")[0], "xray")
        for suffix in ("?security=reality", "?flow=xtls-rprx-vision", "?type=xhttp"):
            self.assertEqual(engines.analyze(base + suffix)["candidates"], ["xray"])
        self.assertEqual(engines.analyze("hy2://secret@example.com:443")["candidates"], ["sing-box"])
        uri = engines.pack_native('{"outbounds":[{"protocol":"freedom"}]}')
        self.assertEqual(engines.analyze(uri)["candidates"], ["xray"])

    def test_native_original_bytes_and_group_semantics_survive(self):
        text = '# exact original\nproxies: [{name: fixture, type: socks5, server: 127.0.0.1, port: 1080}]\nproxy-groups: [{name: AUTO, type: url-test, proxies: [fixture], url: "https://example.com/204", interval: 300}]\nrules: ["MATCH,AUTO"]\n'
        uri = engines.pack_native(text)
        self.assertEqual(engines.unpack_native(uri)["text"], text)
        _, original = engines._document(text)
        config = engines._mihomo_config(original, {"mode": "all", "domains": [], "apps": []}, "linux", 12345)
        self.assertEqual(config["proxy-groups"], original["proxy-groups"])
        self.assertEqual(config["rules"], original["rules"])
        self.assertEqual(config["proxies"], original["proxies"])
        self.assertFalse(config["tun"]["enable"])
        self.assertEqual(config["bind-address"], "127.0.0.1")
        self.assertNotIn("port", original)

    def test_recursive_yaml_and_ambiguous_native_formats_fail(self):
        with self.assertRaises(ValueError):
            engines.pack_native('proxies: &loop [{name: self, items: *loop}]')
        with self.assertRaises(ValueError):
            engines.pack_native('{"proxies": [], "outbounds":[{"type":"direct"}]}')
        with self.assertRaises(ValueError):
            engines.pack_native('{"outbounds":"invalid"}')

    def test_native_default_and_rules_stay_on_original_core(self):
        original = {"outbounds": [{"type": "direct", "tag": "local"}, {"type": "socks", "tag": "remote", "server": "127.0.0.1", "server_port": 1080}], "route": {"rules": [{"domain": ["example.com"], "outbound": "remote"}]}}
        config = engines._sing_config(original, {"mode": "all", "domains": [], "apps": []}, "linux", probe_port=12345, native=True)
        self.assertEqual(config["outbounds"], original["outbounds"])
        self.assertEqual(config["route"]["rules"], original["route"]["rules"])
        self.assertNotIn("final", config["route"])


if __name__ == "__main__":
    unittest.main()
