#!/usr/bin/env python3
import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
import pwd
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

APP = "wproxy"
SERVICE = "org.freedesktop.NetworkManager.wproxy"
PREFIX = "WProxy · "
USER_AGENT = "WProxy/2.3.0 (+NetworkManager; v2rayNG-compatible subscription reader)"


def original_user():
    if os.geteuid() != 0:
        return pwd.getpwuid(os.getuid())
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user and sudo_user != "root":
        try:
            return pwd.getpwnam(sudo_user)
        except KeyError:
            pass
    pk_uid = os.environ.get("PKEXEC_UID")
    if pk_uid and pk_uid.isdigit():
        try:
            return pwd.getpwuid(int(pk_uid))
        except KeyError:
            pass
    return pwd.getpwuid(0)


def config_home():
    p = original_user()
    xdg = os.environ.get("XDG_CONFIG_HOME") if os.geteuid() != 0 else None
    base = Path(xdg) if xdg else Path(p.pw_dir) / ".config"
    return base / APP


def store_path():
    return config_home() / "store.json"


def load_store():
    p = store_path()
    if not p.exists():
        return {"subs": [], "nodes": []}
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
        data.setdefault("subs", [])
        data.setdefault("nodes", [])
        return data
    except Exception as e:
        print(f"Could not read {p}: {e}", file=sys.stderr)
        return {"subs": [], "nodes": []}


def save_store(data):
    p = store_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(p)
    if os.geteuid() == 0:
        u = original_user()
        try:
            os.chown(p, u.pw_uid, u.pw_gid)
            os.chown(p.parent, u.pw_uid, u.pw_gid)
        except PermissionError:
            pass


