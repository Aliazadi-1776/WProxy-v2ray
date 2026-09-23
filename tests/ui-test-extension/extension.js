import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const delay = ms => new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
    resolve();
    return GLib.SOURCE_REMOVE;
}));
function check(condition, message) {
    if (!condition)
        throw new Error(message);
}

export default class UITest extends Extension {
    enable() {
        this.run().then(results => this.finish({ok: true, results}))
            .catch(error => this.finish({ok: false, error: String(error), stack: error.stack}));
    }

    finish(result) {
        GLib.file_set_contents(`${GLib.getenv('WPROXY_TEST_ROOT')}/result.json`, JSON.stringify(result, null, 2));
    }

    async run() {
        await delay(1000);
        const source = GLib.getenv('WPROXY_TEST_SOURCE');
        const {WProxyToggle} = await import(GLib.filename_to_uri(`${source}/extension.js`, null));
        // Fixture data only. All layout, rows, menu and scrolling are production code.
        WProxyToggle.prototype.refresh = function () {};
        this.indicator = new QuickSettings.SystemIndicator();
        this.indicator._icon = new St.Icon({icon_name: 'network-vpn-symbolic'});
        const toggle = new WProxyToggle(this.indicator);
        this.indicator.quickSettingsItems.push(toggle);
        Main.panel.statusArea.quickSettings.addExternalIndicator(this.indicator);
        St.ThemeContext.get_for_stage(global.stage).get_theme().load_stylesheet(
            Gio.File.new_for_path(`${source}/stylesheet.css`));
        toggle._renderStatus({active: false}, [{remaining_human: '4.84 GB left'}]);
        Main.panel.statusArea.quickSettings.menu.open();
        toggle.menu.open();
        const results = [];
        const settings = new Gio.Settings({schema_id: 'org.gnome.desktop.interface'});
        for (const textScale of [1, 1.4]) {
            settings.set_double('text-scaling-factor', textScale);
            await delay(300);
            for (const count of [0, 1, 3, 4, 100]) {
                toggle._nodes = Array.from({length: count}, (_, i) => ({
                    id: `node-${i}`, name: `🇩🇪 Server ${i + 1} — TCP`,
                }));
                toggle._renderNodes();
                await delay(250);
                const scroll = toggle._nodesScroll;
                const rows = scroll.get_child().get_children();
                const expected = rows.slice(0, 3).reduce((sum, row) => sum + row.height, 0);
                const adjustment = scroll.vadjustment;
                check(Math.abs(scroll.height - expected) < 2,
                    `${count} rows: viewport ${scroll.height} != first three ${expected}`);
                check(count <= 3 || adjustment.upper > adjustment.page_size,
                    `${count} rows: content is not scrollable`);
                if (count > 3) {
                    adjustment.value = adjustment.upper - adjustment.page_size;
                    await delay(50);
                    const before = adjustment.value;
                    toggle._latencies.set('node-0', 42);
                    toggle._renderNodes();
                    await delay(50);
                    check(adjustment.value === before, 'Refresh reset scroll position');
                    const [, lastY] = rows.at(-1).get_transformed_position();
                    const [, scrollY] = scroll.get_transformed_position();
                    check(lastY + rows.at(-1).height <= scrollY + scroll.height + 2,
                        'Cannot reach the last server');
                }
                const actions = toggle._actionsSection.actor;
                const [, actionsY] = actions.get_transformed_position();
                check(actionsY + actions.height <= global.stage.height,
                    `${textScale}/${count}: Bottom controls outside screen: ${actionsY + actions.height}`);
                results.push({textScale, count, viewport: scroll.height,
                    expected, scrollUpper: adjustment.upper, page: adjustment.page_size,
                    actionsBottom: actionsY + actions.height, screenHeight: global.stage.height});
            }
        }
        settings.set_double('text-scaling-factor', 1);
        toggle._nodesScroll.vadjustment.value = 0;
        await delay(300);
        const stream = Gio.File.new_for_path(`${GLib.getenv('WPROXY_TEST_ROOT')}/three-rows.png`)
            .replace(null, false, Gio.FileCreateFlags.NONE, null);
        await new Shell.Screenshot().screenshot(false, stream);
        stream.close(null);
        return results;
    }

    disable() {
        this.indicator?.quickSettingsItems.forEach(item => item.destroy());
        this.indicator?.destroy();
    }
}
