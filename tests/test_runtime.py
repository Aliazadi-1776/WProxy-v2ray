import base64
import importlib.util
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wproxyctl", ROOT / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ctl)


class ConfigTests(unittest.TestCase):
    def test_installed_xray_schema_and_binding(self):
        vmess = base64.b64encode(json.dumps({"add": "example.com", "port": 443,
            "id": "11111111-2222-4333-8444-555555555555", "net": "tcp"}).encode()).decode()
        uris = ["vless://11111111-2222-4333-8444-555555555555@example.com:443?security=tls",
                "trojan://test-password@example.com:443?security=tls",
                f"vmess://{vmess}", "ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@example.com:443"]
        with patch.dict(os.environ, {"WPROXY_OUT_IFACE": "wlp58s0"}):
            for uri in uris:
                with self.subTest(scheme=uri.split(":")[0]):
                    config = ctl.xray_config(uri, "198.51.100.42")
                    # v26.3.27 does NOT support automatic addresses/routes.
                    self.assertEqual(config["inbounds"][0]["settings"],
                                     {"name": "wproxy0", "MTU": 1500})
                    for outbound in config["outbounds"][:2]:
                        self.assertEqual(outbound["streamSettings"]["sockopt"]["interface"], "wlp58s0")
                    settings = config["outbounds"][0]["settings"]
                    self.assertEqual((settings.get("vnext") or settings["servers"])[0]["address"], "198.51.100.42")
                    self.assertEqual(config["routing"]["domainStrategy"], "AsIs")

    def test_pinning_preserves_tls_hostname(self):
        config = ctl.xray_config("trojan://test@example.com:443?security=tls", "198.51.100.42")
        self.assertEqual(config["outbounds"][0]["streamSettings"]["tlsSettings"]["serverName"], "example.com")

    def test_tunnel_must_not_be_outbound(self):
        with patch.dict(os.environ, {"WPROXY_OUT_IFACE": "wproxy0"}):
            with self.assertRaises(ValueError):
                ctl.xray_config("trojan://test@example.com:443")

    def test_gateway_is_same_pinned_ip_and_private_file(self):
        answers = [(socket.AF_INET6, socket.SOCK_STREAM, 6, "", ("2001:db8::42", 443, 0, 0)),
                   (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("198.51.100.42", 443))]
        with tempfile.TemporaryDirectory() as directory, patch.object(socket, "getaddrinfo", return_value=answers):
            path = Path(directory) / "gateway"
            value = ctl.write_gateway_metadata("trojan://test@example.com:443", path)
            self.assertEqual(value, "198.51.100.42")
            self.assertEqual(path.read_text().strip(), value)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


class RunnerTests(unittest.TestCase):
    def configure(self, failure=""):
        # Execute the production shell function with only the OS ip command
        # mocked. Simulate the exact failure: Xray's link exists without an IP.
        runner = (ROOT / "service/wproxy-xray-runner").read_text()
        function = re.search(r"^configure_tun\(\) \{.*?^\}", runner, re.M | re.S).group()
        script = r'''
IFACE=wproxy0
HAS_ADDRESS=0
ip() {
    printf '%s\n' "$*" >&2
    case "$*" in
        'link set dev wproxy0 mtu 1500 up') [ "$FAILURE" != link ] ;;
        '-4 addr replace 172.19.0.1/30 dev wproxy0')
            [ "$FAILURE" != address ] || return 1
            HAS_ADDRESS=1 ;;
        '-6 addr replace fdfe:dcba:9876::1/126 dev wproxy0 nodad') return 0 ;;
        '-4 -o addr show dev wproxy0')
            [ "$HAS_ADDRESS" = 1 ] && printf '5: wproxy0 inet 172.19.0.1/30 scope global wproxy0\n' ;;
        *) return 99 ;;
    esac
}
'''
        return subprocess.run(["sh", "-c", script + function + "\nconfigure_tun\n"],
                              env={**os.environ, "FAILURE": failure}, text=True, capture_output=True)

    def test_existing_link_without_ip_gets_configured(self):
        result = self.configure()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-4 addr replace 172.19.0.1/30 dev wproxy0", result.stderr)

    def test_link_failure_does_not_claim_ready(self):
        self.assertNotEqual(self.configure("link").returncode, 0)

    def test_ip_failure_does_not_claim_ready(self):
        self.assertNotEqual(self.configure("address").returncode, 0)


if __name__ == "__main__":
    unittest.main()