def stable_id(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def b64decode_text(value):
    raw = re.sub(r"\s+", "", value or "")
    if not raw:
        raise ValueError("empty base64")
    raw += "=" * (-len(raw) % 4)
    last = None
    for fn in (base64.urlsafe_b64decode, base64.b64decode):
        try:
            return fn(raw.encode()).decode("utf-8")
        except Exception as e:
            last = e
    raise ValueError(str(last))


def maybe_decode_subscription(body):
    text = body.strip().lstrip("\ufeff")
    if "://" in text:
        return text
    try:
        decoded = b64decode_text(text)
        if "://" in decoded:
            return decoded
    except Exception:
        pass
    return text


def clean_name(name, fallback):
    name = urllib.parse.unquote(name or "").strip()
    name = re.sub(r"[\r\n\t]+", " ", name)
    name = re.sub(r"\s{2,}", " ", name)
    return name[:80] or fallback


def vmess_payload(uri):
    payload = uri[len("vmess://"):].strip()
    text = b64decode_text(payload)
    obj = json.loads(text)
    if not isinstance(obj, dict):
        raise ValueError("VMess payload is not an object")
    return obj


def ss_parts(uri):
    raw = uri[len("ss://"):]
    fragment = ""
    if "#" in raw:
        raw, fragment = raw.split("#", 1)
    query = ""
    if "?" in raw:
        raw, query = raw.split("?", 1)
    raw = raw.strip()

    # SIP002: base64(method:password)@host:port
    if "@" in raw:
        userinfo, hostport = raw.rsplit("@", 1)
        try:
            credentials = b64decode_text(userinfo)
        except Exception:
            credentials = urllib.parse.unquote(userinfo)
        if ":" not in credentials:
            raise ValueError("Invalid Shadowsocks credentials")
        method, password = credentials.split(":", 1)
    else:
        decoded = b64decode_text(raw)
        if "@" not in decoded:
            raise ValueError("Invalid Shadowsocks URI")
        credentials, hostport = decoded.rsplit("@", 1)
        if ":" not in credentials:
            raise ValueError("Invalid Shadowsocks credentials")
        method, password = credentials.split(":", 1)

    if hostport.startswith("["):
        end = hostport.find("]")
        if end < 0:
            raise ValueError("Invalid IPv6 host")
        host = hostport[1:end]
        port = int(hostport[end + 2:])
    else:
        host, port_s = hostport.rsplit(":", 1)
        port = int(port_s)
    return method, urllib.parse.unquote(password), host, port, urllib.parse.unquote(fragment), query


def endpoint_from_uri(uri):
    try:
        if uri.startswith("vmess://"):
            o = vmess_payload(uri)
            return str(o.get("add", "")), int(o.get("port", 0))
        if uri.startswith("ss://"):
            _, _, host, port, _, _ = ss_parts(uri)
            return host, port
        u = urllib.parse.urlsplit(uri)
        return u.hostname or "", int(u.port or 0)
    except Exception:
        return "", 0


def node_name(uri, index=0):
    try:
        if uri.startswith("vmess://"):
            o = vmess_payload(uri)
            return clean_name(o.get("ps"), f"Proxy {index + 1}")
        if uri.startswith("ss://"):
            *_, frag, _ = ss_parts(uri)
            return clean_name(frag, f"Proxy {index + 1}")
        u = urllib.parse.urlsplit(uri)
        return clean_name(u.fragment, f"Proxy {index + 1}")
    except Exception:
        return f"Proxy {index + 1}"


def make_unique_name(base, existing):
    if base not in existing:
        return base
    n = 2
    while f"{base} ({n})" in existing:
        n += 1
    return f"{base} ({n})"


def parse_sub_userinfo(value):
    out = {}
    if not value:
        return out
    for part in value.split(";"):
        if "=" not in part:
            continue
        k, v = part.strip().split("=", 1)
        k = k.strip().lower()
        v = v.strip()
        try:
            out[k] = int(v)
        except ValueError:
            out[k] = v
    if all(isinstance(out.get(k), int) for k in ("upload", "download", "total")):
        out["remaining"] = max(0, out["total"] - out["upload"] - out["download"])
    return out


def format_bytes(num):
    if num is None:
        return None
    n = float(num)
    for unit in ("B", "KB", "MB", "GB", "TB", "PB"):
        if abs(n) < 1024.0 or unit == "PB":
            return f"{n:.2f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024.0


def fetch_subscription(sub):
    req = urllib.request.Request(sub["url"], headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=20) as r:
        body = r.read().decode("utf-8", errors="replace")
        userinfo = r.headers.get("subscription-userinfo") or r.headers.get("Subscription-Userinfo")
        profile_title = r.headers.get("profile-title") or r.headers.get("Profile-Title")
    text = maybe_decode_subscription(body)
    uris = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if re.match(r"^(vless|vmess|trojan|ss)://", line, re.I):
            uris.append(line)
    if not uris:
        raise ValueError("Subscription did not contain supported vless/vmess/trojan/ss links")
    return uris, parse_sub_userinfo(userinfo), profile_title


def add_or_replace_nodes(store, uris, source=None):
    if source:
        store["nodes"] = [n for n in store["nodes"] if n.get("source") != source]
    existing_names = {n.get("name", "") for n in store["nodes"]}
    known_ids = {n.get("id") for n in store["nodes"]}
    added = 0
    for i, uri in enumerate(uris):
        uri = uri.strip()
        nid = stable_id(uri)
        if nid in known_ids:
            continue
        name = make_unique_name(node_name(uri, i), existing_names)
        store["nodes"].append({"id": nid, "name": name, "uri": uri, "source": source})
        known_ids.add(nid)
        existing_names.add(name)
        added += 1
    return added


def parse_query(u):
    return {k: v[-1] for k, v in urllib.parse.parse_qs(u.query, keep_blank_values=True).items()}


def bool_q(v):
    return str(v or "").lower() in ("1", "true", "yes", "on")


def stream_settings(query, host, default_security="none", vmess=None):
    if vmess is not None:
        network = str(vmess.get("net") or "tcp").lower()
        security = str(vmess.get("tls") or "none").lower()
        q = {
            "host": str(vmess.get("host") or ""),
            "path": str(vmess.get("path") or ""),
            "sni": str(vmess.get("sni") or ""),
            "fp": str(vmess.get("fp") or ""),
            "type": str(vmess.get("type") or ""),
            "alpn": str(vmess.get("alpn") or ""),
        }
    else:
        q = query
        network = str(q.get("type") or q.get("network") or "tcp").lower()
        security = str(q.get("security") or default_security).lower()

    if network in ("http", "h2"):
        network = "tcp"
    if network == "splithttp":
        network = "xhttp"

    method_map = {
        "tcp": "raw",
        "raw": "raw",
        "ws": "websocket",
        "websocket": "websocket",
        "grpc": "grpc",
        "httpupgrade": "httpupgrade",
        "xhttp": "xhttp",
        "kcp": "mkcp",
        "mkcp": "mkcp",
        "hysteria": "hysteria",
    }
    method = method_map.get(network, network)
    st = {"method": method, "security": security if security in ("tls", "reality") else "none"}

    path = urllib.parse.unquote(q.get("path") or "/")
    host_header = urllib.parse.unquote(q.get("host") or "")
    if method == "websocket":
        ws = {"path": path}
        if host_header:
            # Current Xray exposes an explicit WebSocket host field.
            ws["host"] = host_header
        st["wsSettings"] = ws
    elif method == "grpc":
        grpc = {"serviceName": urllib.parse.unquote(q.get("serviceName") or q.get("service") or "")}
        if q.get("authority"):
            grpc["authority"] = urllib.parse.unquote(q["authority"])
        if q.get("mode") == "multi":
            grpc["multiMode"] = True
        st["grpcSettings"] = grpc
    elif method == "httpupgrade":
        hu = {"path": path}
        if host_header:
            hu["host"] = host_header
        st["httpupgradeSettings"] = hu
    elif method == "xhttp":
        xh = {"path": path}
        if host_header:
            xh["host"] = host_header
        if q.get("mode"):
            xh["mode"] = q["mode"]
        st["xhttpSettings"] = xh
    elif method == "mkcp":
        header = q.get("headerType") or q.get("header") or "none"
        st["kcpSettings"] = {"header": {"type": header}}
    elif method == "raw" and q.get("headerType") in ("http",):
        # Legacy share links may still request the old TCP HTTP header.
        st["rawSettings"] = {"header": {"type": "http"}}

    if st["security"] == "reality" and method not in ("raw", "xhttp", "grpc"):
        raise ValueError(f"REALITY is not compatible with Xray transport method {method}")
    if method == "hysteria" and st["security"] != "tls":
        raise ValueError("Xray Hysteria transport requires TLS")

    sni = urllib.parse.unquote(q.get("sni") or q.get("serverName") or host)
    fp = q.get("fp") or ""
    alpn = [x for x in (q.get("alpn") or "").split(",") if x]

    if st["security"] == "tls":
        tls = {"serverName": sni}
        if fp:
            tls["fingerprint"] = fp
        if alpn:
            tls["alpn"] = alpn
        if bool_q(q.get("allowInsecure")):
            tls["allowInsecure"] = True
        st["tlsSettings"] = tls
    elif st["security"] == "reality":
        reality = {
            "serverName": sni,
            "fingerprint": fp or "chrome",
            "publicKey": q.get("pbk") or q.get("publicKey") or "",
            "shortId": q.get("sid") or q.get("shortId") or "",
        }
        spx = q.get("spx") or q.get("spiderX")
        if spx:
            reality["spiderX"] = urllib.parse.unquote(spx)
        st["realitySettings"] = reality
    return st


def outbound_from_uri(uri):
    if uri.startswith("vless://"):
        u = urllib.parse.urlsplit(uri)
        q = parse_query(u)
        if not u.hostname or not u.port or not u.username:
            raise ValueError("VLESS link is missing server, port, or UUID")
        user = {"id": urllib.parse.unquote(u.username), "encryption": q.get("encryption") or "none"}
        if q.get("flow"):
            user["flow"] = q["flow"]
        return {
            "tag": "proxy",
            "protocol": "vless",
            "settings": {"vnext": [{"address": u.hostname, "port": u.port, "users": [user]}]},
            "streamSettings": stream_settings(q, u.hostname, "none"),
        }

    if uri.startswith("trojan://"):
        u = urllib.parse.urlsplit(uri)
        q = parse_query(u)
        if not u.hostname or not u.port or u.username is None:
            raise ValueError("Trojan link is missing server, port, or password")
        server = {"address": u.hostname, "port": u.port, "password": urllib.parse.unquote(u.username)}
        return {
            "tag": "proxy",
            "protocol": "trojan",
            "settings": {"servers": [server]},
            "streamSettings": stream_settings(q, u.hostname, "tls"),
        }

    if uri.startswith("vmess://"):
        o = vmess_payload(uri)
        host = str(o.get("add") or "")
        port = int(o.get("port") or 0)
        uid = str(o.get("id") or "")
        if not host or not port or not uid:
            raise ValueError("VMess link is missing server, port, or UUID")
        user = {
            "id": uid,
            "alterId": int(o.get("aid") or 0),
            "security": str(o.get("scy") or o.get("security") or "auto"),
        }
        return {
            "tag": "proxy",
            "protocol": "vmess",
            "settings": {"vnext": [{"address": host, "port": port, "users": [user]}]},
            "streamSettings": stream_settings({}, host, vmess=o),
        }

    if uri.startswith("ss://"):
        method, password, host, port, _, query = ss_parts(uri)
        if query:
            qs = urllib.parse.parse_qs(query)
            if qs.get("plugin"):
                raise ValueError("Shadowsocks plugin links are not supported by the Xray backend")
        return {
            "tag": "proxy",
            "protocol": "shadowsocks",
            "settings": {"servers": [{"address": host, "port": port, "method": method, "password": password}]},
        }

    raise ValueError("Unsupported URI. Supported: vless:// vmess:// trojan:// ss://")


def xray_config(uri, server_ip=None):
    proxy = outbound_from_uri(uri)
    # Pin the endpoint resolved before TUN starts. TLS SNI / WS Host still use
    # the original hostname. This avoids resolving the server through itself.
    if server_ip:
        settings = proxy["settings"]
        endpoints = settings.get("vnext") or settings.get("servers")
        endpoints[0]["address"] = server_ip
    direct = {"tag": "direct", "protocol": "freedom"}
    interface = os.environ.get("WPROXY_OUT_IFACE", "").strip()
    if interface:
        if interface == "wproxy0" or not re.fullmatch(r"[a-zA-Z0-9_.:-]{1,15}", interface):
            raise ValueError("Invalid physical outbound interface")
        for outbound in (proxy, direct):
            outbound.setdefault("streamSettings", {}).setdefault("sockopt", {})["interface"] = interface
    return {
        "log": {"loglevel": "warning"},
        "inbounds": [{
            "tag": "tun-in",
            "protocol": "tun",
            "settings": {
                "name": "wproxy0",
                "MTU": 1500
            },
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}
        }],
        "outbounds": [
            proxy,
            direct,
            {"tag": "block", "protocol": "blackhole"}
        ],
        "routing": {
            "domainStrategy": "AsIs",
            "rules": [
                {"type": "field", "ip": ["10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "::1/128", "fc00::/7", "fe80::/10"], "outboundTag": "direct"}
            ]
        }
    }


def write_gateway_metadata(uri, destination):
    # Resolve before starting TUN, using the same parser as ping/config import.
    host, port = endpoint_from_uri(uri)
    if not host or not port:
        raise ValueError('The selected server has no valid endpoint')
    try:
        endpoints = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except OSError as e:
        raise RuntimeError(f'Could not resolve the selected server: {e}') from e
    endpoints.sort(key=lambda entry: entry[0] != socket.AF_INET)
    if not endpoints:
        raise RuntimeError('No address was found for the selected server')
    path = Path(destination)
    path.write_text(endpoints[0][4][0] + '\n', encoding='ascii')
    os.chmod(path, 0o600)
    return endpoints[0][4][0]


def deterministic_uuid(node_id):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"wproxy:{original_user().pw_uid}:{node_id}"))


