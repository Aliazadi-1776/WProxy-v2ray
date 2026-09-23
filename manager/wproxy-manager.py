#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import threading

import gi
gi.require_version('Gtk', '4.0')
from gi.repository import GLib, Gtk

def _resolve_ctl():
    env = os.environ.get('WPROXYCTL')
    candidates = [env, shutil.which('wproxyctl'), '/usr/bin/wproxyctl', '/usr/local/bin/wproxyctl']
    for candidate in candidates:
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return '/usr/bin/wproxyctl'


CTL = _resolve_ctl()


def run(args):
    try:
        p = subprocess.run(args, text=True, capture_output=True)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except FileNotFoundError as e:
        missing = e.filename or (args[0] if args else 'command')
        return 127, '', f'Required command is missing: {missing}. Re-run WProxy installer or runtime repair.'
    except PermissionError as e:
        return 126, '', f'Cannot execute {e.filename or (args[0] if args else "command")}: permission denied'


class WProxyManager(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='local.wrench.WProxyManager')
        self.window = None
        self.status = None
        self.nodes_box = None
        self.subs_box = None
        self.uri_entry = None
        self.sub_entry = None
        self.stack = None

    def do_activate(self):
        if self.window:
            self.window.present()
            return

        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title('WProxy')
        self.window.set_default_size(720, 620)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.window.set_child(root)

        header = Gtk.HeaderBar()
        title = Gtk.Label(label='WProxy')
        title.add_css_class('title')
        header.set_title_widget(title)
        root.append(header)

        switcher = Gtk.StackSwitcher()
        switcher.set_margin_top(12)
        switcher.set_margin_bottom(8)
        switcher.set_margin_start(18)
        switcher.set_margin_end(18)
        root.append(switcher)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        switcher.set_stack(self.stack)
        root.append(self.stack)

        self.stack.add_titled(self._build_nodes_page(), 'nodes', 'Nodes')
        self.stack.add_titled(self._build_subs_page(), 'subscriptions', 'Subscriptions')
        self.stack.add_titled(self._build_add_page(), 'add', 'Add')

        self.status = Gtk.Label(label='')
        self.status.set_xalign(0)
        self.status.set_margin_top(8)
        self.status.set_margin_bottom(12)
        self.status.set_margin_start(18)
        self.status.set_margin_end(18)
        self.status.add_css_class('dim-label')
        root.append(self.status)

        self.refresh()
        self.window.present()

    def _page(self):
        scroller = Gtk.ScrolledWindow()
        scroller.set_vexpand(True)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(18)
        box.set_margin_start(18)
        box.set_margin_end(18)
        scroller.set_child(box)
        return scroller, box

    def _build_nodes_page(self):
        scroller, box = self._page()
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        refresh = Gtk.Button(label='Refresh')
        refresh.connect('clicked', lambda *_: self.refresh())
        ping = Gtk.Button(label='Ping all')
        ping.connect('clicked', lambda *_: self._ping_all())
        disconnect = Gtk.Button(label='Disconnect')
        disconnect.connect('clicked', lambda *_: self._background([CTL, 'nm', 'down'], 'Disconnected', True))
        top.append(refresh); top.append(ping); top.append(disconnect)
        box.append(top)

        self.nodes_box = Gtk.ListBox()
        self.nodes_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self.nodes_box.add_css_class('boxed-list')
        box.append(self.nodes_box)
        return scroller

    def _build_subs_page(self):
        scroller, box = self._page()
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        update = Gtk.Button(label='Update all')
        update.add_css_class('suggested-action')
        update.connect('clicked', lambda *_: self._update_all())
        sync = Gtk.Button(label='Sync to NetworkManager')
        sync.connect('clicked', lambda *_: self._sync_nm())
        top.append(update); top.append(sync)
        box.append(top)

        self.subs_box = Gtk.ListBox()
        self.subs_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self.subs_box.add_css_class('boxed-list')
        box.append(self.subs_box)
        return scroller

    def _build_add_page(self):
        scroller, box = self._page()

        title = Gtk.Label(label='Add a single configuration')
        title.set_xalign(0); title.add_css_class('title-3')
        box.append(title)
        desc = Gtk.Label(label='Supported links: VLESS, VMess, Trojan and Shadowsocks')
        desc.set_xalign(0); desc.add_css_class('dim-label')
        box.append(desc)
        self.uri_entry = Gtk.Entry()
        self.uri_entry.set_placeholder_text('vless://…  vmess://…  trojan://…  ss://…')
        box.append(self.uri_entry)
        btn = Gtk.Button(label='Add configuration')
        btn.add_css_class('suggested-action')
        btn.connect('clicked', self._add_node)
        box.append(btn)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        sep.set_margin_top(16); sep.set_margin_bottom(8)
        box.append(sep)

        title2 = Gtk.Label(label='Add a subscription')
        title2.set_xalign(0); title2.add_css_class('title-3')
        box.append(title2)
        desc2 = Gtk.Label(label='Paste a subscription URL. WProxy imports supported share links and stores subscription traffic info when the server provides it.')
        desc2.set_wrap(True); desc2.set_xalign(0); desc2.add_css_class('dim-label')
        box.append(desc2)
        self.sub_entry = Gtk.Entry()
        self.sub_entry.set_placeholder_text('https://example.com/subscription')
        box.append(self.sub_entry)
        btn2 = Gtk.Button(label='Add and update subscription')
        btn2.add_css_class('suggested-action')
        btn2.connect('clicked', self._add_sub)
        box.append(btn2)
        return scroller

    def _set_status(self, text):
        if self.status:
            self.status.set_text(text or '')

    def _clear_listbox(self, lb):
        child = lb.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            lb.remove(child)
            child = nxt

    def _load_json(self, args):
        code, out, err = run(args)
        if code != 0:
            raise RuntimeError(err or 'Command failed')
        return json.loads(out or '[]')

    def refresh(self):
        try:
            nodes = self._load_json([CTL, 'node', 'list', '--json'])
            subs = self._load_json([CTL, 'sub', 'list', '--json'])
            status = self._load_json([CTL, 'status', '--json'])
            self._render_nodes(nodes, status)
            self._render_subs(subs)
            self._set_status(status.get('name') if status.get('active') else 'Disconnected')
        except Exception as e:
            self._set_status(str(e))

    def _render_nodes(self, nodes, status):
        self._clear_listbox(self.nodes_box)
        active = status.get('node_id')
        if not nodes:
            row = Gtk.ListBoxRow()
            label = Gtk.Label(label='No configurations yet')
            label.set_margin_top(16); label.set_margin_bottom(16)
            row.set_child(label); self.nodes_box.append(row)
            return
        for n in nodes:
            row = Gtk.ListBoxRow()
            outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            outer.set_margin_top(10); outer.set_margin_bottom(10)
            outer.set_margin_start(12); outer.set_margin_end(12)
            labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            name = Gtk.Label(label=n.get('name', 'Proxy'))
            name.set_xalign(0)
            if n.get('id') == active: name.add_css_class('accent')
            source = Gtk.Label(label='Subscription' if n.get('source') else 'Manual')
            source.set_xalign(0); source.add_css_class('dim-label')
            labels.append(name); labels.append(source)
            labels.set_hexpand(True)
            outer.append(labels)

            connect = Gtk.Button(label='Connect')
            connect.connect('clicked', lambda _b, nid=n['id']: self._background([CTL, 'nm', 'up', nid], 'Connected', True))
            delete = Gtk.Button.new_from_icon_name('user-trash-symbolic')
            delete.set_tooltip_text('Remove')
            delete.connect('clicked', lambda _b, nid=n['id']: self._remove_node(nid))
            outer.append(connect); outer.append(delete)
            row.set_child(outer); self.nodes_box.append(row)

    def _render_subs(self, subs):
        self._clear_listbox(self.subs_box)
        if not subs:
            row = Gtk.ListBoxRow(); label = Gtk.Label(label='No subscriptions yet')
            label.set_margin_top(16); label.set_margin_bottom(16)
            row.set_child(label); self.subs_box.append(row); return
        for s in subs:
            row = Gtk.ListBoxRow()
            outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            outer.set_margin_top(10); outer.set_margin_bottom(10)
            outer.set_margin_start(12); outer.set_margin_end(12)
            labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            title = Gtk.Label(label=s.get('name') or 'Subscription'); title.set_xalign(0)
            subtitle_text = s.get('remaining_human') or 'Traffic information unavailable'
            subtitle = Gtk.Label(label=subtitle_text); subtitle.set_xalign(0); subtitle.add_css_class('dim-label')
            labels.append(title); labels.append(subtitle); labels.set_hexpand(True)
            outer.append(labels)
            update = Gtk.Button.new_from_icon_name('view-refresh-symbolic'); update.set_tooltip_text('Update')
            update.connect('clicked', lambda _b, sid=s['id']: self._update_sub(sid))
            delete = Gtk.Button.new_from_icon_name('user-trash-symbolic'); delete.set_tooltip_text('Remove')
            delete.connect('clicked', lambda _b, sid=s['id']: self._remove_sub(sid))
            outer.append(update); outer.append(delete)
            row.set_child(outer); self.subs_box.append(row)

    def _background(self, args, success, refresh=False):
        self._set_status('Working…')
        def worker():
            code, out, err = run(args)
            GLib.idle_add(self._after_background, code, out, err, success, refresh)
        threading.Thread(target=worker, daemon=True).start()

    def _after_background(self, code, out, err, success, refresh):
        self._set_status(success if code == 0 else (err or out or 'Command failed'))
        if refresh: self.refresh()
        return False

    def _sync_nm(self):
        self._background(['pkexec', CTL, 'nm', 'sync'], 'Synced to NetworkManager', True)

    def _add_node(self, *_):
        uri = self.uri_entry.get_text().strip()
        if not uri: return
        code, _, err = run([CTL, 'node', 'add', uri])
        if code != 0:
            self._set_status(err or 'Could not add configuration'); return
        self.uri_entry.set_text('')
        self._sync_nm()

    def _add_sub(self, *_):
        url = self.sub_entry.get_text().strip()
        if not url: return
        code, sid, err = run([CTL, 'sub', 'add', url])
        if code != 0:
            self._set_status(err or 'Could not add subscription'); return
        self.sub_entry.set_text('')
        self._set_status('Updating subscription…')
        def worker():
            c, o, e = run([CTL, 'sub', 'update', sid.strip()])
            if c == 0:
                c, o2, e2 = run(['pkexec', CTL, 'nm', 'sync'])
                o = o2 or o; e = e2 or e
            GLib.idle_add(self._after_background, c, o, e, 'Subscription added', True)
        threading.Thread(target=worker, daemon=True).start()

    def _remove_node(self, nid):
        code, _, err = run([CTL, 'node', 'remove', nid])
        if code != 0: self._set_status(err); return
        self._sync_nm()

    def _remove_sub(self, sid):
        code, _, err = run([CTL, 'sub', 'remove', sid])
        if code != 0: self._set_status(err); return
        self._sync_nm()

    def _update_sub(self, sid):
        self._set_status('Updating subscription…')
        def worker():
            c, o, e = run([CTL, 'sub', 'update', sid])
            if c == 0:
                c2, o2, e2 = run(['pkexec', CTL, 'nm', 'sync'])
                if c2 != 0:
                    c, o, e = c2, o2, e2
            GLib.idle_add(self._after_background, c, o, e, 'Subscription updated', True)
        threading.Thread(target=worker, daemon=True).start()

    def _update_all(self):
        self._set_status('Updating subscriptions…')
        def worker():
            c, o, e = run([CTL, 'sub', 'update'])
            if c == 0:
                c2, o2, e2 = run(['pkexec', CTL, 'nm', 'sync'])
                if c2 != 0:
                    c, o, e = c2, o2, e2
            GLib.idle_add(self._after_background, c, o, e, 'Subscriptions updated', True)
        threading.Thread(target=worker, daemon=True).start()

    def _ping_all(self):
        self._set_status('Pinging nodes…')
        def worker():
            code, out, err = run([CTL, 'node', 'ping', '--all', '--json', '--timeout', '1.5'])
            if code == 0:
                try:
                    rows = json.loads(out)
                    good = [r for r in rows if r.get('latency_ms') is not None]
                    good.sort(key=lambda r: r['latency_ms'])
                    msg = ' · '.join(f"{r['name']}: {r['latency_ms']}ms" for r in good[:5]) or 'No node responded'
                except Exception:
                    msg = out
            else:
                msg = err or 'Ping failed'
            GLib.idle_add(self._set_status, msg)
        threading.Thread(target=worker, daemon=True).start()


if __name__ == '__main__':
    raise SystemExit(WProxyManager().run(None))
