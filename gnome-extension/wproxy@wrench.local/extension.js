import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const USER_CTL = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'wproxyctl']);
const CTL = GLib.file_test(USER_CTL, GLib.FileTest.IS_EXECUTABLE)
    ? USER_CTL
    : (GLib.find_program_in_path('wproxyctl') ?? '/usr/bin/wproxyctl');
const MANAGER = GLib.find_program_in_path('wproxy-manager') ?? '/usr/bin/wproxy-manager';

function spawn(args, callback = null) {
    try {
        const p = Gio.Subprocess.new(args,
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        p.communicate_utf8_async(null, null, (proc, res) => {
            try {
                const [, stdout, stderr] = proc.communicate_utf8_finish(res);
                callback?.(proc.get_successful(), stdout ?? '', stderr ?? '');
            } catch (e) {
                callback?.(false, '', String(e));
            }
        });
    } catch (e) {
        callback?.(false, '', String(e));
    }
}

function spawnDetached(args) {
    try {
        Gio.Subprocess.new(args, Gio.SubprocessFlags.NONE);
    } catch (e) {
        Main.notify('WProxy', String(e));
    }
}

function jsonCommand(args, callback) {
    spawn(args, (ok, out, err) => {
        if (!ok) {
            callback(null, err.trim() || 'Command failed');
            return;
        }
        try {
            callback(JSON.parse(out), null);
        } catch (e) {
            callback(null, `Invalid WProxy response: ${e}`);
        }
    });
}

// CSS max-height is not a reliable allocation limit for a popup section.
// Report only three rows to Quick Settings' layout; the child still contains
// every server, so St.ScrollView can scroll to the rest.
const WProxyNodeScroll = GObject.registerClass(
class WProxyNodeScroll extends St.ScrollView {
    vfunc_get_preferred_height(forWidth) {
        const rows = this.get_child()?.get_children().filter(row => row.visible) ?? [];
        const height = rows.slice(0, 3).reduce((sum, row) =>
            sum + row.get_preferred_height(forWidth)[1], 0);
        return this.get_theme_node().adjust_preferred_height(height, height);
    }
});

class WProxyNodeSection extends PopupMenu.PopupMenuSection {
    constructor() {
        super();
        this.box.add_style_class_name('wproxy-node-list');
        this.actor = new WProxyNodeScroll({
            style_class: 'wproxy-nodes-scroll',
            overlay_scrollbars: false,
            enable_mouse_scrolling: true,
            x_expand: true,
            y_expand: false,
            hscrollbar_policy: St.PolicyType.NEVER,
            vscrollbar_policy: St.PolicyType.AUTOMATIC,
        });
        if (this.actor.set_child)
            this.actor.set_child(this.box);
        else
            this.actor.add_actor(this.box);
        this.actor._delegate = this;
    }
}

export const WProxyToggle = GObject.registerClass(
class WProxyToggle extends QuickSettings.QuickMenuToggle {
    constructor(indicator) {
        super({
            title: 'V2Ray',
            subtitle: 'Disconnected',
            iconName: 'network-vpn-symbolic',
            toggleMode: true,
        });

        this._indicator = indicator;
        this._nodes = [];
        this._busy = false;
        this._activeNodeId = null;
        this._connectingNodeId = null;
        this._latencies = new Map();
        this._pingingNodes = new Set();
        this._nodeRows = new Map();
        this._nodeListSignature = null;

        this.menu.setHeader('network-vpn-symbolic', 'V2Ray', 'WProxy 2.3.0');

        this._statusSection = new PopupMenu.PopupMenuSection();
        this._subscriptionSection = new PopupMenu.PopupMenuSection();
        this._nodesSection = new WProxyNodeSection();
        this._nodesScroll = this._nodesSection.actor;
        this._actionsSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._statusSection);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addMenuItem(this._subscriptionSection);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addMenuItem(this._nodesSection);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addMenuItem(this._actionsSection);

        this._buildSubscriptionControls();

        this._buildActionControls();

        this.connect('clicked', () => this._onToggleClicked());
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open) {
                this.refresh(true);
            }
        });

        this.refresh();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
            this.refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    destroy() {
        if (this._timer) {
            GLib.Source.remove(this._timer);
            this._timer = null;
        }
        super.destroy();
    }

    _notifyError(message) {
        if (message)
            Main.notify('WProxy', message);
    }

    _buildSubscriptionControls() {
        const item = new PopupMenu.PopupBaseMenuItem({
            reactive: false,
            can_focus: false,
        });
        const box = new St.BoxLayout({
            vertical: true,
            x_expand: true,
            style_class: 'wproxy-subscription-box',
        });
        const inputRow = new St.BoxLayout({
            x_expand: true,
            style_class: 'wproxy-subscription-input-row',
        });
        this._subscriptionEntry = new St.Entry({
            hint_text: 'Paste subscription URL',
            can_focus: true,
            x_expand: true,
            style_class: 'wproxy-subscription-entry',
        });
        this._subscriptionEntry.clutter_text.connect('activate', () => this._addSubscription());
        inputRow.add_child(this._subscriptionEntry);

        const addButton = new St.Button({
            label: 'Add',
            can_focus: true,
            reactive: true,
            track_hover: true,
            style_class: 'button wproxy-add-button',
        });
        addButton.connect('clicked', () => this._addSubscription());
        inputRow.add_child(addButton);
        box.add_child(inputRow);

        item.add_child(box);
        this._subscriptionSection.addMenuItem(item);
    }

    _buildActionControls() {
        const item = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        const row = new St.BoxLayout({x_expand: true, style_class: 'wproxy-actions-row'});
        for (const [label, accessibleName, action] of [
            ['Ping all', 'Ping all servers', () => this._pingAll()],
            ['Update', 'Update subscriptions', () => this._updateSubscriptions()],
            ['Manager', 'Open full manager', () => spawnDetached([MANAGER])],
        ]) {
            const button = new St.Button({label, accessible_name: accessibleName,
                can_focus: true, reactive: true, track_hover: true, x_expand: true,
                style_class: 'button wproxy-action-button'});
            button.connect('clicked', action);
            row.add_child(button);
        }
        item.add_child(row);
        this._actionsSection.addMenuItem(item);
    }

    _addSubscription() {
        if (this._busy)
            return;

        const url = this._subscriptionEntry.get_text().trim();
        if (!/^https?:\/\//i.test(url)) {
            this._notifyError('Paste a valid http(s) subscription URL');
            return;
        }

        this._busy = true;
        this.subtitle = 'Adding subscription…';
        spawn([CTL, 'sub', 'add', url], (added, out, addErr) => {
            const subscriptionId = out.trim();
            if (!added || !subscriptionId) {
                this._busy = false;
                this._notifyError(addErr.trim() || 'Could not add subscription');
                this.refresh();
                return;
            }

            spawn([CTL, 'sub', 'update', subscriptionId], (updated, _updateOut, updateErr) => {
                if (!updated) {
                    this._busy = false;
                    this._notifyError(updateErr.trim() || 'Subscription update failed');
                    this.refresh();
                    return;
                }

                spawn(['pkexec', CTL, 'nm', 'sync'], (synced, _syncOut, syncErr) => {
                    this._busy = false;
                    if (!synced) {
                        this._notifyError(syncErr.trim() || 'NetworkManager sync was cancelled');
                    } else {
                        this._subscriptionEntry.set_text('');
                        Main.notify('WProxy', 'Subscription added and servers synced');
                    }
                    this.refresh(true);
                });
            });
        });
    }

    _onToggleClicked() {
        if (this._busy)
            return;

        if (!this.checked) {
            this._busy = true;
            spawn([CTL, 'nm', 'down'], (_ok, _out, err) => {
                this._busy = false;
                if (err.trim())
                    this._notifyError(err.trim());
                this.refresh();
            });
            return;
        }

        jsonCommand([CTL, 'node', 'list', '--json'], (nodes, err) => {
            if (err || !Array.isArray(nodes) || nodes.length === 0) {
                this.checked = false;
                this._notifyError(err || 'No WProxy nodes. Add a config or subscription first.');
                return;
            }
            const target = this._activeNodeId || nodes[0].id;
            this._connectNode(target);
        });
    }

    _connectWithAutoSync(id, retried = false) {
        spawn([CTL, 'nm', 'up', id], (ok, _out, err) => {
            if (ok) {
                this._finishConnect(id, true, '');
                return;
            }

            const message = err.trim() || 'Could not connect';
            const needsSync = !retried && /sync|profile|uuid|unknown connection|not found/i.test(message);
            if (!needsSync) {
                this._finishConnect(id, false, message);
                return;
            }

            // Subscriptions can create nodes before their NetworkManager profiles exist.
            // Ask Polkit for permission, sync once, and retry the selected server.
            spawn(['pkexec', CTL, 'nm', 'sync'], (syncOk, _syncOut, syncErr) => {
                if (!syncOk) {
                    this._finishConnect(id, false,
                        syncErr.trim() || 'NetworkManager sync was cancelled');
                    return;
                }
                this._connectWithAutoSync(id, true);
            });
        });
    }

    _finishConnect(id, ok, message) {
        this._busy = false;
        this._connectingNodeId = null;
        if (!ok) {
            this.checked = false;
            this._notifyError(message || 'Could not connect');
        } else {
            const node = this._nodes.find(n => n.id === id);
            Main.notify('WProxy', `Connected to ${node?.name ?? 'server'}`);
        }
        this.refresh();
    }

    _connectNode(id) {
        if (this._busy)
            return;
        this._busy = true;
        this._connectingNodeId = id;
        this._renderNodes();
        this._connectWithAutoSync(id, false);
    }

    _updateSubscriptions() {
        if (this._busy)
            return;
        this._busy = true;
        spawn([CTL, 'sub', 'update'], (ok, _out, err) => {
            if (!ok) {
                this._busy = false;
                this._notifyError(err.trim() || 'Subscription update failed');
                return;
            }
            spawn(['pkexec', CTL, 'nm', 'sync'], (syncOk, _so, syncErr) => {
                this._busy = false;
                if (!syncOk)
                    this._notifyError(syncErr.trim() || 'NetworkManager sync was cancelled');
                this.refresh();
            });
        });
    }

    _pingNode(id) {
        if (this._pingingNodes.has(id))
            return;

        this._pingingNodes.add(id);
        this._renderNodes();

        jsonCommand([CTL, 'node', 'ping', id, '--json', '--timeout', '2.0'], (rows, err) => {
            this._pingingNodes.delete(id);
            if (err) {
                this._latencies.set(id, null);
                this._notifyError(err);
                this._renderNodes();
                return;
            }

            const row = Array.isArray(rows) ? rows.find(r => r.id === id) : null;
            this._latencies.set(id, row?.latency_ms ?? null);
            this._renderNodes();
        });
    }

    _pingAll() {
        if (this._nodes.length === 0)
            return;

        for (const node of this._nodes)
            this._pingingNodes.add(node.id);
        this._renderNodes();

        jsonCommand([CTL, 'node', 'ping', '--all', '--json', '--timeout', '2.0'], (rows, err) => {
            this._pingingNodes.clear();
            if (err) {
                this._notifyError(err);
                this._renderNodes();
                return;
            }
            if (!Array.isArray(rows))
                return;
            for (const r of rows)
                this._latencies.set(r.id, r.latency_ms);
            this._renderNodes();
        });
    }

    _latencyText(nodeId) {
        if (this._pingingNodes.has(nodeId))
            return '…';
        if (!this._latencies.has(nodeId))
            return 'Ping';
        const latency = this._latencies.get(nodeId);
        return latency === null ? 'Timeout' : `${latency} ms`;
    }

    _renderStatus(status, subs) {
        this._statusSection.removeAll();
        const cardItem = new PopupMenu.PopupBaseMenuItem({
            reactive: false,
            can_focus: false,
        });
        const card = new St.BoxLayout({
            vertical: true,
            x_expand: true,
            style_class: 'wproxy-status-card',
        });

        const heading = new St.BoxLayout({x_expand: true});
        const state = new St.Label({
            text: status?.active ? 'Connected' : 'Disconnected',
            x_expand: true,
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'wproxy-status-subtitle',
        });
        heading.add_child(state);
        card.add_child(heading);

        const trafficSource = Array.isArray(subs)
            ? subs.find(sub => sub?.remaining_human)
            : null;
        if (trafficSource) {
            heading.add_child(new St.Label({
                text: trafficSource.remaining_human,
                style_class: 'wproxy-traffic-value',
            }));
        }

        cardItem.add_child(card);
        this._statusSection.addMenuItem(cardItem);
    }

    _renderNodes() {
        const signature = JSON.stringify(this._nodes.map(node => [node.id, node.name]));
        if (signature === this._nodeListSignature) {
            this._updateNodeRows();
            return;
        }
        this._nodeListSignature = signature;
        this._nodeRows.clear();
        this._nodesSection.removeAll();
        if (this._nodes.length === 0) {
            this._nodesSection.addMenuItem(
                new PopupMenu.PopupMenuItem('No configurations', {reactive: false}));
            return;
        }

        for (const node of this._nodes) {
            const item = new PopupMenu.PopupMenuItem('', {
                reactive: true,
                can_focus: true,
            });
            item.add_style_class_name('wproxy-node-row');

            // Reuse PopupMenuItem's built-in label for the server name.
            item.label.text = node.name;
            item.label.x_expand = true;
            item.label.y_align = Clutter.ActorAlign.CENTER;
            item.label.add_style_class_name('wproxy-node-name');

            const latency = this._latencies.get(node.id);
            const latencyLabel = new St.Label({
                text: this._connectingNodeId === node.id ? 'Connecting…' : this._latencyText(node.id),
                y_align: Clutter.ActorAlign.CENTER,
                x_align: Clutter.ActorAlign.END,
                style_class: 'wproxy-node-latency',
                style: 'margin-left: 8px; margin-right: 8px;',
            });
            if (latency !== undefined && latency !== null && latency < 250)
                latencyLabel.add_style_class_name('wproxy-node-latency-good');
            else if (latency === null)
                latencyLabel.add_style_class_name('wproxy-node-latency-bad');
            item.add_child(latencyLabel);

            const pingButton = new St.Button({
                style_class: 'button',
                can_focus: true,
                reactive: true,
                track_hover: true,
                accessible_name: `Ping ${node.name}`,
                child: new St.Icon({
                    icon_name: 'network-transmit-receive-symbolic',
                    icon_size: 14,
                }),
                style: 'padding: 4px 7px; min-width: 28px; min-height: 24px;',
            });

            // Keep the small ping button independent from the row's connect action.
            pingButton.connect('button-press-event', () => Clutter.EVENT_STOP);
            pingButton.connect('clicked', () => this._pingNode(node.id));
            item.add_child(pingButton);

            if (node.id === this._activeNodeId) {
                item.add_style_class_name('wproxy-node-row-active');
                item.setOrnament(PopupMenu.Ornament.CHECK);
            } else {
                item.setOrnament(PopupMenu.Ornament.NONE);
            }

            item.connect('activate', () => this._connectNode(node.id));
            this._nodesSection.addMenuItem(item);
            this._nodeRows.set(node.id, {item, latencyLabel});
        }
    }

    _updateNodeRows() {
        // Preserve scroll position and keyboard focus during periodic refreshes.
        for (const [id, {item, latencyLabel}] of this._nodeRows) {
            latencyLabel.text = this._connectingNodeId === id
                ? 'Connecting…' : this._latencyText(id);
            const latency = this._latencies.get(id);
            latencyLabel.remove_style_class_name('wproxy-node-latency-good');
            latencyLabel.remove_style_class_name('wproxy-node-latency-bad');
            if (latency !== undefined && latency !== null && latency < 250)
                latencyLabel.add_style_class_name('wproxy-node-latency-good');
            else if (latency === null)
                latencyLabel.add_style_class_name('wproxy-node-latency-bad');
            if (id === this._activeNodeId) {
                item.add_style_class_name('wproxy-node-row-active');
                item.setOrnament(PopupMenu.Ornament.CHECK);
            } else {
                item.remove_style_class_name('wproxy-node-row-active');
                item.setOrnament(PopupMenu.Ornament.NONE);
            }
        }
    }

    refresh(autoPing = false) {
        jsonCommand([CTL, 'status', '--json'], (status, statusErr) => {
            if (statusErr) {
                this.checked = false;
                this.subtitle = 'Not installed';
                this._indicator._icon.visible = false;
                return;
            }

            this._activeNodeId = status.node_id ?? null;
            this.checked = Boolean(status.active);
            this.subtitle = status.active
                ? (status.name?.replace('WProxy · ', '') || 'Connected')
                : 'Disconnected';
            this._indicator._icon.visible = Boolean(status.active);

            jsonCommand([CTL, 'node', 'list', '--json'], (nodes) => {
                this._nodes = Array.isArray(nodes) ? nodes : [];
                this._renderNodes();
                if (autoPing && this._nodes.length > 0 && this._pingingNodes.size === 0)
                    this._pingAll();
            });
            jsonCommand([CTL, 'sub', 'list', '--json'], (subs) => {
                this._renderStatus(status, subs);
            });
        });
    }
});