def escape_keyfile_value(value):
    return value.replace("\\", "\\\\").replace("\n", "").replace("\r", "")


def nm_keyfile(node):
    u = original_user()
    cid = PREFIX + node["name"]
    cuuid = deterministic_uuid(node["id"])
    uri = escape_keyfile_value(node["uri"])
    return f"""[connection]\nid={cid}\nuuid={cuuid}\ntype=vpn\nautoconnect=false\n\n[vpn]\nservice-type={SERVICE}\nuser-name={uri}\nuri={uri}\nwproxy-version=2.3.0\nnode-id={node['id']}\npersistent=false\n\n[ipv4]\nmethod=auto\nnever-default=false\n\n[ipv6]\nmethod=auto\nnever-default=false\n"""


def require_root():
    if os.geteuid() != 0:
        print("This command changes NetworkManager system connections. Run: sudo wproxyctl nm sync", file=sys.stderr)
        sys.exit(4)


def run(cmd, check=False, capture=False):
    return subprocess.run(cmd, check=check, text=True, capture_output=capture)


def nm_sync(store):
    require_root()
    conn_dir = Path("/etc/NetworkManager/system-connections")
    conn_dir.mkdir(parents=True, exist_ok=True)
    uid = original_user().pw_uid
    wanted = set()
    for node in store["nodes"]:
        fn = conn_dir / f"wproxy-{uid}-{node['id']}.nmconnection"
        wanted.add(fn.name)
        fn.write_text(nm_keyfile(node), encoding="utf-8")
        os.chmod(fn, 0o600)
        print(f"Synced {node['name']}")
    for old in conn_dir.glob(f"wproxy-{uid}-*.nmconnection"):
        if old.name not in wanted:
            old.unlink(missing_ok=True)
            print(f"Removed stale {old.name}")
    # Remove legacy profiles created by WProxy 1.0 if they contain our service marker.
    for old in conn_dir.glob("wproxy-*.nmconnection"):
        if old.name.startswith(f"wproxy-{uid}-"):
            continue
        try:
            if SERVICE in old.read_text(encoding="utf-8", errors="ignore"):
                old.unlink(missing_ok=True)
        except OSError:
            pass
    run(["nmcli", "connection", "reload"])
    # WProxy VPN service does not support NetworkManager private/user-only
    # connections. Keep every generated profile system-wide. This also
    # repairs profiles created by WProxy <= 2.2.3.
    for node in store["nodes"]:
        cuuid = deterministic_uuid(node["id"])
        run(["nmcli", "connection", "modify", "uuid", cuuid, "connection.permissions", ""])
    run(["nmcli", "connection", "reload"])


