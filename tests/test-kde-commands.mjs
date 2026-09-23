import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {spawnSync} from 'node:child_process';

const source = fs.readFileSync(new URL('../kde-plasmoid/org.wproxy.WProxy/contents/code/Commands.js', import.meta.url), 'utf8');
const api = vm.createContext({});
vm.runInContext(source, api);
for (const value of ['', 'ordinary', "'", '$(printf INJECTED)', '; printf INJECTED', 'line1\nline2', 'https://example.invalid/?a=1&b="x"', 'فارسی']) {
    const result = spawnSync('/bin/sh', ['-c', api.command(['/usr/bin/printf', '%s', value])], {encoding: 'utf8'});
    assert.equal(result.status, 0);
    assert.equal(result.stdout, value);
}
assert.equal(api.needsSync('Unknown connection'), true);
assert.equal(api.needsSync('Connection activation failed: Unknown reason'), false);
assert.equal(api.latencyText('a', {a: null}, {}), 'Timeout');
assert.equal(api.latencyText('a', {a: 0}, {}), '0 ms');
assert.equal(api.latencyText('a', {}, {a: true}), '…');
assert.equal(api.latencyText('a', {}, {}), 'Ping');
console.log('KDE command quoting and state helpers: PASS');
