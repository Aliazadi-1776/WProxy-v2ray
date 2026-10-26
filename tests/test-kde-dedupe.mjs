import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../scripts/kde-dedupe-widget.js', import.meta.url), 'utf8');

function widget(type) {
    return {type, removed: false, remove() { this.removed = true; }};
}

function containment(items, config = {}) {
    const byId = new Map(items.map((item, index) => [index + 1, item]));
    return {
        get widgetIds() { return [...byId].filter(([, item]) => !item.removed).map(([id]) => id); },
        widgetById(id) { return byId.get(id); },
        readConfig(key) { return config[key] ?? ''; },
        writeConfig(key, value) { config[key] = Array.isArray(value) ? value.join(',') : value; },
        reloadConfig() { this.reloaded = true; },
        config,
        reloaded: false,
    };
}

const trayCopies = [widget('org.wproxy.WProxy'), widget('org.wproxy.WProxy')];
const tray = containment(trayCopies, {
    extraItems: 'org.example.Clock,org.wproxy.WProxy,org.wproxy.WProxy',
});
const trayApplet = widget('org.kde.plasma.systemtray');
trayApplet.readConfig = () => 77;
const directCopies = [widget('org.wproxy.WProxy'), widget('org.wproxy.WProxy')];
const panelWithTray = containment([trayApplet, ...directCopies]);

const standaloneCopies = [widget('org.wproxy.WProxy'), widget('org.wproxy.WProxy')];
const panelWithoutTray = containment(standaloneCopies);
const output = [];
const context = vm.createContext({
    panels: () => [panelWithTray, panelWithoutTray],
    desktopById: (id) => id === 77 ? tray : null,
    print: (message) => output.push(message),
});

vm.runInContext(source, context);

assert.deepEqual(tray.config.extraItems.split(','), ['org.example.Clock', 'org.wproxy.WProxy']);
assert.equal(tray.reloaded, true);
assert.equal(trayCopies.filter((item) => !item.removed).length, 1);
assert.equal(directCopies.filter((item) => !item.removed).length, 0);
assert.equal(standaloneCopies.filter((item) => !item.removed).length, 1);
assert.deepEqual(output, ['WProxy panel cleanup: removed 4 duplicate widget(s).']);
console.log('KDE widget deduplication: PASS');