def active_wproxy_names():
    p = run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"], capture=True)
    names = []
    if p.returncode != 0:
        return names
    for line in p.stdout.splitlines():
        # nmcli escapes literal colons as \:
        parts = re.split(r"(?<!\\):", line, maxsplit=1)
        if len(parts) == 2 and parts[1] == "vpn":
            name = parts[0].replace("\\:", ":").replace("\\\\", "\\")
            if name.startswith(PREFIX):
                names.append(name)
    return names


def nm_down():
    ok = True
    for name in active_wproxy_names():
        p = run(["nmcli", "connection", "down", "id", name])
        ok = ok and p.returncode == 0
    return ok


def nm_up(store, node_id):
    node = next((n for n in store["nodes"] if n["id"] == node_id), None)
    if not node:
        raise ValueError("Unknown node id")
    nm_down()
    cuuid = deterministic_uuid(node_id)
    p = run(["nmcli", "--wait", "25", "connection", "up", "uuid", cuuid], capture=True)
    if p.returncode != 0:
        # Preserve the actual failure. A generic 'sync first' error made the
        # extension re-import every profile after unrelated runtime failures.
        raise RuntimeError(p.stderr.strip() or p.stdout.strip() or 'VPN activation failed')
    if p.stdout:
        print(p.stdout, end='')


