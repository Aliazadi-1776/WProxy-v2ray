#!/usr/bin/env python3
"""Start each real core in turn and carry one request through its local proxy."""
import http.server
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "cli"))
import wproxyctl as ctl


class UpstreamProxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_CONNECT(self):
        self.send_response(200, "Connection established")
        self.end_headers()
        self.close_connection = False

    def do_GET(self):
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_args):
        pass


def free_port():
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        return reservation.getsockname()[1]


def wait_for_port(port, process):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Selected core exited before its proxy was ready")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError("Selected core did not open its proxy in time")


def main():
    upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), UpstreamProxy)
    thread = threading.Thread(target=upstream.serve_forever, daemon=True)
    thread.start()
    upstream_port = upstream.server_address[1]
    profiles = [
        ("sing-box", f"http://127.0.0.1:{upstream_port}"),
        ("xray", ctl.engines.pack_native(json.dumps({"outbounds": [{
            "tag": "proxy", "protocol": "http",
            "settings": {"servers": [{"address": "127.0.0.1", "port": upstream_port}]},
        }]}))),
        ("mihomo", ctl.engines.pack_native(f"""proxies:
  - name: upstream
    type: http
    server: 127.0.0.1
    port: {upstream_port}
proxy-groups:
  - name: WProxy
    type: select
    proxies: [upstream]
rules: ["MATCH,WProxy"]
""")),
    ]
    switched = []
    try:
        with tempfile.TemporaryDirectory(prefix="wproxy-engine-switch-") as directory:
            for expected, uri in profiles:
                port = free_port()
                plan = ctl.engine_plan(uri, platform="linux", probe_port=port)
                if plan.engine != expected:
                    raise RuntimeError(f"Expected {expected}, selected {plan.engine}")
                config = Path(directory) / f"{expected}.json"
                ctl.engines.validate(plan, config)
                process = subprocess.Popen(
                    ctl.engines.command(plan.engine, plan.binary, config),
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
                try:
                    wait_for_port(port, process)
                    with socket.create_connection(("127.0.0.1", port), timeout=3) as client:
                        client.sendall(
                            f"GET http://127.0.0.1:{upstream_port}/generate_204 HTTP/1.1\r\n"
                            f"Host: 127.0.0.1:{upstream_port}\r\nConnection: close\r\n\r\n".encode("ascii")
                        )
                        status = client.recv(80).split(b"\r\n", 1)[0]
                    if b" 204 " not in status:
                        raise RuntimeError(f"{expected} returned {status.decode('ascii', errors='replace')}")
                    switched.append(expected)
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    finally:
        upstream.shutdown()
        upstream.server_close()
        thread.join(timeout=2)
    print(" -> ".join(switched))


if __name__ == "__main__":
    main()
