#!/usr/bin/env python3
"""Test actual HTTPS via the installed Xray without touching system routes.

No server URLs, credentials, or subscription URLs are printed. A successful
SOCKS probe verifies the remote proxy, not NetworkManager/TUN integration.
"""
import argparse
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time

spec = importlib.util.spec_from_file_location(
    "wproxyctl", Path(__file__).resolve().parents[1] / "cli/wproxyctl.py")
ctl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ctl)


def probe(node, xray, timeout):
    result = {"id": node["id"], "ok": False, "stage": "config"}
    try:
        with tempfile.TemporaryDirectory(prefix="wproxy-https-") as directory:
            config_path = Path(directory) / "config.json"
            # Use the same pinned endpoint and transport as the TUN runtime.
            endpoint = ctl.write_gateway_metadata(node["uri"], Path(directory) / "gateway")
            config = ctl.xray_config(node["uri"], endpoint)
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            config["inbounds"] = [{"listen": "127.0.0.1", "port": port,
                                   "protocol": "socks", "settings": {"auth": "noauth"}}]
            config_path.write_text(json.dumps(config))
            config_path.chmod(0o600)
            # Never expose Xray's potentially credential-bearing diagnostics.
            with subprocess.Popen([xray, "run", "-c", str(config_path)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as process:
                try:
                    ready = False
                    for _ in range(40):
                        if process.poll() is not None:
                            break
                        try:
                            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                                ready = True
                            break
                        except OSError:
                            time.sleep(0.05)
                    if not ready:
                        result["stage"] = "xray-start"
                        return result
                    started = time.monotonic()
                    response = subprocess.run([
                        "curl", "--noproxy", "", "--socks5-hostname", f"127.0.0.1:{port}",
                        "--connect-timeout", str(timeout), "--max-time", str(timeout),
                        "-sS", "-o", "/dev/null", "-w", "%{http_code}",
                        "https://www.gstatic.com/generate_204"], capture_output=True, text=True,
                        timeout=timeout + 2)
                    result.update(stage="https", curl_exit=response.returncode,
                                  http_code=response.stdout.strip(),
                                  elapsed_ms=round((time.monotonic() - started) * 1000),
                                  ok=response.returncode == 0 and response.stdout.strip() == "204")
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired):
        result["stage"] = "config-or-network-error"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=int, default=12)
    parser.add_argument("--select", action="store_true", help="Print just the fastest working node ID")
    args = parser.parse_args()
    # This probe runs unprivileged and must not attempt SO_BINDTODEVICE.
    os.environ.pop("WPROXY_OUT_IFACE", None)
    xray = shutil.which("xray") or "/usr/local/bin/xray"
    nodes = ctl.load_store()["nodes"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        results = list(executor.map(lambda n: probe(n, xray, args.timeout), nodes))
    working = sorted((r for r in results if r["ok"]), key=lambda r: r["elapsed_ms"])
    if args.select:
        if working:
            print(working[0]["id"])
    else:
        print(json.dumps({"core": subprocess.check_output([xray, "version"], text=True).splitlines()[0],
                          "tested": len(results), "working": len(working), "results": results}, indent=2))
    return 0 if working else 1


if __name__ == "__main__":
    raise SystemExit(main())