def status_json(store):
    active = active_wproxy_names()
    active_name = active[0] if active else None
    active_node = None
    if active_name:
        short = active_name[len(PREFIX):]
        active_node = next((n for n in store["nodes"] if n.get("name") == short), None)
    return {
        "active": bool(active),
        "name": active_name,
        "node_id": active_node.get("id") if active_node else None,
        "nodes": len(store["nodes"]),
        "subscriptions": len(store["subs"]),
    }


def ping_node(node, timeout):
    host, port = endpoint_from_uri(node["uri"])
    if not host or not port:
        return None
    start = time.perf_counter()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            pass
        return int((time.perf_counter() - start) * 1000)
    except OSError:
        return None


def cmd_sub(args, store):
    if args.action == "add":
        sid = stable_id(args.url)
        if any(s["id"] == sid for s in store["subs"]):
            # Keep this command idempotent; GUI callers need the ID even when it already exists.
            print(sid)
            return
        store["subs"].append({"id": sid, "name": args.name or "Subscription", "url": args.url, "usage": {}})
        save_store(store)
        print(sid)
    elif args.action == "list":
        rows = []
        for s in store["subs"]:
            x = dict(s)
            rem = (s.get("usage") or {}).get("remaining")
            x["remaining_human"] = format_bytes(rem)
            rows.append(x)
        if args.json:
            public_rows = []
            for s in rows:
                public_rows.append({
                    "id": s["id"],
                    "name": s.get("name", "Subscription"),
                    "usage": s.get("usage") or {},
                    "remaining_human": s.get("remaining_human"),
                    "updated_at": s.get("updated_at"),
                })
            print(json.dumps(public_rows, ensure_ascii=False))
        else:
            for s in rows:
                extra = f"  {s['remaining_human']} left" if s.get("remaining_human") else ""
                print(f"{s['id']}  {s.get('name','Subscription')}  {s['url']}{extra}")
    elif args.action == "remove":
        store["subs"] = [s for s in store["subs"] if s["id"] != args.id]
        store["nodes"] = [n for n in store["nodes"] if n.get("source") != args.id]
        save_store(store)
    elif args.action == "update":
        targets = [s for s in store["subs"] if not args.id or s["id"] == args.id]
        if args.id and not targets:
            raise ValueError("Unknown subscription id")
        failures = 0
        for sub in targets:
            try:
                uris, usage, title = fetch_subscription(sub)
                if title:
                    raw_title = title[7:] if title.lower().startswith("base64:") else title
                    try:
                        title = b64decode_text(raw_title)
                    except Exception:
                        title = urllib.parse.unquote(title)
                    sub["name"] = clean_name(title, sub.get("name", "Subscription"))
                sub["usage"] = usage
                sub["updated_at"] = int(time.time())
                added = add_or_replace_nodes(store, uris, sub["id"])
                print(f"Updated {sub['name']}: {added} nodes")
            except Exception as e:
                failures += 1
                print(f"{sub.get('name', sub['id'])}: {e}", file=sys.stderr)
        save_store(store)
        if failures:
            sys.exit(2)


