"""Native core adapters; saved input is immutable and runtime files are private copies."""
import base64
import copy
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import urllib.parse

ENGINES = ("sing-box", "xray", "mihomo")
NATIVE_PREFIX = "wproxy-config://"
MAX_INPUT_BYTES = 8 * 1024 * 1024
SCHEMES = {"vless", "vmess", "trojan", "ss", "hysteria2", "hy2", "tuic", "wireguard", "wg", "socks", "socks5", "http", "https"}


def _document(text):
    if not isinstance(text, str) or len(text.encode("utf-8")) > MAX_INPUT_BYTES:
        raise ValueError("Configuration must be UTF-8 text smaller than 8 MiB")
    stripped = text.lstrip("\ufeff \t\r\n")
    try:
        value = json.loads(stripped)
        is_json = True
    except RecursionError as error:
        raise ValueError("Configuration is too deeply nested") from error
    except json.JSONDecodeError:
        try:
            import yaml
        except ImportError as error:
            raise ValueError("YAML import requires PyYAML; reinstall WProxy with its YAML support") from error
        try:
            value = yaml.safe_load(stripped)
        except (yaml.YAMLError, RecursionError) as error:
            raise ValueError("Invalid YAML configuration") from error
        is_json = False
    if not isinstance(value, dict):
        raise ValueError("A native configuration must contain an object")
    for key in ("outbounds", "endpoints", "proxies", "proxy-groups"):
        if key in value and (not isinstance(value[key], list) or any(not isinstance(row, dict) for row in value[key])):
            raise ValueError(f"Configuration {key} must be a list of objects")
    for key in ("proxy-providers", "rule-providers", "route", "routing", "dns"):
        if key in value and not isinstance(value[key], dict):
            raise ValueError(f"Configuration {key} must be an object")
    for section in (value.get("route", {}), value.get("routing", {})):
        if "rules" in section and not isinstance(section["rules"], list):
            raise ValueError("Configuration route rules must be a list")
    if "rules" in value and (not isinstance(value["rules"], list) or any(not isinstance(rule, str) for rule in value["rules"])):
        raise ValueError("Clash rules must be a list of strings")
    clash = any(key in value for key in ("proxies", "proxy-providers", "proxy-groups"))
    outbounds = value.get("outbounds")
    sing = isinstance(outbounds, list) and any(isinstance(row, dict) and "type" in row for row in outbounds)
    sing = sing or isinstance(value.get("endpoints"), list)
    xray = isinstance(outbounds, list) and any(isinstance(row, dict) and "protocol" in row for row in outbounds)
    if sum((clash, sing, xray)) != 1:
        raise ValueError("Cannot identify one native format: use sing-box JSON, Xray JSON or Clash YAML")
    if clash:
        _bounded_document(value)
        return "clash-json" if is_json else "clash-yaml", value
    if not is_json:
        raise ValueError("sing-box and Xray native configurations must be JSON")
    _bounded_document(value)
    return "sing-box-json" if sing else "xray-json", value


def _bounded_document(value):
    remaining = 100000
    ancestors = set()

    def visit(item, depth=0):
        nonlocal remaining
        remaining -= 1
        if remaining < 0 or depth > 64:
            raise ValueError("Configuration is too deeply nested or contains too many entries")
        if isinstance(item, (dict, list)):
            if id(item) in ancestors:
                raise ValueError("Recursive YAML aliases are not supported")
            ancestors.add(id(item))
            if isinstance(item, dict):
                if any(not isinstance(key, str) for key in item):
                    raise ValueError("Configuration object keys must be strings")
                for child in item.values():
                    visit(child, depth + 1)
            else:
                for child in item:
                    visit(child, depth + 1)
            ancestors.remove(id(item))
        elif item is not None and not isinstance(item, (str, int, float, bool)):
            raise ValueError("Configuration contains an unsupported YAML value")
    visit(value)


