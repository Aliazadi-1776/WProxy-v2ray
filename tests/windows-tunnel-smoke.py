#!/usr/bin/env python3
"""Native Wintun test on a disposable GitHub runner, using no saved servers."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid


def powershell(script, timeout=20):
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
        text=True, capture_output=True, timeout=timeout,
    )
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout.strip()


def watchdog(cli, runtime, cancel, seconds):
    """This detached process survives the test process or Actions losing network."""
    cancel.with_suffix(".armed").touch()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if cancel.exists():
            return
        time.sleep(1)
    try:
        subprocess.run([str(cli), "windows", "down"], capture_output=True, timeout=20, check=True)
    except (OSError, subprocess.TimeoutExpired, subprocess.CalledProcessError):
        # The PID file is in this test's isolated LOCALAPPDATA, never a user profile.
        try:
            pid = int((runtime / "xray.pid").read_text(encoding="ascii").strip())
            image = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
                text=True, capture_output=True, timeout=10,
            ).stdout.lower()
            if image.startswith(('"xray.exe"', '"sing-box.exe"', '"mihomo.exe"')):
                subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True, timeout=10)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("installation", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--watchdog", type=Path)
    args = parser.parse_args()
    if os.name != "nt" or os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("Refusing route changes: run only on a disposable native Windows GitHub Actions runner")
    if not ctypes.windll.shell32.IsUserAnAdmin():
        raise SystemExit("The disposable Windows runner must have administrator rights for Wintun")
    cli = args.installation.resolve() / "wproxyctl.exe"
    if args.watchdog:
        watchdog(cli, Path(os.environ["LOCALAPPDATA"]) / "WProxy/run", args.watchdog, 150)
        return
    args.output.mkdir(parents=True, exist_ok=True)
    xray = args.installation.resolve() / "bin/xray.exe"
    assert cli.is_file() and xray.is_file(), "Test the complete installed Setup.exe payload"
    profile = Path(tempfile.mkdtemp(prefix="wproxy-native-tun-test-"))
    environment = os.environ.copy()
    environment.update(APPDATA=str(profile / "roaming"), LOCALAPPDATA=str(profile / "local"))
    runtime = profile / "local/WProxy/run"
    cancel = profile / "cancel-watchdog"
    results = {"platform": "windows", "installed": True}

    def ctl(*arguments, check=True, timeout=60):
        result = subprocess.run(
            [str(cli), *arguments], env=environment, capture_output=True,
            text=True, encoding="utf-8", errors="replace", timeout=timeout,
        )
        if check and result.returncode:
            raise RuntimeError(result.stderr or result.stdout or f"CLI exited {result.returncode}")
        return result

    def https():
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open("https://cp.cloudflare.com/generate_204", timeout=10) as response:
            assert response.status == 204, response.status
        return 204

    interface = powershell(
        "$ErrorActionPreference='Stop';"
        "$r=Get-NetRoute -DestinationPrefix '0.0.0.0/0' | "
        "Where-Object {$_.InterfaceAlias -ne 'wproxy'} | Sort-Object RouteMetric | Select-Object -First 1;"
        "if(-not $r){throw 'No physical default route'};"
        "$a=Get-NetAdapter -InterfaceIndex $r.InterfaceIndex;"
        "[ordered]@{name=$a.Name;index=$a.ifIndex}|ConvertTo-Json -Compress"
    )
    physical = json.loads(interface)
    results["physical_interface"] = physical
    https()  # Establish external service availability before changing any route.
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    identifier = str(uuid.uuid4())
    access = args.output.resolve() / "synthetic-server-access.log"
    server_config = {
        "log": {"loglevel": "warning", "access": str(access)},
        "inbounds": [{
            "listen": "127.0.0.1", "port": port, "protocol": "vless",
            "settings": {"clients": [{"id": identifier}], "decryption": "none"},
            "streamSettings": {"network": "raw", "security": "none"},
        }],
        # The local server must leave through the original physical interface.
        "outbounds": [{"protocol": "freedom", "streamSettings": {"sockopt": {"interface": physical["name"]}}}],
    }
    server_path = profile / "synthetic-server.json"
    server_path.write_text(json.dumps(server_config), encoding="utf-8")
    server_log = (args.output / "synthetic-server-error.log").open("w", encoding="utf-8")
    server = subprocess.Popen(
        [str(xray), "run", "-c", str(server_path)], stdout=server_log,
        stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW,
    )
    recovery = None
    try:
        for _ in range(100):
            assert server.poll() is None, "Synthetic Xray server exited; see its log"
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("Synthetic proxy did not listen")
        uri = f"vless://{identifier}@127.0.0.1:{port}?security=none&type=tcp#CI-local-proxy"
        ctl("node", "add", uri)
        nodes = json.loads(ctl("node", "list", "--json").stdout)
        assert len(nodes) == 1
        node_id = nodes[0]["id"]
        preflight = json.loads(ctl("node", "verify", node_id, "--json").stdout)
        assert preflight["verified"] is True
        results["preflight"] = preflight

        ui_output = args.output.resolve() / "ui-tunnel"
        ui_environment = os.environ.copy()
        ui_environment.update(
            WPROXY_TEST_URI=uri, WPROXY_TEST_PYTHON=sys.executable,
            WPROXY_TEST_WATCHDOG=str(Path(__file__).resolve()),
        )
        ui = subprocess.run(
            ["node", str(Path(__file__).with_name("windows-desktop-smoke.mjs").resolve()),
             str(args.installation.resolve()), str(ui_output)],
            env=ui_environment, text=True, capture_output=True, timeout=135,
        )
        if ui.returncode:
            raise RuntimeError(ui.stderr or ui.stdout or "Native UI connection test failed")
        print(ui.stdout.strip())
        ui_result = json.loads((ui_output / "desktop-result.json").read_text(encoding="utf-8"))
        assert ui_result["uiTunnel"]["rustElevationBridge"] and ui_result["uiTunnel"]["disconnected"]
        results["ui_tunnel"] = ui_result["uiTunnel"]

        # Arm recovery in an independent process BEFORE the client can add routes.
        with (args.output / "watchdog.log").open("w", encoding="utf-8") as recovery_log:
            recovery = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), str(args.installation.resolve()),
                 str(args.output.resolve()), "--watchdog", str(cancel)],
                env=environment, stdin=subprocess.DEVNULL, stdout=recovery_log, stderr=subprocess.STDOUT,
                creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
                close_fds=True,
            )
        for _ in range(100):
            assert recovery.poll() is None, "Network recovery watchdog exited before it was armed"
            if cancel.with_suffix(".armed").exists():
                break
            time.sleep(0.05)
        else:
            raise RuntimeError("Network recovery watchdog did not arm")
        ctl("windows", "up", node_id, timeout=70)
        status = json.loads(ctl("windows", "status", "--json").stdout)
        assert status["active"] and status["verified"] and status["node_id"] == node_id, status
        results["connected"] = status
        networking = json.loads(powershell(
            "$ErrorActionPreference='Stop';$a=Get-NetAdapter -Name 'wproxy';"
            "$r=Get-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix '0.0.0.0/0';"
            "$d=Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4;"
            "Clear-DnsClientCache;"
            "$resolved=Resolve-DnsName 'cp.cloudflare.com' -Type A -DnsOnly -ErrorAction Stop;"
            "[ordered]@{up=($a.Status -eq 'Up');route=[bool]$r;dns=@($d.ServerAddresses);"
            "resolved=@($resolved | Where-Object {$_.IPAddress} | ForEach-Object {$_.IPAddress})}|ConvertTo-Json -Compress",
            timeout=30,
        ))
        assert networking["up"] and networking["route"], networking
        assert "1.1.1.1" in networking["dns"] and networking["resolved"], networking
        results["networking"] = networking
        results["https_status"] = https()
        time.sleep(0.5)
        accepted = access.read_text(encoding="utf-8", errors="replace")
        assert re.search(r"accepted\s+(?:tcp:)?[^\s]+:443", accepted), "No HTTPS traffic crossed the synthetic proxy"
        assert re.search(r"accepted\s+udp:[^\s]+:53", accepted), "No DNS traffic crossed the synthetic proxy"
        results["proxy_access_confirmed"] = True
        ctl("windows", "down")
        assert not json.loads(ctl("windows", "status", "--json").stdout)["active"]

        # An unreachable proxy must fail connection verification and remove TUN.
        server.terminate()
        server.wait(timeout=10)
        failed = ctl("windows", "up", node_id, check=False, timeout=75)
        assert failed.returncode != 0 and "verification failed" in failed.stderr.lower(), failed.stderr
        assert not json.loads(ctl("windows", "status", "--json").stdout)["active"]
        results["unreachable_server_rolled_back"] = True
        remaining = powershell("@(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object {$_.InterfaceAlias -eq 'wproxy'}).Count")
        assert remaining == "0", f"WProxy default routes remained after cleanup: {remaining}"
        results["internet_restored"] = https() == 204
        print("Installed native Windows TUN: PASS (Wintun, default route, DNS, HTTPS, synthetic proxy access, failed-server rollback)")
    finally:
        try:
            ctl("windows", "down", timeout=25)
            cancel.touch()
        finally:
            if server.poll() is None:
                server.kill()
                server.wait(timeout=10)
            server_log.close()
            if recovery and cancel.exists():
                recovery.wait(timeout=5)
            for name in ("xray.log", "last-error.txt"):
                source = runtime / name
                if source.is_file():
                    (args.output / name).write_bytes(source.read_bytes())
            (args.output / "tunnel-result.json").write_text(json.dumps(results, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