def cmd_node(args, store):
    if args.action == "add":
        # Validate early by rendering the outbound.
        outbound_from_uri(args.uri)
        nid = stable_id(args.uri)
        if any(n["id"] == nid for n in store["nodes"]):
            print(nid)
            return
        existing = {n.get("name", "") for n in store["nodes"]}
        name = make_unique_name(args.name or node_name(args.uri, len(store["nodes"])), existing)
        store["nodes"].append({"id": nid, "name": clean_name(name, "Proxy"), "uri": args.uri, "source": None})
        save_store(store)
        print(nid)
    elif args.action == "list":
        if args.json:
            public_rows = [
                {"id": n["id"], "name": n["name"], "source": n.get("source")}
                for n in store["nodes"]
            ]
            print(json.dumps(public_rows, ensure_ascii=False))
        else:
            for n in store["nodes"]:
                source = n.get("source") or "manual"
                print(f"{n['id']}  {n['name']}  [{source}]  {n['uri']}")
    elif args.action == "remove":
        store["nodes"] = [n for n in store["nodes"] if n["id"] != args.id]
        save_store(store)
    elif args.action == "rename":
        node = next((n for n in store["nodes"] if n["id"] == args.id), None)
        if not node:
            raise ValueError("Unknown node id")
        node["name"] = clean_name(args.name, node["name"])
        save_store(store)
    elif args.action == "ping":
        targets = store["nodes"] if args.all else [next((n for n in store["nodes"] if n["id"] == args.id), None)]
        targets = [n for n in targets if n]
        if not targets:
            raise ValueError("No matching node")
        rows = []
        workers = min(16, max(1, len(targets)))
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            future_map = {pool.submit(ping_node, n, args.timeout): n for n in targets}
            for fut in concurrent.futures.as_completed(future_map):
                n = future_map[fut]
                try:
                    ms = fut.result()
                except Exception:
                    ms = None
                rows.append({"id": n["id"], "name": n["name"], "latency_ms": ms})
        order = {n["id"]: i for i, n in enumerate(targets)}
        rows.sort(key=lambda r: order.get(r["id"], 0))
        if args.json:
            print(json.dumps(rows, ensure_ascii=False))
        else:
            for r in rows:
                print(f"{r['id']}  {r['name']}  {r['latency_ms'] if r['latency_ms'] is not None else 'timeout'}")