def pack_native(text):
    format_name, _ = _document(text)
    payload = json.dumps({"version": 1, "format": format_name, "text": text}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return NATIVE_PREFIX + base64.urlsafe_b64encode(payload).decode("ascii").rstrip("=")


def unpack_native(uri):
    if not isinstance(uri, str) or not uri.startswith(NATIVE_PREFIX):
        raise ValueError("Not a native WProxy configuration")
    encoded = uri[len(NATIVE_PREFIX):]
    if len(encoded) > (MAX_INPUT_BYTES * 6 + 1024) * 4 // 3 + 4:
        raise ValueError("Configuration is larger than 8 MiB")
    try:
        envelope = json.loads(base64.b64decode(encoded + "=" * (-len(encoded) % 4), altchars=b"-_", validate=True))
    except (ValueError, UnicodeDecodeError) as error:
        raise ValueError("Invalid native configuration envelope") from error
    if not isinstance(envelope, dict) or envelope.get("version") != 1 or not isinstance(envelope.get("text"), str):
        raise ValueError("Unsupported native configuration envelope")
    format_name, _ = _document(envelope["text"])
    if format_name != envelope.get("format"):
        raise ValueError("Native configuration format does not match its content")
    return {"format": format_name, "text": envelope["text"]}


def _uri_parts(uri):
    if not isinstance(uri, str) or len(uri.encode("utf-8")) > MAX_INPUT_BYTES or any(c in uri for c in "\r\n\x00"):
        raise ValueError("Invalid connection link")
    try:
        parsed = urllib.parse.urlsplit(uri)
        query = {key: values[-1] for key, values in urllib.parse.parse_qs(parsed.query, keep_blank_values=True).items()}
        if parsed.scheme.lower() not in SCHEMES:
            raise ValueError("Unsupported connection protocol")
        # VMess and legacy Shadowsocks embed their endpoint in base64.
        if parsed.scheme.lower() not in ("vmess", "ss"):
            port = parsed.port or (443 if parsed.scheme.lower() == "https" else 80 if parsed.scheme.lower() == "http" else 0)
            if not parsed.hostname or not 0 < port < 65536:
                raise ValueError("Connection link is missing a valid server or port")
            if parsed.scheme.lower() in ("vless", "trojan", "tuic", "hysteria2", "hy2", "wireguard", "wg") and parsed.username is None:
                raise ValueError("Connection link is missing authentication")
        return parsed, query
    except (ValueError, TypeError) as error:
        raise ValueError("Invalid connection link: server, port or authentication is missing") from error


def analyze(uri):
    if uri.startswith(NATIVE_PREFIX):
        native = unpack_native(uri)
        engine = {"sing-box-json": "sing-box", "xray-json": "xray", "clash-yaml": "mihomo", "clash-json": "mihomo"}[native["format"]]
        return {"format": native["format"], "engine": engine, "candidates": [engine], "protocol": "native"}
    parsed, query = _uri_parts(uri)
    scheme = parsed.scheme.lower()
    transport = (query.get("type") or query.get("network") or "tcp").lower()
    specialized = query.get("security") == "reality" or bool(query.get("flow")) or transport in ("xhttp", "splithttp", "kcp", "mkcp", "hysteria")
    specialized = specialized or query.get("encryption") not in (None, "", "none") or query.get("headerType") not in (None, "", "none") or query.get("mode") == "multi" or bool(query.get("authority"))
    candidates = ["xray"] if scheme in ("vless", "vmess", "trojan", "ss") and specialized else ["sing-box", "xray"] if scheme in ("vless", "vmess", "trojan", "ss") else ["sing-box"]
    # VMess's network and optional camouflage live in its JSON payload.
    if scheme == "vmess":
        try:
            encoded = uri[8:]
            obj = json.loads(base64.b64decode(encoded + "=" * (-len(encoded) % 4)))
            if not isinstance(obj, dict) or not obj.get("add") or not obj.get("id") or not 0 < int(obj.get("port", 0)) < 65536:
                raise ValueError()
            if str(obj.get("net", "tcp")).lower() in ("xhttp", "splithttp", "kcp", "mkcp", "hysteria") or obj.get("type") not in (None, "", "none"):
                candidates = ["xray"]
        except (ValueError, TypeError, KeyError) as error:
            raise ValueError("Invalid VMess payload") from error
    if scheme == "ss":
        # SIP002 plugin parameters cannot be ignored by an Xray fallback.
        if query.get("plugin"):
            candidates = ["sing-box"]
    return {"format": "uri", "engine": candidates[0], "candidates": candidates, "protocol": {"hy2": "hysteria2", "wg": "wireguard", "socks5": "socks"}.get(scheme, scheme)}


def endpoint(uri, legacy_endpoint):
    if not uri.startswith(NATIVE_PREFIX):
        parsed, _ = _uri_parts(uri)
        if parsed.scheme.lower() in ("vmess", "ss"):
            return legacy_endpoint(uri)
        return parsed.hostname or "", parsed.port or (443 if parsed.scheme.lower() == "https" else 80 if parsed.scheme.lower() == "http" else 0)
    _, value = _document(unpack_native(uri)["text"])
    for row in value.get("proxies", []) + value.get("outbounds", []) + value.get("endpoints", []):
        if not isinstance(row, dict):
            continue
        host, port = row.get("server"), row.get("server_port") or row.get("port")
        if host and port:
            return str(host), int(port)
        settings = row.get("settings") or {}
        if not isinstance(settings, dict):
            raise ValueError("Invalid native outbound settings")
        for key in ("vnext", "servers"):
            if key in settings and not isinstance(settings[key], list):
                raise ValueError("Invalid native outbound servers")
        if "peers" in row and not isinstance(row["peers"], list):
            raise ValueError("Invalid native endpoint peers")
        for item in settings.get("vnext", []) + settings.get("servers", []) + row.get("peers", []):
            if not isinstance(item, dict):
                raise ValueError("Invalid native endpoint")
            if item.get("address") and item.get("port"):
                return str(item["address"]), int(item["port"])
    return "", 0


def _trusted_binary(path):
    path = Path(path)
    if not path.is_file() or not os.access(path, os.X_OK):
        return False
    if os.name == "nt" or not hasattr(os, "geteuid") or os.geteuid() != 0:
        return True
    for parent in (path, *path.parents):
        info = parent.stat()
        if info.st_uid != 0 or info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            return False
    return True


def find_binary(engine, platform=None):
    if engine not in ENGINES:
        raise ValueError("Unknown core")
    platform = platform or ("windows" if os.name == "nt" else "linux")
    filename = engine + (".exe" if platform == "windows" else "")
    configured = os.environ.get({"sing-box": "SING_BOX_BIN", "xray": "XRAY_BIN", "mihomo": "MIHOMO_BIN"}[engine])
    if platform == "windows":
        directory = Path(sys.executable).resolve().parent
        candidates = [directory / "bin" / filename, Path(__file__).resolve().parents[1] / "windows/bin" / filename]
        candidates += [Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/WProxy/bin" / filename]
    else:
        candidates = [Path("/usr/lib/wproxy/cores") / filename, Path("/usr/local/bin") / filename, Path("/usr/bin") / filename]
    if configured:
        candidates.insert(0, Path(configured))
    discovered = shutil.which(filename)
    if discovered:
        candidates.append(Path(discovered))
    for candidate in candidates:
        if _trusted_binary(candidate):
            return str(candidate.resolve())
    raise RuntimeError(f"{engine} core is missing. Reinstall WProxy with its bundled engines.")


def _version(engine, binary):
    args = [binary, "version"] if engine != "mihomo" else [binary, "-v"]
    flags = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=5, **flags)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"Could not identify the {engine} core version") from error
    output = (result.stdout or "") + "\n" + (result.stderr or "")
    match = re.search(r"(?:\bv)?(\d+\.\d+\.\d+(?:[-+][\w.-]+)?)\b", output)
    if result.returncode or not match:
        raise RuntimeError(f"Could not identify the {engine} core version")
    return match.group(1)


