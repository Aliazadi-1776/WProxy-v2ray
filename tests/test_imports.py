"""Focused native import checks; no TUN, network or installed cores required."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wproxy_import", ROOT / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ctl)


class ImportTests(unittest.TestCase):
    def test_native_file_keeps_exact_yaml_and_groups(self):
        original = "# provider settings\nproxies:\n  - {name: one, type: socks5, server: example.com, port: 1080}\nproxy-groups:\n  - {name: Auto, type: url-test, proxies: [one], url: 'https://example.com/check'}\nrules: [MATCH,Auto]\n"
        with tempfile.TemporaryDirectory() as temporary:
            file = Path(temporary) / "provider.yaml"
            file.write_text(original)
            store = {"nodes": [], "subs": []}
            with patch.object(ctl, "save_store"), contextlib.redirect_stdout(io.StringIO()):
                ctl.cmd_node(SimpleNamespace(action="import", path=str(file), name="Provider"), store)
        self.assertEqual(len(store["nodes"]), 1)
        native = ctl.engines.unpack_native(store["nodes"][0]["uri"])
        self.assertEqual(native["text"], original)
        self.assertEqual(ctl.node_engine_info(store["nodes"][0]["uri"]), "mihomo")

    def test_failed_subscription_replacement_keeps_existing_nodes(self):
        old = {"id": "saved", "name": "Saved", "source": "subscription", "uri": "trojan://secret@example.com:443"}
        store = {"nodes": [old]}
        with self.assertRaises(ValueError):
            ctl.add_or_replace_nodes(store, ["trojan://new@example.net:443", "tuic://missing-port@example.net"], "subscription")
        self.assertEqual(store["nodes"], [old])

    def test_native_json_is_not_flattened_into_provider_urls(self):
        original = json.dumps({"outbounds": [{"type": "http", "tag": "proxy", "server": "example.com", "server_port": 8080}], "route": {"rule_set": [{"type": "remote", "tag": "rules", "url": "https://example.com/rules.srs"}]}})
        values = ctl.extract_subscription_uris(original)
        self.assertEqual(len(values), 1)
        self.assertEqual(ctl.engines.unpack_native(values[0])["text"], original)

    def test_unsupported_link_does_not_silently_disappear(self):
        with self.assertRaisesRegex(ValueError, "Unsupported connection protocol: ssh"):
            ctl.extract_subscription_uris("trojan://secret@example.com:443\nssh://user@example.net:22")

    def test_modern_links_and_legacy_subscription_json(self):
        links = ["hy2://password@example.com:443", "tuic://11111111-2222-4333-8444-555555555555:secret@example.net:443", "http://example.org:8080"]
        self.assertEqual(ctl.extract_subscription_uris(json.dumps({"servers": links})), links)
        self.assertEqual(ctl.endpoint_from_uri("https://example.org"), ("example.org", 443))


if __name__ == "__main__":
    unittest.main()