def build_parser():
    p = argparse.ArgumentParser(prog="wproxyctl", description="WProxy configuration and NetworkManager controller")
    p.add_argument("--version", action="version", version="WProxy 2.3.0")
    sp = p.add_subparsers(dest="cmd", required=True)

    ps = sp.add_parser("sub")
    ss = ps.add_subparsers(dest="action", required=True)
    a = ss.add_parser("add"); a.add_argument("url"); a.add_argument("--name")
    a = ss.add_parser("list"); a.add_argument("--json", action="store_true")
    a = ss.add_parser("update"); a.add_argument("id", nargs="?")
    a = ss.add_parser("remove"); a.add_argument("id")

    pn = sp.add_parser("node")
    ns = pn.add_subparsers(dest="action", required=True)
    a = ns.add_parser("add"); a.add_argument("uri"); a.add_argument("--name")
    a = ns.add_parser("list"); a.add_argument("--json", action="store_true")
    a = ns.add_parser("remove"); a.add_argument("id")
    a = ns.add_parser("rename"); a.add_argument("id"); a.add_argument("name")
    a = ns.add_parser("ping"); a.add_argument("id", nargs="?"); a.add_argument("--all", action="store_true"); a.add_argument("--json", action="store_true"); a.add_argument("--timeout", type=float, default=2.0)

    pm = sp.add_parser("nm")
    ms = pm.add_subparsers(dest="action", required=True)
    ms.add_parser("sync")
    a = ms.add_parser("up"); a.add_argument("id")
    ms.add_parser("down")

    a = sp.add_parser("status"); a.add_argument("--json", action="store_true")
    a = sp.add_parser("render"); a.add_argument("uri"); a.add_argument("--output", "-o")
    a.add_argument('--gateway-output')
    return p


def main():
    args = build_parser().parse_args()
    store = load_store()
    try:
        if args.cmd == "sub":
            cmd_sub(args, store)
        elif args.cmd == "node":
            cmd_node(args, store)
        elif args.cmd == "nm":
            if args.action == "sync": nm_sync(store)
            elif args.action == "up": nm_up(store, args.id)
            elif args.action == "down": sys.exit(0 if nm_down() else 1)
        elif args.cmd == "status":
            data = status_json(store)
            if args.json: print(json.dumps(data, ensure_ascii=False))
            else: print("connected" if data["active"] else "disconnected", data.get("name") or "")
        elif args.cmd == "render":
            server_ip = None
            if args.gateway_output:
                server_ip = write_gateway_metadata(args.uri, args.gateway_output)
            cfg = json.dumps(xray_config(args.uri, server_ip), indent=2, ensure_ascii=False) + "\n"
            if args.output:
                Path(args.output).write_text(cfg, encoding="utf-8")
            else:
                sys.stdout.write(cfg)
    except (ValueError, RuntimeError) as e:
        print(str(e), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
