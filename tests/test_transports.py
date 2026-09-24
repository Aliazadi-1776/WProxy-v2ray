"""Transport regression tests, including a real loopback Xray wire check."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import queue
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("transport_ctl", ROOT / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ctl)
UUID = "11111111-2222-4333-8444-555555555555"
XRAY = shutil.which("xray")
BASE = f"vless://{UUID}@example.com:443?"


class TransportTests(unittest.TestCase):
    def stream(self, query):
        return ctl.outbound_from_uri(BASE + query)["streamSettings"]

    def test_network_field_selects_each_transport(self):
        for alias, expected in (("tcp", "raw"), ("raw", "raw"), ("ws", "websocket"),
                                ("websocket", "websocket"), ("grpc", "grpc"),
                                ("httpupgrade", "httpupgrade"), ("xhttp", "xhttp"),
                                ("splithttp", "xhttp")):
            with self.subTest(alias=alias):
                stream = self.stream("type=" + alias)
                self.assertEqual(stream["network"], expected)
                self.assertNotIn("method", stream)

    def test_vmess_websocket_uses_network(self):
        data = {"add": "example.com", "port": 80, "id": UUID,
                "net": "ws", "path": "/literal%2Fpath?ed=2048", "host": "front.example"}
        uri = "vmess://" + base64.b64encode(json.dumps(data).encode()).decode()
        stream = ctl.outbound_from_uri(uri)["streamSettings"]
        self.assertEqual(stream["network"], "websocket")
        self.assertEqual(stream["wsSettings"]["path"], data["path"])

    def test_websocket_path_is_decoded_once_and_keeps_early_data(self):
        stream = self.stream("type=ws&host=front.example&path=%2Fpart%252Fkeep%3Fed%3D2048")
        self.assertEqual(stream["wsSettings"],
                         {"host": "front.example", "path": "/part%2Fkeep?ed=2048"})

    def test_tcp_http_camouflage_preserves_host_and_path(self):
        stream = self.stream("type=tcp&headerType=http&host=a.example%2Cb.example&path=%2Fone%2C%2Ftwo")
        request = stream["rawSettings"]["header"]["request"]
        self.assertEqual(request["path"], ["/one", "/two"])
        self.assertEqual(request["headers"]["Host"], ["a.example", "b.example"])

    def test_vmess_tcp_http_header(self):
        data = {"add": "example.com", "port": 80, "id": UUID,
                "net": "tcp", "type": "http", "path": "/keep%2Fescaped", "host": "front.example"}
        uri = "vmess://" + base64.b64encode(json.dumps(data).encode()).decode()
        stream = ctl.outbound_from_uri(uri)["streamSettings"]
        self.assertEqual(stream["rawSettings"]["header"]["request"],
                         {"path": ["/keep%2Fescaped"], "headers": {"Host": ["front.example"]}})

    def test_unsupported_values_do_not_fall_back_to_unencrypted_tcp(self):
        for transport in ("http", "h2", "h3", "quic", "unknown"):
            with self.subTest(transport=transport):
                with self.assertRaises(ValueError):
                    self.stream("type=" + transport)
        with self.assertRaises(ValueError):
            self.stream("type=tcp&security=xtls")
        with self.assertRaises(ValueError):
            self.stream("type=ws&security=reality")

    @unittest.skipUnless(XRAY, "Optional wire integration test requires an installed Xray core")
    def test_websocket_upgrade_is_actually_sent_by_xray(self):
        # A syntax-only Xray check cannot catch an ignored unknown JSON key.
        # Observe an actual request to a loopback fake server; no Internet,
        # real credentials, system routes or TUN privileges are involved.
        seen = queue.Queue()
        with socket.socket() as server, tempfile.TemporaryDirectory(prefix="wproxy-ws-wire-") as directory:
            server.bind(("127.0.0.1", 0))
            server.listen(1)
            server.settimeout(5)
            remote_port = server.getsockname()[1]

            def capture():
                try:
                    with server.accept()[0] as connection:
                        connection.settimeout(3)
                        data = b""
                        while b"\r\n\r\n" not in data and len(data) < 8192:
                            chunk = connection.recv(4096)
                            if not chunk:
                                break
                            data += chunk
                        seen.put(data)
                        connection.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
                except OSError as error:
                    seen.put(error)

            thread = threading.Thread(target=capture, daemon=True)
            thread.start()
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                socks_port = reservation.getsockname()[1]
            uri = (f"vless://{UUID}@127.0.0.1:{remote_port}"
                   "?type=ws&host=front.example&path=%2Fwire%252Fsegment%3Fed%3D2048")
            with patch.dict(os.environ, {"WPROXY_OUT_IFACE": ""}):
                config = ctl.xray_config(uri)
            config["inbounds"] = [{"listen": "127.0.0.1", "port": socks_port,
                                   "protocol": "socks", "settings": {"auth": "noauth"}}]
            config_file = Path(directory) / "config.json"
            config_file.write_text(json.dumps(config))
            with subprocess.Popen([XRAY, "run", "-c", str(config_file)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as process:
                try:
                    deadline = time.monotonic() + 5
                    while True:
                        self.assertIsNone(process.poll(), "Xray exited before SOCKS was ready")
                        try:
                            client = socket.create_connection(("127.0.0.1", socks_port), timeout=0.2)
                            break
                        except OSError:
                            if time.monotonic() >= deadline:
                                self.fail("Xray SOCKS listener did not start")
                            time.sleep(0.05)
                    with client:
                        client.settimeout(3)
                        client.sendall(b"\x05\x01\x00")
                        self.assertEqual(client.recv(2), b"\x05\x00")
                        # Documentation-only target IP; the proxy server is loopback.
                        client.sendall(b"\x05\x01\x00\x01" + socket.inet_aton("198.51.100.42")
                                       + (443).to_bytes(2, "big") + b"synthetic-client-payload")
                        request = seen.get(timeout=6)
                    self.assertIsInstance(request, bytes, str(request))
                    self.assertTrue(request.startswith(b"GET /wire%2Fsegment HTTP/1.1\r\n"), repr(request[:90]))
                    self.assertIn(b"host: front.example\r\n", request.lower())
                    self.assertIn(b"upgrade: websocket\r\n", request.lower())
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                    thread.join(timeout=6)


if __name__ == "__main__":
    unittest.main()