def inventory(platform=None):
    rows = []
    for engine in ENGINES:
        try:
            binary = find_binary(engine, platform)
            version = _version(engine, binary)
            rows.append({"engine": engine, "available": True, "version": version})
        except RuntimeError:
            rows.append({"engine": engine, "available": False, "version": None})
    return rows


def command(engine, binary, path, check=False):
    path = str(Path(path).resolve())
    if engine == "xray":
        return [binary, "run", *(["-test"] if check else []), "-c", path]
    if engine == "sing-box":
        return [binary, "check" if check else "run", "-c", path]
    if engine == "mihomo":
        return [binary, *(["-t"] if check else []), "-d", str(Path(path).parent), "-f", path]
    raise ValueError("Unknown core")


def validate(plan, path):
    path = Path(path)
    path.write_text(json.dumps(plan.config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(path, 0o600)
    if getattr(plan, "validated", False):
        return plan
    flags = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
    try:
        result = subprocess.run(command(plan.engine, plan.binary, path, check=True), capture_output=True, text=True, timeout=20, cwd=path.parent, **flags)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"{plan.engine} configuration validation could not finish") from error
    if result.returncode:
        # Core errors can echo a password, URL or private key. Keep UI diagnostics safe.
        raise RuntimeError(f"{plan.engine} {plan.version} rejected this configuration. Check its options or update the bundled core.")
    plan.validated = True
    return plan


def _tls(query, host, default=False):
    security = (query.get("security") or ("tls" if default else "none")).lower()
    if security not in ("none", "tls"):
        raise ValueError("This TLS mode requires Xray")
    if security == "none":
        return None
    tls = {"enabled": True, "server_name": query.get("sni") or query.get("peer") or query.get("serverName") or host}
    if query.get("alpn"):
        tls["alpn"] = query["alpn"].split(",")
    if (query.get("insecure") or query.get("allowInsecure") or "").lower() in ("1", "true", "yes"):
        tls["insecure"] = True
    if query.get("fp"):
        tls["utls"] = {"enabled": True, "fingerprint": query["fp"]}
    return tls


def _sing_outbound(uri, legacy):
    parsed, query = _uri_parts(uri)
    scheme = parsed.scheme.lower()
    host, port = endpoint(uri, lambda value: legacy.endpoint_from_uri(value))
    result = {"type": {"ss": "shadowsocks", "hy2": "hysteria2", "wg": "wireguard", "socks5": "socks", "https": "http"}.get(scheme, scheme), "tag": "proxy", "server": host, "server_port": port}
    if not host or not 0 < int(port) < 65536:
        raise ValueError("Connection link has no valid endpoint")
    if scheme in ("vless", "vmess", "trojan", "ss"):
        outbound = legacy.outbound_from_uri(uri) if scheme != "ss" or not query.get("plugin") else None
        if scheme == "vless":
            result["uuid"] = urllib.parse.unquote(parsed.username)
            if query.get("encryption") not in (None, "", "none"):
                raise ValueError("VLESS encryption requires Xray")
        elif scheme == "vmess":
            vmess = legacy.vmess_payload(uri)
            result.update(uuid=str(vmess["id"]), security=str(vmess.get("scy") or vmess.get("security") or "auto"), alter_id=int(vmess.get("aid") or 0))
        elif scheme == "trojan":
            result["password"] = urllib.parse.unquote(parsed.username)
        else:
            method, password, _, _, _, raw_query = legacy.ss_parts(uri)
            result.update(method=method, password=password)
            params = urllib.parse.parse_qs(raw_query)
            if params.get("plugin"):
                plugin, _, options = params["plugin"][-1].partition(";")
                result.update(plugin=plugin, plugin_opts=options)
        stream = (outbound or {}).get("streamSettings", {})
        security = stream.get("security", "none")
        if security == "reality":
            raise ValueError("REALITY uses Xray")
        if security == "tls":
            original = stream.get("tlsSettings", {})
            tls = {"enabled": True, "server_name": original.get("serverName", host)}
            for old, new in (("allowInsecure", "insecure"), ("alpn", "alpn")):
                if old in original:
                    tls[new] = original[old]
            if original.get("fingerprint"):
                tls["utls"] = {"enabled": True, "fingerprint": original["fingerprint"]}
            result["tls"] = tls
        network = stream.get("network", "raw")
        if network == "websocket":
            ws = stream.get("wsSettings", {})
            path = ws.get("path", "/")
            transport = {"type": "ws", "path": path}
            if ws.get("host"):
                transport["headers"] = {"Host": ws["host"]}
            # Share-link early data belongs to the transport, not the HTTP path.
            split = urllib.parse.urlsplit(path)
            parts = urllib.parse.parse_qs(split.query)
            if "ed" in parts:
                transport["max_early_data"] = int(parts["ed"][-1])
                transport["early_data_header_name"] = "Sec-WebSocket-Protocol"
                kept = [(key, value) for key, value in urllib.parse.parse_qsl(split.query) if key != "ed"]
                transport["path"] = urllib.parse.urlunsplit((split.scheme, split.netloc, split.path, urllib.parse.urlencode(kept), split.fragment))
            result["transport"] = transport
        elif network == "grpc":
            grpc = stream.get("grpcSettings", {})
            if grpc.get("multiMode") or grpc.get("authority"):
                raise ValueError("Xray-specific gRPC options require Xray")
            result["transport"] = {"type": "grpc", "service_name": grpc.get("serviceName", "")}
        elif network == "httpupgrade":
            settings = stream.get("httpupgradeSettings", {})
            result["transport"] = {"type": "httpupgrade", "path": settings.get("path", "/"), "host": settings.get("host", "")}
        elif network != "raw" or stream.get("rawSettings"):
            raise ValueError("This transport requires Xray")
    elif scheme in ("hysteria2", "hy2"):
        result["password"] = urllib.parse.unquote(parsed.username + ((":" + parsed.password) if parsed.password is not None else ""))
        result["tls"] = _tls(query, host, default=True)
        if query.get("obfs"):
            if query["obfs"] != "salamander" or not query.get("obfs-password"):
                raise ValueError("Hysteria2 requires a valid salamander obfuscation password")
            result["obfs"] = {"type": "salamander", "password": query["obfs-password"]}
    elif scheme == "tuic":
        if parsed.password is None:
            raise ValueError("TUIC link must include UUID and password")
        result.update(uuid=urllib.parse.unquote(parsed.username), password=urllib.parse.unquote(parsed.password))
        result["tls"] = _tls(query, host, default=True)
        if query.get("congestion_control"):
            result["congestion_control"] = query["congestion_control"]
        if query.get("udp_relay_mode"):
            result["udp_relay_mode"] = query["udp_relay_mode"]
    elif scheme in ("socks", "socks5", "http", "https"):
        if parsed.username is not None:
            result["username"] = urllib.parse.unquote(parsed.username)
        if parsed.password is not None:
            result["password"] = urllib.parse.unquote(parsed.password)
        if scheme in ("socks", "socks5"):
            result["version"] = "5"
        elif scheme == "https":
            result["tls"] = _tls(query, host, default=True)
    elif scheme in ("wireguard", "wg"):
        private_key = urllib.parse.unquote(parsed.username)
        public_key = query.get("publickey") or query.get("public_key")
        addresses = query.get("address") or query.get("local_address")
        if not public_key or not addresses:
            raise ValueError("WireGuard link needs publickey and address parameters")
        peer = {"address": host, "port": port, "public_key": public_key, "allowed_ips": ["0.0.0.0/0", "::/0"]}
        if query.get("presharedkey"):
            peer["pre_shared_key"] = query["presharedkey"]
        if query.get("reserved"):
            peer["reserved"] = [int(value) for value in query["reserved"].split(",")]
        result = {"type": "wireguard", "tag": "proxy", "system": False, "address": addresses.split(","), "private_key": private_key, "peers": [peer]}
        if query.get("mtu"):
            result["mtu"] = int(query["mtu"])
    return result


def _sing_routes(policy, direct, proxy):
    rules = [{"ip_is_private": True, "action": "route", "outbound": direct}]
    target = direct if policy["mode"] == "bypass" else proxy
    if policy["mode"] in ("bypass", "only"):
        domains, ips = [], []
        for value in policy["domains"]:
            try:
                ipaddress.ip_address(value)
                ips.append(value)
            except ValueError:
                domains.append(value)
        if domains:
            rules.append({"domain_suffix": domains, "action": "route", "outbound": target})
        if ips:
            rules.append({"ip_cidr": ips, "action": "route", "outbound": target})
        if policy["apps"]:
            rules.append({"process_path": policy["apps"], "action": "route", "outbound": target})
    return rules


def _interface():
    interface = os.environ.get("WPROXY_OUT_IFACE", "").strip()
    if interface and (interface == "wproxy0" or not re.fullmatch(r"[a-zA-Z0-9_.:-]{1,15}", interface)):
        raise ValueError("Invalid physical outbound interface")
    return interface


def _ingress_tag(config, engine):
    inbounds = config.get("inbounds", [])
    if not isinstance(inbounds, list) or any(not isinstance(row, dict) for row in inbounds):
        raise ValueError("Native inbounds must be a list of objects")
    tags = [row.get("tag") for row in inbounds if row.get("tag")]
    rules = (config.get("route") if engine == "sing-box" else config.get("routing")) or {}
    field = "inbound" if engine == "sing-box" else "inboundTag"
    referenced = any(isinstance(row, dict) and row.get(field) for row in rules.get("rules", []))
    if referenced and len(tags) != 1:
        raise ValueError("Native routing with multiple inbound identities cannot be mapped to one WProxy TUN")
    return tags[0] if len(tags) == 1 else "wproxy-in"


def _sing_config(value, policy, platform, probe_port=None, native=False):
    config = copy.deepcopy(value)
    inbound_tag = _ingress_tag(config, "sing-box") if native else "wproxy-in"
    if config.get("services") or config.get("certificate"):
        raise ValueError("Native service/certificate management is not supported inside a WProxy tunnel")
    config["log"] = {"level": "warn", "timestamp": False}
    config.pop("experimental", None)
    config.pop("ntp", None)
    config["inbounds"] = [{"type": "http", "tag": inbound_tag, "listen": "127.0.0.1", "listen_port": probe_port}] if probe_port else [{
        "type": "tun", "tag": inbound_tag, "interface_name": "wproxy" if platform == "windows" else "wproxy0",
        "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"], "mtu": 1400 if platform == "windows" else 1500,
        "auto_route": platform == "windows", "strict_route": platform == "windows", "stack": "mixed",
    }]
    route = config.setdefault("route", {})
    if platform == "linux" and _interface():
        route["default_interface"] = _interface()
        route.pop("auto_detect_interface", None)
    else:
        route["auto_detect_interface"] = True
        route.pop("default_interface", None)
    outbounds = config.setdefault("outbounds", [])
    entries = outbounds + config.get("endpoints", [])
    if platform == "linux" and _interface():
        for row in entries:
            if row.get("type") not in ("selector", "urltest", "block", "dns"):
                row["bind_interface"] = _interface()
    if native:
        if not entries:
            raise ValueError("Native sing-box configuration needs an outbound or endpoint")
        tags = {row.get("tag") for row in entries}
        first = entries[0]
        if not first.get("tag"):
            if "wproxy-default" in tags:
                raise ValueError("Native config uses the reserved wproxy-default tag")
            first["tag"] = "wproxy-default"
        proxy = route.get("final") or first["tag"]
        if policy["mode"] != "all":
            direct = "wproxy-direct"
            if direct in tags:
                raise ValueError("Native config uses the reserved wproxy-direct tag")
            outbounds.append({"type": "direct", "tag": direct})
            overlay = _sing_routes(policy, direct, proxy)
            if policy["mode"] == "only":
                overlay.append({"action": "route", "outbound": direct})
            route["rules"] = overlay + route.get("rules", [])
    else:
        proxy = "proxy"
        route["rules"] = [{"action": "sniff"}] + _sing_routes(policy, "direct", proxy)
        route["final"] = "direct" if policy["mode"] == "only" else proxy
    if platform == "windows" and not probe_port:
        if "dns" not in config:
            direct = "wproxy-dns-direct"
            if any(row.get("tag") == direct for row in entries):
                raise ValueError("Native config uses the reserved wproxy-dns-direct tag")
            outbounds.append({"type": "direct", "tag": direct})
            config["dns"] = {"servers": [
                {"type": "udp", "tag": "wproxy-bootstrap", "server": "1.1.1.1", "detour": direct},
                {"type": "https", "tag": "wproxy-dns", "server": "1.1.1.1", "detour": proxy},
            ], "final": "wproxy-dns"}
            route.setdefault("default_domain_resolver", "wproxy-bootstrap")
        route.setdefault("rules", []).insert(0, {"protocol": "dns", "action": "hijack-dns"})
    return config


