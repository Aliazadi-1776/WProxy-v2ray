import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const delay = ms => new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
    resolve();
    return GLib.SOURCE_REMOVE;
}));
function check(value, message) { if (!value) throw new Error(message); }
async function until(predicate, message) {
    for (let n = 0; n < 100; n++) {
        if (predicate()) return;
        await delay(50);
    }
    throw new Error(message);
}
function buttons(actor) {
    return [...(actor instanceof St.Button ? [actor] : []),
        ...actor.get_children().flatMap(buttons)];
}

export default class ActionTest extends Extension {
    enable() {
        this.run().then(results => this.finish({ok: true, results}))
            .catch(error => this.finish({ok: false, error: String(error), stack: error.stack}));
    }
    finish(result) {
        GLib.file_set_contents(`${GLib.getenv('WPROXY_TEST_ROOT')}/result.json`, JSON.stringify(result, null, 2));
    }
    async run() {
        await delay(1000);
        const root = GLib.getenv('WPROXY_TEST_ROOT');
        const source = GLib.getenv('WPROXY_TEST_SOURCE');
        const fixture = GLib.getenv('WPROXY_TEST_FIXTURE');
        const python = GLib.getenv('WPROXY_TEST_PYTHON');
        const subprocess = Gio.Subprocess.new;
        this.restore = () => { Gio.Subprocess.new = subprocess; };
        Gio.Subprocess.new = (args, flags) => {
            if (args[0].endsWith('wproxyctl') || args[0].endsWith('wproxy-manager') ||
                args[0] === 'pkexec')
                return subprocess([python, fixture, ...args], flags);
            return subprocess(args, flags);
        };
        const readCommands = () => {
            const [exists, bytes] = GLib.file_get_contents(`${root}/commands.jsonl`);
            return exists ? new TextDecoder().decode(bytes).trim().split('\n').filter(Boolean).map(JSON.parse) : [];
        };
        const mark = name => GLib.file_set_contents(`${root}/${name}`, '1');
        const {default: WProxyExtension} = await import(GLib.filename_to_uri(`${source}/extension.js`, null));
        this.production = new WProxyExtension({uuid: 'wproxy@wrench.local', path: source,
            dir: Gio.File.new_for_path(source), name: 'WProxy actual production extension'});
        const qs = Main.panel.statusArea.quickSettings;
        const before = qs._indicators.get_children().length;
        this.production.enable();
        let toggle = this.production._indicator.quickSettingsItems[0];
        await until(() => toggle._nodes.length === 2, 'Initial real refresh never reached fake CLI');
        check(!toggle.checked, 'Initial status is connected');
        const results = ['production extension enable and initial subprocess refresh'];
        check(qs._indicators.get_children().length === before + 1, 'Indicator not inserted exactly once');
        toggle._nodeRows.get('0123456789abcdef').item.activate(null);
        await until(() => !toggle._busy && toggle.checked, 'Row connect did not complete');
        check(toggle._activeNodeId === '0123456789abcdef', 'Connected to wrong node');
        results.push('server row activation -> nm up -> refreshed active status');
        toggle.checked = false;
        toggle._onToggleClicked();
        await until(() => !toggle._busy && !toggle.checked && toggle._activeNodeId === null, 'Disconnect did not refresh');
        results.push('tile disconnect -> nm down -> refreshed inactive status');
        toggle._pingNode('0123456789abcdef');
        toggle._pingNode('0123456789abcdef');
        await until(() => !toggle._pingingNodes.has('0123456789abcdef'), 'Ping did not complete');
        check(toggle._latencies.get('0123456789abcdef') === 42, 'Ping response not rendered');
        check(readCommands().filter(a => a.includes('ping') && a.includes('0123456789abcdef')).length === 1,
            'Duplicate ping escaped guard');
        results.push('single ping rendered and duplicate request suppressed');
        const controls = buttons(toggle._actionsSection.actor);
        const ping = controls.find(button => button.label === 'Ping all');
        check(ping, 'Ping all button missing');
        ping.emit('clicked', 1);
        await until(() => toggle._pingingNodes.size === 0, 'Ping all did not complete');
        check(toggle._latencies.get('fedcba9876543210') === 42, 'Ping all response not rendered');
        results.push('actual Ping all button -> node ping --all -> row latencies');
        mark('missing-profile');
        toggle._connectNode('fedcba9876543210');
        await until(() => !toggle._busy && toggle.checked && toggle._activeNodeId === 'fedcba9876543210',
            'Missing-profile sync/retry did not complete');
        check(readCommands().some(a => a[0] === 'pkexec' && a.slice(-2).join(' ') === 'nm sync'),
            'Missing profile did not request sync');
        results.push('missing connection -> pkexec nm sync -> selected server retried once');
        toggle.checked = false;
        toggle._onToggleClicked();
        await until(() => !toggle._busy && toggle._activeNodeId === null, 'Second disconnect failed');
        mark('missing-profile'); mark('cancel-sync');
        const beforeCancelled = readCommands().filter(a => a.includes('up')).length;
        toggle._connectNode('0123456789abcdef');
        await until(() => !toggle._busy, 'Cancelled authorization left busy state');
        check(!toggle.checked && toggle._connectingNodeId === null, 'Cancelled connection retained active state');
        check(readCommands().filter(a => a.includes('up')).length === beforeCancelled + 1,
            'Cancelled sync still retried connection');
        Gio.File.new_for_path(`${root}/cancel-sync`).delete(null);
        results.push('Polkit cancellation clears busy state and never retries activation');
        toggle._subscriptionEntry.set_text('https://fixture.invalid/sub');
        toggle._addSubscription();
        await until(() => !toggle._busy && toggle._subscriptionEntry.get_text() === '', 'Subscription add did not finish');
        results.push('subscription entry -> add -> update -> sync -> clears entry');
        controls.find(button => button.label === 'Update').emit('clicked', 1);
        await until(() => !toggle._busy, 'Update subscriptions button stuck');
        results.push('actual Update button -> subscriptions update -> sync');
        controls.find(button => button.label === 'Manager').emit('clicked', 1);
        await until(() => readCommands().some(a => a[0].endsWith('wproxy-manager')), 'Manager not launched');
        results.push('actual Manager button -> manager executable');
        this.production.disable();
        check(qs._indicators.get_children().length === before, 'Disable left an indicator');
        this.production.enable();
        toggle = this.production._indicator.quickSettingsItems[0];
        await until(() => toggle._nodes.length === 2, 'Re-enable failed');
        check(qs._indicators.get_children().length === before + 1, 'Re-enable duplicated indicator');
        this.production.disable();
        check(qs._indicators.get_children().length === before, 'Second disable left indicator');
        this.production = null;
        this.restore();
        results.push('enable/disable/re-enable cleans timers and indicator without duplicates');
        return results;
    }
    disable() {
        this.production?.disable();
        this.restore?.();
    }
}