const WProxyIndicator = GObject.registerClass(
class WProxyIndicator extends QuickSettings.SystemIndicator {
    constructor() {
        super();
        this._icon = this._addIndicator();
        this._icon.icon_name = 'network-vpn-symbolic';
        this._icon.visible = false;
        this.quickSettingsItems.push(new WProxyToggle(this));
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        super.destroy();
    }
});

export default class WProxyExtension extends Extension {
    _isWProxyConnection(connection) {
        const vpn = connection?.get_setting_vpn?.();
        const serviceType = vpn?.get_service_type?.() ?? vpn?.service_type ?? '';
        return serviceType === 'org.freedesktop.NetworkManager.wproxy';
    }

    _filterNativeVpnList(quickSettings) {
        const vpnToggle = quickSettings._network?._vpnToggle;
        if (!vpnToggle?._shouldHandleConnection)
            return;

        this._nativeVpnToggle = vpnToggle;
        this._nativeVpnShouldHandle = vpnToggle._shouldHandleConnection.bind(vpnToggle);
        vpnToggle._shouldHandleConnection = connection =>
            !this._isWProxyConnection(connection) &&
            this._nativeVpnShouldHandle(connection);

        // The native VPN tile may already have loaded its rows before this
        // extension starts. Remove only WProxy duplicates; the profiles stay
        // in NetworkManager and all unrelated VPN/WireGuard rows stay intact.
        for (const connection of [...(vpnToggle._items?.keys() ?? [])]) {
            if (this._isWProxyConnection(connection))
                vpnToggle._removeConnection(connection);
        }
    }