def _xray_native(value, policy, platform, legacy, probe_port=None):
    config = copy.deepcopy(value)
    inbound_tag = _ingress_tag(config, "xray")
    config["log"] = {"loglevel": "warning"}
    for field in ("api", "metrics", "stats", "observatory", "burstObservatory"):
        config.pop(field, None)
    sample = legacy.xray_config("trojan://wproxy@example.invalid:443", routing={"mode": "all"}, platform=platform)
    config["inbounds"] = [{"tag": "wproxy-in", "listen": "127.0.0.1", "port": probe_port, "protocol": "http"}] if probe_port else sample["inbounds"]
    config["inbounds"][0]["tag"] = inbound_tag
    outbounds = config.get("outbounds", [])
    if not outbounds:
        raise ValueError("Native Xray configuration needs an outbound")
    first = outbounds[0]
    if not first.get("tag"):
        if any(row.get("tag") == "wproxy-default" for row in outbounds):
            raise ValueError("Native config uses the reserved wproxy-default tag")
        first["tag"] = "wproxy-default"
    proxy = first["tag"]
    if policy["mode"] != "all":
        if any(row.get("tag") == "wproxy-direct" for row in outbounds):
            raise ValueError("Native config uses the reserved wproxy-direct tag")
        outbounds.append({"tag": "wproxy-direct", "protocol": "freedom"})
        overlay = legacy.routing_rules(policy)
        for rule in overlay:
            if rule.get("outboundTag") == "direct":
                rule["outboundTag"] = "wproxy-direct"
            elif rule.get("outboundTag") == "proxy":
                rule["outboundTag"] = proxy
        config.setdefault("routing", {}).setdefault("rules", [])[:0] = overlay
    if platform == "linux" and _interface():
        for row in outbounds:
            if row.get("protocol") != "blackhole":
                row.setdefault("streamSettings", {}).setdefault("sockopt", {})["interface"] = _interface()
    return config


