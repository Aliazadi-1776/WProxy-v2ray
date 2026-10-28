#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import threading
from pathlib import Path

import gi

gi.require_version('Gtk', '4.0')
gi.require_version('Gdk', '4.0')
from gi.repository import Gdk, Gio, GLib, Gtk, Pango


APP_CSS = r'''
window.wproxy-window {
  background: #1e1e20;
  color: #f2f2f7;
  font-family: Inter, "Segoe UI", Ubuntu, Cantarell, sans-serif;
}

headerbar.wproxy-titlebar {
  background: #1e1e20;
  color: #f2f2f7;
  border-bottom: 1px solid #38383c;
  box-shadow: none;
  min-height: 42px;
}

.navigation-rail {
  background: #252528;
  border-right: 1px solid #38383c;
  padding: 18px 12px;
  min-width: 164px;
}

.brand-mark {
  background: #0a84ff;
  color: #ffffff;
  border-radius: 11px;
  font-size: 20px;
  font-weight: 900;
  min-width: 44px;
  min-height: 44px;
}

.brand-name {
  color: #ffffff;
  font-size: 17px;
  font-weight: 800;
}

.brand-caption, .page-copy, .meta-label, .helper-copy {
  color: #a1a1a6;
}

button.nav-button {
  background: transparent;
  color: #c7c7cc;
  border: 0;
  border-radius: 8px;
  min-height: 42px;
  padding: 0 12px;
}

button.nav-button:hover {
  background: #323235;
  color: #ffffff;
}

button.nav-button.selected {
  background: #0a84ff;
  color: #ffffff;
}

.nav-label { font-weight: 700; }
.main-content { background: #1e1e20; }

.connection-card {
  background: #2a2a2d;
  border: 1px solid #38383c;
  border-radius: 12px;
  padding: 14px 16px;
}

.connection-icon {
  background: #343438;
  color: #8e8e93;
  border-radius: 10px;
  font-size: 18px;
  min-width: 44px;
  min-height: 44px;
}

.connection-icon.connected {
  background: #123d31;
  color: #30d158;
}

.eyebrow {
  color: #64a8ff;
  font-size: 10px;
  font-weight: 800;
  letter-spacing: 1.4px;
}

.connection-title {
  color: #ffffff;
  font-size: 19px;
  font-weight: 800;
}

.connection-detail { color: #a1a1a6; }
.page-title { color: #ffffff; font-size: 22px; font-weight: 800; }
.page-copy { font-size: 12px; }

.surface-card {
  background: #2a2a2d;
  border: 1px solid #38383c;
  border-radius: 10px;
  padding: 16px;
}

.card-title { color: #ffffff; font-size: 16px; font-weight: 800; }
.card-kicker { color: #64a8ff; font-size: 10px; font-weight: 800; letter-spacing: 1.2px; }

button.action-button {
  min-height: 36px;
  border-radius: 8px;
  padding: 0 14px;
  font-weight: 750;
}

button.primary-action {
  background: #0a84ff;
  color: #ffffff;
  border: 1px solid #0a84ff;
}

button.primary-action:hover { background: #409cff; }

button.secondary-action {
  background: #343438;
  color: #f2f2f7;
  border: 1px solid #48484a;
}

button.secondary-action:hover { background: #414145; }

button.danger-action {
  background: #43242b;
  color: #ff6961;
  border: 1px solid #63313b;
}

entry, dropdown {
  background: #18181a;
  color: #f2f2f7;
  border: 1px solid #48484a;
  border-radius: 8px;
  min-height: 38px;
}

entry:focus, dropdown:focus { border-color: #0a84ff; }

list.material-list {
  background: transparent;
  border: 0;
}

list.material-list > row {
  background: #2a2a2d;
  border: 1px solid #38383c;
  border-radius: 9px;
  margin-bottom: 8px;
}

list.material-list > row:hover {
  background: #323235;
  border-color: #545458;
}

.node-name { color: #ffffff; font-size: 14px; font-weight: 750; }

.server-avatar {
  color: #ffffff;
  background: #3a3a3e;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 800;
  min-width: 34px;
  min-height: 34px;
}

.live-badge {
  color: #30d158;
  background: #123d31;
  border-radius: 7px;
  font-size: 9px;
  font-weight: 800;
  padding: 5px 8px;
}

.empty-state {
  background: #2a2a2d;
  border: 1px dashed #545458;
  border-radius: 10px;
  padding: 30px 20px;
}

.empty-icon { color: #0a84ff; }
.empty-title { color: #ffffff; font-size: 17px; font-weight: 800; }

checkbutton.preference-toggle { color: #c7c7cc; font-size: 12px; padding: 4px 2px; }
checkbutton.preference-toggle check { background: #18181a; border: 1px solid #545458; border-radius: 5px; }
checkbutton.preference-toggle check:checked { background: #0a84ff; border-color: #0a84ff; }

.status-rail {
  background: #252528;
  border-top: 1px solid #38383c;
  padding: 8px 18px;
}

.status-rail label { color: #a1a1a6; font-size: 12px; }
.status-rail.error label { color: #ff6961; }
scrollbar slider { background: #545458; border-radius: 4px; min-width: 6px; }
'''


def _resolve_ctl():
    env = os.environ.get('WPROXYCTL')
    candidates = [env, shutil.which('wproxyctl'), '/usr/bin/wproxyctl', '/usr/local/bin/wproxyctl']
    for candidate in candidates:
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return '/usr/bin/wproxyctl'