    _restoreNativeVpnList() {
        if (!this._nativeVpnToggle || !this._nativeVpnShouldHandle)
            return;

        const vpnToggle = this._nativeVpnToggle;
        vpnToggle._shouldHandleConnection = this._nativeVpnShouldHandle;
        for (const connection of vpnToggle._client?.get_connections?.() ?? [])
            vpnToggle._addConnection(connection);

        this._nativeVpnToggle = null;
        this._nativeVpnShouldHandle = null;
    }

    enable() {
        this._indicator = new WProxyIndicator();
        const quickSettings = Main.panel.statusArea.quickSettings;
        const networkItems = quickSettings._network?.quickSettingsItems ?? [];

        this._filterNativeVpnList(quickSettings);

        /* GNOME places external tiles near the end by default.  Insert this
         * tile immediately after its built-in Wi-Fi tile so the panel reads
         * "Wi-Fi | V2Ray", matching the network-first workflow. */
        if (quickSettings._indicators && quickSettings.menu?.insertItemBefore) {
            const indicatorSibling = quickSettings._brightness ?? null;
            quickSettings._indicators.insert_child_below(
                this._indicator, indicatorSibling);

            const wifiItem = networkItems.find(item =>
                item?.constructor?.name === 'NMWirelessToggle') ?? networkItems.at(1);
            const itemSibling = wifiItem?.get_next_sibling() ?? null;
            quickSettings.menu.insertItemBefore(
                this._indicator.quickSettingsItems[0], itemSibling, 1);
        } else {
            quickSettings.addExternalIndicator(this._indicator);
        }
    }

    disable() {
        this._restoreNativeVpnList();
        this._indicator?.destroy();
        this._indicator = null;
    }
}