def _mihomo_config(value, policy, platform, probe_port=None):
    config = copy.deepcopy(value)
    if config.get("script"):
        raise ValueError("Clash scripts are not supported by the WProxy Mihomo adapter")
    config.update({"find-process-mode": "strict", "allow-lan": False, "bind-address": "127.0.0.1", "log-level": "warning", "ipv6": True,
                   "port": probe_port or 0, "mixed-port": 0, "socks-port": 0, "redir-port": 0, "tproxy-port": 0})
    for field in ("external-controller", "external-controller-tls", "external-controller-unix", "external-controller-pipe", "external-ui", "external-ui-url", "listeners", "authentication"):
        config.pop(field, None)
    config["tun"] = {"enable": not bool(probe_port), "device": "wproxy" if platform == "windows" else "wproxy0", "stack": "mixed",
                     "auto-route": platform == "windows", "auto-detect-interface": platform == "windows", "mtu": 1400 if platform == "windows" else 1500,
                     "inet6-address": ["fdfe:dcba:9876::1/126"]}
    if platform == "linux" and _interface():
        config["interface-name"] = _interface()
        for row in config.get("proxies", []):
            row["interface-name"] = _interface()
    # NM owns Linux DNS; Windows must resolve via the tunnel itself.
    if platform == "windows" and not probe_port:
        dns = config.setdefault("dns", {})
        dns.update({"enable": True, "listen": "127.0.0.1:0"})
        dns.setdefault("nameserver", ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"])
        config["tun"]["dns-hijack"] = ["any:53", "tcp://any:53"]
    elif isinstance(config.get("dns"), dict):
        config["dns"]["listen"] = "127.0.0.1:0"
    for key in ("proxy-providers", "rule-providers"):
        for name, provider in config.get(key, {}).items():
            if not isinstance(provider, dict):
                raise ValueError("Invalid Clash provider")
            if provider.get("type") == "file":
                raise ValueError("File-based Clash providers must be embedded or use an HTTPS provider URL")
            if provider.get("url") and not str(provider["url"]).startswith("https://"):
                raise ValueError("Clash provider downloads require HTTPS")
            if key == "proxy-providers" and platform == "linux" and _interface():
                provider.setdefault("override", {})["interface-name"] = _interface()
            provider["path"] = "./providers/" + hashlib.sha256((key + name).encode()).hexdigest() + ".yaml"
    if policy["mode"] != "all":
        groups = config.get("proxy-groups", [])
        proxy = next((row.get("name") for row in groups if isinstance(row, dict) and row.get("name")), None)
        proxy = proxy or next((row.get("name") for row in config.get("proxies", []) if isinstance(row, dict)), None)
        if not proxy:
            raise ValueError("Clash split routing requires a named proxy or group")
        target = "DIRECT" if policy["mode"] == "bypass" else proxy
        if "," in target or any("," in application for application in policy["apps"]):
            raise ValueError("Clash split routing does not support commas in application paths or group names")
        overlay = []
        for domain in policy["domains"]:
            try:
                address = ipaddress.ip_address(domain)
                overlay.append(f"{'IP-CIDR6' if address.version == 6 else 'IP-CIDR'},{domain}/{128 if address.version == 6 else 32},{target},no-resolve")
            except ValueError:
                overlay.append(f"DOMAIN-SUFFIX,{domain},{target}")
        overlay.extend(f"PROCESS-PATH,{application},{target}" for application in policy["apps"])
        if policy["mode"] == "only":
            overlay.append("MATCH,DIRECT")
        config["mode"] = "rule"
        config["rules"] = overlay + config.get("rules", [])
    return config


def prepare(uri, routing, platform, legacy, server_ip=None, probe_port=None):
    info = analyze(uri)
    policy = legacy.normalize_routing_policy(routing)
    if probe_port:
        policy = {"mode": "all", "domains": [], "apps": []}
    native_value = _document(unpack_native(uri)["text"])[1] if info["format"] != "uri" else None
    missing = []
    for engine in info["candidates"]:
        try:
            binary = find_binary(engine, platform)
            version = _version(engine, binary)
            minimum = {"sing-box": (1, 12, 0), "mihomo": (1, 19, 0), "xray": (26, 9, 30)}[engine]
            actual = tuple(int(part) for part in version.split("-")[0].split("+")[0].split(".")[:3])
            if actual < minimum:
                raise RuntimeError(f"{engine} {version} is too old; reinstall WProxy with its bundled cores.")
        except RuntimeError as error:
            missing.append(str(error))
            continue
        try:
            if engine == "xray":
                config = _xray_native(native_value, policy, platform, legacy, probe_port) if native_value is not None else legacy.xray_config(uri, server_ip, policy, platform)
                if probe_port and native_value is None:
                    config["inbounds"] = [{"tag": "wproxy-in", "listen": "127.0.0.1", "port": probe_port, "protocol": "http"}]
            elif engine == "sing-box":
                if native_value is None:
                    outbound = _sing_outbound(uri, legacy)
                    if server_ip:
                        if outbound["type"] == "wireguard":
                            outbound["peers"][0]["address"] = server_ip
                        else:
                            outbound["server"] = server_ip
                    value = {"outbounds": [{"type": "direct", "tag": "direct"}]}
                    if outbound["type"] == "wireguard":
                        value["endpoints"] = [outbound]
                    else:
                        value["outbounds"].insert(0, outbound)
                else:
                    value = native_value
                config = _sing_config(value, policy, platform, probe_port, native=native_value is not None)
            else:
                config = _mihomo_config(native_value, policy, platform, probe_port)
            plan = SimpleNamespace(engine=engine, binary=binary, config=config, version=version, validated=False)
            with tempfile.TemporaryDirectory(prefix="wproxy-select-") as directory:
                validate(plan, Path(directory) / "config.json")
            return plan
        except (ValueError, RuntimeError) as error:
            missing.append(str(error))
            continue
    raise RuntimeError(" ".join(missing) or "No compatible engine is available for this configuration")