CTL = _resolve_ctl()
ADMIN = '/usr/libexec/wproxy-admin'


def admin_command(action, *arguments):
    if os.path.isfile(ADMIN) and os.access(ADMIN, os.X_OK):
        return ['pkexec', ADMIN, action, *arguments]
    fallback = {'sync': 'sync', 'up': 'up', 'down': 'down'}.get(action)
    if fallback:
        return ['pkexec', CTL, 'nm', fallback, *arguments]
    return ['pkexec', ADMIN, action, *arguments]


def run(args):
    try:
        process = subprocess.run(args, text=True, capture_output=True)
        return process.returncode, process.stdout.strip(), process.stderr.strip()
    except FileNotFoundError as error:
        missing = error.filename or (args[0] if args else 'command')
        return 127, '', f'Required command is missing: {missing}. Re-run WProxy installer or runtime repair.'
    except PermissionError as error:
        return 126, '', f'Cannot execute {error.filename or (args[0] if args else "command")}: permission denied'


class WProxyManager(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='local.wrench.WProxyManager')
        self.window = None
        self.stack = None
        self.nav_buttons = {}
        self.status = None
        self.status_rail = None
        self.connection_icon = None
        self.connection_title = None
        self.connection_detail = None
        self.nodes_box = None
        self.subs_box = None
        self.uri_entry = None
        self.sub_entry = None
        self.routing_mode = None
        self.routing_domains = None
        self.routing_apps = None
        self.domain_entry = None
        self.app_entry = None
        self.routing_empty_warning = None
        self.disconnect_button = None
        self.routing_refreshing = False
        self.preference_loading = False
        self.auto_update_toggle = None
        self.authorization_toggle = None
        self.auto_update_started = False

    def do_startup(self):
        Gtk.Application.do_startup(self)
        settings = Gtk.Settings.get_default()
        if settings:
            settings.set_property('gtk-application-prefer-dark-theme', True)
        provider = Gtk.CssProvider()
        if hasattr(provider, 'load_from_string'):
            provider.load_from_string(APP_CSS)
        else:
            provider.load_from_data(APP_CSS.encode())
        display = Gdk.Display.get_default()
        if display:
            Gtk.StyleContext.add_provider_for_display(
                display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

        refresh_action = Gio.SimpleAction.new('refresh', None)
        refresh_action.connect('activate', lambda *_: self.refresh())
        self.add_action(refresh_action)
        self.set_accels_for_action('app.refresh', ['F5'])
        for index, page in enumerate(('nodes', 'subscriptions', 'add', 'routing'), start=1):
            page_action = Gio.SimpleAction.new(f'show-{page}', None)
            page_action.connect('activate', lambda _action, _value, target=page: self._show_page(target))
            self.add_action(page_action)
            self.set_accels_for_action(f'app.show-{page}', [f'<Alt>{index}'])

        choose_app_action = Gio.SimpleAction.new('choose-application', None)
        choose_app_action.connect('activate', self._show_app_picker)
        self.add_action(choose_app_action)

    def do_activate(self):
        if self.window:
            self.window.present()
            return

        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title('WProxy')
        self.window.set_default_size(1040, 700)
        self.window.set_size_request(820, 580)
        self.window.add_css_class('wproxy-window')

        header = Gtk.HeaderBar()
        header.add_css_class('wproxy-titlebar')
        title = Gtk.Label(label='WProxy')
        title.add_css_class('title')
        header.set_title_widget(title)
        refresh_button = Gtk.Button.new_from_icon_name('view-refresh-symbolic')
        refresh_button.set_tooltip_text('Refresh (F5)')
        refresh_button.connect('clicked', lambda *_: self.refresh())
        header.pack_end(refresh_button)
        self.window.set_titlebar(header)

        root = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self.window.set_child(root)
        root.append(self._build_navigation())

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        main.set_hexpand(True)
        main.add_css_class('main-content')
        root.append(main)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        content.set_margin_top(16)
        content.set_margin_bottom(12)
        content.set_margin_start(18)
        content.set_margin_end(18)
        content.set_vexpand(True)
        main.append(content)
        content.append(self._build_connection_card())

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.set_transition_duration(180)
        self.stack.set_vexpand(True)
        self.stack.add_named(self._build_nodes_page(), 'nodes')
        self.stack.add_named(self._build_subs_page(), 'subscriptions')
        self.stack.add_named(self._build_add_page(), 'add')
        self.stack.add_named(self._build_routing_page(), 'routing')
        content.append(self.stack)

        self.status_rail = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.status_rail.add_css_class('status-rail')
        status_icon = Gtk.Image.new_from_icon_name('dialog-information-symbolic')
        self.status_rail.append(status_icon)
        self.status = Gtk.Label(label='Ready')
        self.status.set_xalign(0)
        self.status.set_hexpand(True)
        self.status.set_ellipsize(Pango.EllipsizeMode.END)
        self.status_rail.append(self.status)
        shortcut = Gtk.Label(label='F5  Refresh')
        shortcut.add_css_class('meta-label')
        self.status_rail.append(shortcut)
        main.append(self.status_rail)

        self._show_page('nodes')
        self.refresh()
        self.window.present()
        GLib.idle_add(self._start_auto_update)

    def _build_navigation(self):
        rail = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        rail.add_css_class('navigation-rail')
        rail.set_size_request(220, -1)
        rail.set_hexpand(False)

        mark = Gtk.Label(label='W')
        mark.set_halign(Gtk.Align.START)
        mark.set_valign(Gtk.Align.CENTER)
        mark.set_justify(Gtk.Justification.CENTER)
        mark.add_css_class('brand-mark')
        rail.append(mark)
        name = Gtk.Label(label='WProxy')
        name.set_xalign(0)
        name.add_css_class('brand-name')
        rail.append(name)
        caption = Gtk.Label(label='Private routing')
        caption.set_xalign(0)
        caption.add_css_class('brand-caption')
        caption.set_margin_bottom(18)
        rail.append(caption)

        for page, label, icon_name in (
            ('nodes', 'Servers', 'network-vpn-symbolic'),
            ('subscriptions', 'Subscriptions', 'view-refresh-symbolic'),
            ('add', 'Add connection', 'list-add-symbolic'),
            ('routing', 'Split routing', 'preferences-system-network-symbolic'),
        ):
            button = Gtk.Button()
            button.add_css_class('nav-button')
            button.set_hexpand(True)
            inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=11)
            icon = Gtk.Image.new_from_icon_name(icon_name)
            text = Gtk.Label(label=label)
            text.set_xalign(0)
            text.set_hexpand(True)
            text.add_css_class('nav-label')
            inner.append(icon)
            inner.append(text)
            button.set_child(inner)
            button.connect('clicked', lambda _button, target=page: self._show_page(target))
            self.nav_buttons[page] = button
            rail.append(button)

        spacer = Gtk.Box()
        spacer.set_vexpand(True)
        rail.append(spacer)

        self.preference_loading = True
        self.auto_update_toggle = Gtk.CheckButton(label='Automatic updates')
        self.auto_update_toggle.add_css_class('preference-toggle')
        self.auto_update_toggle.set_tooltip_text('Download verified releases and install them automatically')
        self.auto_update_toggle.set_active(self._auto_update_enabled())
        self.auto_update_toggle.connect('toggled', self._auto_update_changed)
        rail.append(self.auto_update_toggle)

        self.authorization_toggle = Gtk.CheckButton(label='Remember authorization')
        self.authorization_toggle.add_css_class('preference-toggle')
        self.authorization_toggle.set_tooltip_text('Allow only WProxy tunnel actions without asking again')
        self.authorization_toggle.set_active(self._authorization_enabled())
        self.authorization_toggle.connect('toggled', self._authorization_changed)
        rail.append(self.authorization_toggle)
        self.preference_loading = False

        version = Gtk.Label(label='WProxy 2.7.4')
        version.set_xalign(0)
        version.add_css_class('meta-label')
        rail.append(version)
        return rail

    def _show_page(self, page):
        if self.stack:
            self.stack.set_visible_child_name(page)
        for name, button in self.nav_buttons.items():
            if name == page:
                button.add_css_class('selected')
            else:
                button.remove_css_class('selected')

    def _build_connection_card(self):
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        card.add_css_class('connection-card')
        self.connection_icon = Gtk.Label(label='●')
        self.connection_icon.set_halign(Gtk.Align.CENTER)
        self.connection_icon.set_valign(Gtk.Align.CENTER)
        self.connection_icon.add_css_class('connection-icon')
        card.append(self.connection_icon)

        copy = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        copy.set_hexpand(True)
        eyebrow = Gtk.Label(label='SYSTEM TUNNEL')
        eyebrow.set_xalign(0)
        eyebrow.add_css_class('eyebrow')
        self.connection_title = Gtk.Label(label='Not connected')
        self.connection_title.set_xalign(0)
        self.connection_title.add_css_class('connection-title')
        self.connection_detail = Gtk.Label(label='Choose a server or let WProxy pick the fastest one')
        self.connection_detail.set_xalign(0)
        self.connection_detail.set_ellipsize(Pango.EllipsizeMode.END)
        self.connection_detail.add_css_class('connection-detail')
        copy.append(eyebrow)
        copy.append(self.connection_title)
        copy.append(self.connection_detail)
        card.append(copy)
        return card

    def _page(self):
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_margin_top(2)
        box.set_margin_bottom(12)
        scroller.set_child(box)
        return scroller, box

    def _page_heading(self, title, copy, actions=None):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text.set_hexpand(True)
        label = Gtk.Label(label=title)
        label.set_xalign(0)
        label.add_css_class('page-title')
        description = Gtk.Label(label=copy)
        description.set_xalign(0)
        description.set_wrap(True)
        description.add_css_class('page-copy')
        text.append(label)
        text.append(description)
        row.append(text)
        if actions:
            row.append(actions)
        return row

    def _button(self, label, kind='secondary'):
        button = Gtk.Button(label=label)
        button.add_css_class('action-button')
        button.add_css_class(f'{kind}-action')
        return button

    def _card(self, kicker, title, copy):
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        card.add_css_class('surface-card')
        small = Gtk.Label(label=kicker.upper())
        small.set_xalign(0)
        small.add_css_class('card-kicker')
        heading = Gtk.Label(label=title)
        heading.set_xalign(0)
        heading.add_css_class('card-title')
        description = Gtk.Label(label=copy)
        description.set_xalign(0)
        description.set_wrap(True)
        description.add_css_class('helper-copy')
        card.append(small)
        card.append(heading)
        card.append(description)
        return card

    def _build_nodes_page(self):
        scroller, box = self._page()
        box.append(self._page_heading(
            'Servers', 'Choose a server. The active connection is always marked clearly.'
        ))
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        actions.set_halign(Gtk.Align.START)
        fastest = self._button('Use fastest', 'primary')
        fastest.connect('clicked', lambda *_: self._connect_fastest())
        ping = self._button('Ping all')
        ping.connect('clicked', lambda *_: self._ping_all())
        self.disconnect_button = self._button('Disconnect', 'danger')
        self.disconnect_button.connect(
            'clicked', lambda *_: self._background(admin_command('down'), 'Disconnected', True)
        )
        actions.append(fastest)
        actions.append(ping)
        actions.append(self.disconnect_button)
        box.append(actions)
        self.nodes_box = Gtk.ListBox()
        self.nodes_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self.nodes_box.add_css_class('material-list')
        box.append(self.nodes_box)
        return scroller

    def _build_subs_page(self):
        scroller, box = self._page()
        box.append(self._page_heading(
            'Subscriptions', 'Update providers separately and see how many servers each one owns.'
        ))
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        actions.set_halign(Gtk.Align.START)
        update = self._button('Update all', 'primary')
        update.connect('clicked', lambda *_: self._update_all())
        sync = self._button('Sync')
        sync.set_tooltip_text('Sync to NetworkManager')
        sync.connect('clicked', lambda *_: self._sync_nm())
        actions.append(update)
        actions.append(sync)
        box.append(actions)
        self.subs_box = Gtk.ListBox()
        self.subs_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self.subs_box.add_css_class('material-list')
        box.append(self.subs_box)
        return scroller

    def _build_add_page(self):
        scroller, box = self._page()
        box.append(self._page_heading(
            'Add connection', 'Use one share link or add a subscription with multiple servers.'
        ))

        node_card = self._card(
            'Single server', 'Paste a configuration',
            'Supports VLESS, VMess, Trojan and Shadowsocks share links.'
        )
        self.uri_entry = Gtk.Entry()
        self.uri_entry.set_placeholder_text('vless://…  vmess://…  trojan://…  ss://…')
        self.uri_entry.set_visibility(False)
        self.uri_entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, 'view-reveal-symbolic')
        self.uri_entry.connect('icon-press', self._toggle_secret_entry)
        self.uri_entry.connect('activate', self._add_node)
        node_card.append(self.uri_entry)
        add_node = self._button('Add configuration', 'primary')
        add_node.set_halign(Gtk.Align.START)
        add_node.connect('clicked', self._add_node)
        node_card.append(add_node)
        box.append(node_card)

        sub_card = self._card(
            'Subscription', 'Add a provider URL',
            'WProxy imports supported links and keeps each provider separate.'
        )
        self.sub_entry = Gtk.Entry()
        self.sub_entry.set_placeholder_text('https://example.com/subscription')
        self.sub_entry.set_visibility(False)
        self.sub_entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, 'view-reveal-symbolic')
        self.sub_entry.connect('icon-press', self._toggle_secret_entry)
        self.sub_entry.connect('activate', self._add_sub)
        sub_card.append(self.sub_entry)
        add_sub = self._button('Add and update', 'primary')
        add_sub.set_halign(Gtk.Align.START)
        add_sub.connect('clicked', self._add_sub)
        sub_card.append(add_sub)
        box.append(sub_card)
        return scroller

    def _build_routing_page(self):
        scroller, box = self._page()
        box.append(self._page_heading(
            'Split routing', 'Choose what uses the tunnel. Reconnect after changing an active connection.'
        ))
        mode_card = self._card(
            'Traffic mode', 'Choose the default path',
            'Rules are saved locally and synced to every WProxy NetworkManager profile.'
        )
        self.routing_mode = Gtk.DropDown.new_from_strings([
            'All traffic through VPN',
            'Bypass listed sites and applications',
            'Only listed sites and applications use VPN',
        ])
        self.routing_mode.connect('notify::selected', self._routing_mode_changed)
        mode_card.append(self.routing_mode)
        box.append(mode_card)

        grid = Gtk.Grid(column_spacing=14, row_spacing=14)
        grid.set_column_homogeneous(True)
        domains = self._card('Sites', 'Domain rules', 'Enter a hostname or URL. Subdomains are included.')
        domain_add = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.domain_entry = Gtk.Entry()
        self.domain_entry.set_hexpand(True)
        self.domain_entry.set_placeholder_text('youtube.com')
        self.domain_entry.connect('activate', self._add_routing_domain)
        add_domain = self._button('Add', 'primary')
        add_domain.connect('clicked', self._add_routing_domain)
        domain_add.append(self.domain_entry)
        domain_add.append(add_domain)
        domains.append(domain_add)
        self.routing_domains = Gtk.ListBox()
        self.routing_domains.set_selection_mode(Gtk.SelectionMode.NONE)
        self.routing_domains.add_css_class('material-list')
        domains.append(self.routing_domains)

        apps = self._card(
            'Applications', 'Choose installed apps',
            'Pick an application by name. WProxy saves the executable selector for you.'
        )
        choose_app = self._button('Choose application…', 'primary')
        choose_app.set_halign(Gtk.Align.START)
        choose_app.connect('clicked', self._show_app_picker)
        apps.append(choose_app)
        self.routing_apps = Gtk.ListBox()
        self.routing_apps.set_selection_mode(Gtk.SelectionMode.NONE)
        self.routing_apps.add_css_class('material-list')
        apps.append(self.routing_apps)

        grid.attach(domains, 0, 0, 1, 1)
        grid.attach(apps, 1, 0, 1, 1)
        box.append(grid)
        self.routing_empty_warning = Gtk.Label(label=(
            '“Only listed” needs at least one site or application. With an empty list, all traffic stays direct.'
        ))
        self.routing_empty_warning.set_wrap(True)
        self.routing_empty_warning.set_xalign(0)
        self.routing_empty_warning.add_css_class('helper-copy')
        box.append(self.routing_empty_warning)
        warning = Gtk.Label(label=(
            'Process matching is case-sensitive. Encrypted DNS can limit site-only matching.'
        ))
        warning.set_wrap(True)
        warning.set_xalign(0)
        warning.add_css_class('helper-copy')
        box.append(warning)
        return scroller

    def _toggle_secret_entry(self, entry, _position):
        entry.set_visibility(not entry.get_visibility())
        icon = 'view-conceal-symbolic' if entry.get_visibility() else 'view-reveal-symbolic'
        entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY, icon)

    def _show_app_picker(self, *_):
        picker = Gtk.Window(title='Choose application', transient_for=self.window, modal=True)
        picker.set_default_size(640, 560)
        picker.set_size_request(520, 440)
        picker.add_css_class('wproxy-window')

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        root.set_margin_top(20)
        root.set_margin_bottom(18)
        root.set_margin_start(20)
        root.set_margin_end(20)
        picker.set_child(root)
        title = Gtk.Label(label='Choose an application')
        title.set_xalign(0)
        title.add_css_class('page-title')
        copy = Gtk.Label(label='Select an installed app, or browse to an executable file.')
        copy.set_xalign(0)
        copy.set_wrap(True)
        copy.add_css_class('page-copy')
        root.append(title)
        root.append(copy)

        search = Gtk.SearchEntry()
        search.set_placeholder_text('Search applications')
        root.append(search)
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        app_list = Gtk.ListBox()
        app_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        app_list.add_css_class('material-list')
        scroller.set_child(app_list)
        root.append(scroller)

        values = {}
        searchable = {}
        applications = sorted(
            (app for app in Gio.AppInfo.get_all() if app.should_show() and app.get_executable()),
            key=lambda app: app.get_display_name().casefold(),
        )
        for application in applications:
            executable = application.get_executable().strip()
            if not executable:
                continue
            resolved = shutil.which(executable)
            if resolved:
                executable = str(Path(resolved).resolve())
            elif os.path.isabs(executable):
                executable = str(Path(executable).resolve())
            row = Gtk.ListBoxRow()
            content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            content.set_margin_top(10)
            content.set_margin_bottom(10)
            content.set_margin_start(12)
            content.set_margin_end(12)
            icon = application.get_icon()
            image = Gtk.Image.new_from_gicon(icon) if icon else Gtk.Image.new_from_icon_name('application-x-executable-symbolic')
            image.set_pixel_size(28)
            content.append(image)
            labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
            labels.set_hexpand(True)
            name = Gtk.Label(label=application.get_display_name())
            name.set_xalign(0)
            name.set_ellipsize(Pango.EllipsizeMode.END)
            name.add_css_class('node-name')
            command = Gtk.Label(label=executable)
            command.set_xalign(0)
            command.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
            command.add_css_class('meta-label')
            labels.append(name)
            labels.append(command)
            content.append(labels)
            row.set_child(content)
            app_list.append(row)
            values[row] = executable
            searchable[row] = f'{application.get_display_name()} {executable}'.casefold()

        def choose_value(value):
            code, _out, err = run([CTL, 'routing', 'app', 'add', value])
            if code != 0:
                self._set_status(err or 'Could not add application', True)
                return
            picker.close()
            self._sync_nm()

        def choose_selected(*_args):
            row = app_list.get_selected_row()
            if row in values:
                choose_value(values[row])

        def filter_apps(entry):
            query = entry.get_text().strip().casefold()
            for row, text in searchable.items():
                row.set_visible(not query or query in text)

        search.connect('search-changed', filter_apps)
        search.connect('activate', lambda *_: choose_selected())
        app_list.connect('row-activated', lambda _list, row: choose_value(values[row]))

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        browse = self._button('Browse files…')
        cancel = self._button('Cancel')
        choose = self._button('Choose', 'primary')
        actions.append(browse)
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        actions.append(spacer)
        actions.append(cancel)
        actions.append(choose)
        root.append(actions)

        def browse_executable(*_args):
            chooser = Gtk.FileChooserNative(
                title='Choose executable', transient_for=picker,
                action=Gtk.FileChooserAction.OPEN, accept_label='Choose', cancel_label='Cancel'
            )

            def selected(dialog, response):
                if response == Gtk.ResponseType.ACCEPT:
                    selected_file = dialog.get_file()
                    path = selected_file.get_path() if selected_file else None
                    if path:
                        choose_value(path)
                dialog.destroy()

            chooser.connect('response', selected)
            chooser.show()

        browse.connect('clicked', browse_executable)
        cancel.connect('clicked', lambda *_: picker.close())
        choose.connect('clicked', choose_selected)
        picker.present()

    def _set_status(self, text, error=False):
        if self.status:
            self.status.set_text(text or '')
        if self.status_rail:
            if error:
                self.status_rail.add_css_class('error')
            else:
                self.status_rail.remove_css_class('error')

    def _set_connection_state(self, active, name=''):
        if not self.connection_icon:
            return
        if active:
            self.connection_icon.add_css_class('connected')
            self.connection_title.set_text('Connected')
            self.connection_detail.set_text(name or 'Tunnel is active')
        else:
            self.connection_icon.remove_css_class('connected')
            self.connection_title.set_text('Not connected')
            self.connection_detail.set_text('Choose a server or let WProxy pick the fastest one')
        if self.disconnect_button:
            self.disconnect_button.set_sensitive(active)

    def _clear_listbox(self, listbox):
        child = listbox.get_first_child()
        while child:
            next_child = child.get_next_sibling()
            listbox.remove(child)
            child = next_child

    def _load_json(self, args):
        code, out, err = run(args)
        if code != 0:
            raise RuntimeError(err or 'Command failed')
        return json.loads(out or '[]')

    def refresh(self):
        self._set_status('Refreshing…')
        try:
            nodes = self._load_json([CTL, 'node', 'list', '--json'])
            subscriptions = self._load_json([CTL, 'sub', 'list', '--json'])
            status = self._load_json([CTL, 'status', '--json'])
            routing = self._load_json([CTL, 'routing', 'show', '--json'])
            self._render_nodes(nodes, status)
            self._render_subs(subscriptions)
            self._render_routing(routing)
            active = bool(status.get('active'))
            name = status.get('name') or ''
            self._set_connection_state(active, name)
            self._set_status(f'Connected to {name}' if active else 'Ready · No active tunnel')
        except Exception as error:
            self._set_connection_state(False)
            self._set_status(str(error), True)

    def _empty_row(self, title, copy, action_label=None):
        row = Gtk.ListBoxRow()
        empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        empty.set_halign(Gtk.Align.FILL)
        empty.add_css_class('empty-state')
        icon = Gtk.Image.new_from_icon_name('network-vpn-symbolic')
        icon.set_pixel_size(30)
        icon.add_css_class('empty-icon')
        heading = Gtk.Label(label=title)
        heading.add_css_class('empty-title')
        detail = Gtk.Label(label=copy)
        detail.set_wrap(True)
        detail.set_justify(Gtk.Justification.CENTER)
        detail.add_css_class('helper-copy')
        empty.append(icon)
        empty.append(heading)
        empty.append(detail)
        if action_label:
            action = self._button(action_label, 'primary')
            action.set_halign(Gtk.Align.CENTER)
            action.connect('clicked', lambda *_: self._show_page('add'))
            empty.append(action)
        row.set_child(empty)
        return row

    def _render_nodes(self, nodes, status):
        self._clear_listbox(self.nodes_box)
        active = status.get('node_id')
        if not nodes:
            self.nodes_box.append(self._empty_row(
                'No servers yet', 'Add a share link or subscription to build your server list.',
                'Add connection'
            ))
            return
        for node in nodes:
            row = Gtk.ListBoxRow()
            outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            outer.set_margin_top(12)
            outer.set_margin_bottom(12)
            outer.set_margin_start(14)
            outer.set_margin_end(14)
            server_name = node.get('name', 'Proxy')
            badge = Gtk.Label(label=(server_name.strip()[:1] or 'W').upper())
            badge.add_css_class('server-avatar')
            badge.set_valign(Gtk.Align.CENTER)
            outer.append(badge)
            labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            labels.set_hexpand(True)
            name = Gtk.Label(label=server_name)
            name.set_xalign(0)
            name.set_ellipsize(Pango.EllipsizeMode.END)
            name.add_css_class('node-name')
            source_text = node.get('source_name') or ('Subscription' if node.get('source') else 'Manual')
            source = Gtk.Label(label=source_text)
            source.set_xalign(0)
            source.set_ellipsize(Pango.EllipsizeMode.END)
            source.add_css_class('meta-label')
            labels.append(name)
            labels.append(source)
            outer.append(labels)
            is_active = node.get('id') == active
            if is_active:
                live = Gtk.Label(label='LIVE')
                live.set_valign(Gtk.Align.CENTER)
                live.add_css_class('live-badge')
                outer.append(live)
            connect = self._button('Connected' if is_active else 'Connect', 'secondary' if is_active else 'primary')
            connect.set_sensitive(not is_active)
            connect.connect('clicked', lambda _button, node_id=node['id']: self._background(
                admin_command('up', node_id), 'Connected', True
            ))
            delete = Gtk.Button.new_from_icon_name('user-trash-symbolic')
            delete.add_css_class('action-button')
            delete.add_css_class('secondary-action')
            delete.set_tooltip_text('Remove server')
            delete.connect('clicked', lambda _button, node_id=node['id']: self._remove_node(node_id))
            outer.append(connect)
            outer.append(delete)
            row.set_child(outer)
            self.nodes_box.append(row)

    def _render_subs(self, subscriptions):
        self._clear_listbox(self.subs_box)
        if not subscriptions:
            self.subs_box.append(self._empty_row(
                'No subscriptions yet', 'Add a provider URL to update a group of servers together.',
                'Add subscription'
            ))
            return
        for subscription in subscriptions:
            row = Gtk.ListBoxRow()
            outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            outer.set_margin_top(12)
            outer.set_margin_bottom(12)
            outer.set_margin_start(14)
            outer.set_margin_end(14)
            labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            labels.set_hexpand(True)
            title = Gtk.Label(label=subscription.get('name') or 'Subscription')
            title.set_xalign(0)
            title.set_ellipsize(Pango.EllipsizeMode.END)
            title.add_css_class('node-name')
            count = int(subscription.get('node_count') or 0)
            traffic = subscription.get('remaining_human') or 'traffic unavailable'
            subtitle = Gtk.Label(label=f'{count} servers · {traffic}')
            subtitle.set_xalign(0)
            subtitle.add_css_class('meta-label')
            labels.append(title)
            labels.append(subtitle)
            outer.append(labels)
            update = self._button('Update', 'primary')
            update.connect('clicked', lambda _button, sub_id=subscription['id']: self._update_sub(sub_id))
            delete = Gtk.Button.new_from_icon_name('user-trash-symbolic')
            delete.add_css_class('action-button')
            delete.add_css_class('secondary-action')
            delete.set_tooltip_text('Remove subscription')
            delete.connect('clicked', lambda _button, sub_id=subscription['id']: self._remove_sub(sub_id))
            outer.append(update)
            outer.append(delete)
            row.set_child(outer)
            self.subs_box.append(row)

    def _routing_row(self, value, kind):
        row = Gtk.ListBoxRow()
        outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        outer.set_margin_top(7)
        outer.set_margin_bottom(7)
        outer.set_margin_start(10)
        outer.set_margin_end(10)
        label = Gtk.Label(label=value)
        label.set_xalign(0)
        label.set_hexpand(True)
        label.set_ellipsize(Pango.EllipsizeMode.END)
        remove = Gtk.Button.new_from_icon_name('user-trash-symbolic')
        remove.add_css_class('secondary-action')
        remove.set_tooltip_text('Remove rule')
        remove.connect('clicked', lambda *_: self._change_routing(
            [CTL, 'routing', kind, 'remove', value], 'Routing entry removed'
        ))
        outer.append(label)
        outer.append(remove)
        row.set_child(outer)
        return row

    def _render_routing(self, routing):
        self.routing_refreshing = True
        self.routing_mode.set_selected({'all': 0, 'bypass': 1, 'only': 2}.get(routing.get('mode'), 0))
        self.routing_refreshing = False
        self._clear_listbox(self.routing_domains)
        for value in routing.get('domains', []):
            self.routing_domains.append(self._routing_row(value, 'domain'))
        self._clear_listbox(self.routing_apps)
        for value in routing.get('apps', []):
            self.routing_apps.append(self._routing_row(value, 'app'))
        if self.routing_empty_warning:
            empty_only = routing.get('mode') == 'only' and not routing.get('domains') and not routing.get('apps')
            self.routing_empty_warning.set_visible(empty_only)

    def _background(self, args, success, refresh=False):
        self._set_status('Working…')

        def worker():
            code, out, err = run(args)
            GLib.idle_add(self._after_background, code, out, err, success, refresh)

        threading.Thread(target=worker, daemon=True).start()

    def _after_background(self, code, out, err, success, refresh):
        self._set_status(success if code == 0 else (err or out or 'Command failed'), code != 0)
        if refresh:
            self.refresh()
        return False

    def _sync_nm(self):
        self._background(admin_command('sync'), 'Synced to NetworkManager', True)

    def _change_routing(self, args, success):
        self._set_status('Saving and syncing routing…')

        def worker():
            code, out, err = run(args)
            if code == 0:
                code, second_out, second_err = run(admin_command('sync'))
                out = second_out or out
                err = second_err or err
            GLib.idle_add(self._after_background, code, out, err, success, True)

        threading.Thread(target=worker, daemon=True).start()

    def _routing_mode_changed(self, dropdown, _param):
        if self.routing_refreshing:
            return
        mode = ('all', 'bypass', 'only')[dropdown.get_selected()]
        self._change_routing([CTL, 'routing', 'mode', mode], 'Routing mode saved; reconnect to apply')

    def _add_routing_domain(self, *_):
        value = self.domain_entry.get_text().strip()
        if not value:
            return
        self.domain_entry.set_text('')
        self._change_routing([CTL, 'routing', 'domain', 'add', value], 'Site added; reconnect to apply')

    def _add_node(self, *_):
        uri = self.uri_entry.get_text().strip()
        if not uri:
            return
        code, _, err = run([CTL, 'node', 'add', uri])
        if code != 0:
            self._set_status(err or 'Could not add configuration', True)
            return
        self.uri_entry.set_text('')
        self._sync_nm()

    def _add_sub(self, *_):
        url = self.sub_entry.get_text().strip()
        if not url:
            return
        code, sub_id, err = run([CTL, 'sub', 'add', url])
        if code != 0:
            self._set_status(err or 'Could not add subscription', True)
            return
        self.sub_entry.set_text('')
        self._set_status('Updating subscription…')

        def worker():
            result, out, error = run([CTL, 'sub', 'update', sub_id.strip()])
            if result == 0:
                result, second_out, second_error = run(admin_command('sync'))
                out = second_out or out
                error = second_error or error
            GLib.idle_add(self._after_background, result, out, error, 'Subscription added', True)

        threading.Thread(target=worker, daemon=True).start()

    def _remove_node(self, node_id):
        code, _, err = run([CTL, 'node', 'remove', node_id])
        if code != 0:
            self._set_status(err, True)
            return
        self._sync_nm()

    def _remove_sub(self, sub_id):
        code, _, err = run([CTL, 'sub', 'remove', sub_id])
        if code != 0:
            self._set_status(err, True)
            return
        self._sync_nm()

    def _update_sub(self, sub_id):
        self._set_status('Updating subscription…')

        def worker():
            code, out, err = run([CTL, 'sub', 'update', sub_id])
            if code == 0:
                second_code, second_out, second_err = run(admin_command('sync'))
                if second_code != 0:
                    code, out, err = second_code, second_out, second_err
            GLib.idle_add(self._after_background, code, out, err, 'Subscription updated', True)

        threading.Thread(target=worker, daemon=True).start()

    def _update_all(self):
        self._set_status('Updating subscriptions…')

        def worker():
            code, out, err = run([CTL, 'sub', 'update'])
            if code == 0:
                second_code, second_out, second_err = run(admin_command('sync'))
                if second_code != 0:
                    code, out, err = second_code, second_out, second_err
            GLib.idle_add(self._after_background, code, out, err, 'Subscriptions updated', True)

        threading.Thread(target=worker, daemon=True).start()

    def _auto_update_enabled(self):
        code, out, _err = run([CTL, 'settings', 'show', '--json'])
        if code != 0:
            return False
        try:
            return bool(json.loads(out).get('auto_update'))
        except (TypeError, json.JSONDecodeError):
            return False

    def _authorization_enabled(self):
        return Path(f'/etc/polkit-1/rules.d/49-wproxy-{os.getuid()}.rules').is_file()

    def _auto_update_changed(self, button):
        if self.preference_loading:
            return
        enabled = button.get_active()
        code, _out, err = run([CTL, 'settings', 'set', 'auto_update', 'true' if enabled else 'false'])
        if code != 0:
            self.preference_loading = True
            button.set_active(not enabled)
            self.preference_loading = False
            self._set_status(err or 'Could not save automatic update preference', True)
            return
        self._set_status('Automatic updates enabled' if enabled else 'Automatic updates disabled')
        if enabled:
            self._start_auto_update(force=True)

    def _authorization_changed(self, button):
        if self.preference_loading:
            return
        enabled = button.get_active()
        button.set_sensitive(False)
        self._set_status('Saving limited WProxy authorization…')

        def worker():
            code, out, err = run(admin_command('authorize' if enabled else 'revoke'))
            GLib.idle_add(self._authorization_finished, code, out, err, enabled)

        threading.Thread(target=worker, daemon=True).start()

    def _authorization_finished(self, code, out, err, requested):
        actual = self._authorization_enabled()
        self.preference_loading = True
        self.authorization_toggle.set_active(actual)
        self.preference_loading = False
        self.authorization_toggle.set_sensitive(True)
        if code == 0 and actual == requested:
            self._set_status('WProxy authorization remembered' if actual else 'WProxy authorization reset')
        else:
            self._set_status(err or out or 'Could not change WProxy authorization', True)
        return False

    def _start_auto_update(self, force=False):
        if self.auto_update_started and not force:
            return False
        if not self.auto_update_toggle or not self.auto_update_toggle.get_active():
            return False
        self.auto_update_started = True

        def worker():
            code, out, err = run([CTL, 'update', 'download', '--platform', 'linux', '--json'])
            if code != 0:
                GLib.idle_add(self._set_status, err or out or 'Automatic update check failed', True)
                return
            try:
                result = json.loads(out)
            except json.JSONDecodeError:
                GLib.idle_add(self._set_status, 'Automatic update returned invalid data', True)
                return
            if not result.get('update_available'):
                return
            archive = result.get('path')
            if not archive:
                GLib.idle_add(self._set_status, 'Update was downloaded without an install path', True)
                return
            GLib.idle_add(self._set_status, f"Installing WProxy {result.get('latest_version', '')}…")
            install_code, install_out, install_err = run(admin_command('update', archive))
            GLib.idle_add(
                self._set_status,
                'WProxy updated. Restart the manager to use the new version.' if install_code == 0
                else (install_err or install_out or 'Automatic update installation failed'),
                install_code != 0,
            )

        threading.Thread(target=worker, daemon=True).start()
        return False

    def _connect_fastest(self):
        self._set_status('Testing servers and choosing the fastest…')

        def worker():
            code, out, err = run([CTL, 'node', 'best', '--json', '--timeout', '1.5'])
            if code != 0:
                GLib.idle_add(self._after_background, code, out, err, '', False)
                return
            try:
                best = json.loads(out)
            except json.JSONDecodeError:
                GLib.idle_add(self._after_background, 2, '', 'Could not read fastest server result', '', False)
                return
            connect_code, connect_out, connect_err = run(admin_command('up', best['id']))
            success = f"Connected to {best['name']} · {best['latency_ms']}ms"
            GLib.idle_add(
                self._after_background, connect_code, connect_out, connect_err, success, True
            )

        threading.Thread(target=worker, daemon=True).start()

    def _ping_all(self):
        self._set_status('Pinging servers…')

        def worker():
            code, out, err = run([CTL, 'node', 'ping', '--all', '--json', '--timeout', '1.5'])
            if code == 0:
                try:
                    rows = json.loads(out)
                    good = [row for row in rows if row.get('latency_ms') is not None]
                    good.sort(key=lambda row: row['latency_ms'])
                    message = ' · '.join(
                        f"{row['name']}: {row['latency_ms']}ms" for row in good[:5]
                    ) or 'No server responded'
                except Exception:
                    message = out
            else:
                message = err or 'Ping failed'
            GLib.idle_add(self._set_status, message, code != 0)

        threading.Thread(target=worker, daemon=True).start()


if __name__ == '__main__':
    raise SystemExit(WProxyManager().run(None))
