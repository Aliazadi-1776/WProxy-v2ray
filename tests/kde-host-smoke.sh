#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VIEWER=${PLASMOIDVIEWER:-$(command -v plasmoidviewer || true)}
PACKAGE_TOOL=${KPACKAGETOOL:-$(command -v kpackagetool6 || true)}
if [ -z "$VIEWER" ] || [ -z "$PACKAGE_TOOL" ]; then
    echo 'Plasma SDK plasmoidviewer and kpackagetool6 are required.' >&2
    exit 2
fi
SHELL_PACKAGE=
IFS=: read -r -a DATA_DIRS <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for directory in "${DATA_DIRS[@]}"; do
    candidate="$directory/plasma/shells/org.kde.plasma.plasmoidviewershell"
    if [ -f "$candidate/metadata.json" ]; then SHELL_PACKAGE=$candidate; break; fi
done
if [ -z "$SHELL_PACKAGE" ]; then
    echo 'The Plasma SDK viewer shell package is required.' >&2
    exit 2
fi
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wproxy-kde-host.XXXXXX")
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
export XDG_DATA_HOME="$TEST_ROOT/data"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_DATA_DIRS="$XDG_DATA_HOME:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export QT_QPA_PLATFORM=offscreen
export QT_QUICK_BACKEND=software
export QT_QUICK_CONTROLS_STYLE=Basic
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_DATA_HOME/plasma/shells" "$XDG_CONFIG_HOME/wproxy" "$XDG_CACHE_HOME"
chmod 700 "$XDG_RUNTIME_DIR"
cp -a "$SHELL_PACKAGE" "$XDG_DATA_HOME/plasma/shells/"
python3 - "$REPO_ROOT" "$TEST_ROOT" <<'PY'
import json
from pathlib import Path
import sys
repo, root = map(Path, sys.argv[1:])
fixture = (repo / 'tests/kde-host/Desktop.qml').read_text()
fixture = fixture.replace('EVIDENCE_DIRECTORY', json.dumps(str(root)))
shell = root / 'data/plasma/shells/org.kde.plasma.plasmoidviewershell/contents/views/Desktop.qml'
shell.write_text(fixture)
store = {'nodes': [
    {'id': f'{index:016x}', 'name': f'Test server {index + 1:03d}',
     'uri': 'trojan://fixture@example.invalid:443?security=tls', 'source': None}
    for index in range(100)
], 'subs': [], 'routing': {'version': 1, 'mode': 'all', 'domains': [], 'apps': []},
    'preferences': {'auto_update': False, 'remember_authorization': False}}
path = root / 'config/wproxy/store.json'
path.write_text(json.dumps(store))
path.chmod(0o600)
PY
echo "KDE test directory: $TEST_ROOT"
"$VIEWER" --version > "$TEST_ROOT/runtime-version.txt" 2>&1
{
    "$PACKAGE_TOOL" --type Plasma/Applet --install "$REPO_ROOT/kde-plasmoid/org.wproxy.WProxy"
    "$PACKAGE_TOOL" --type Plasma/Applet --upgrade "$REPO_ROOT/kde-plasmoid/org.wproxy.WProxy"
    "$PACKAGE_TOOL" --type Plasma/Applet --remove org.wproxy.WProxy
    test ! -e "$XDG_DATA_HOME/plasma/plasmoids/org.wproxy.WProxy"
    "$PACKAGE_TOOL" --type Plasma/Applet --install "$REPO_ROOT/kde-plasmoid/org.wproxy.WProxy"
} > "$TEST_ROOT/package.log" 2>&1
timeout 20s dbus-run-session --config-file="$REPO_ROOT/tests/session-bus.conf" -- \
    "$VIEWER" --applet org.wproxy.WProxy --size 620x700 > "$TEST_ROOT/viewer.log" 2>&1
python3 - "$TEST_ROOT" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
prefix = 'qml: WPROXY_HOST_SMOKE '
results = [json.loads(line.split(prefix, 1)[1]) for line in (root / 'viewer.log').read_text().splitlines() if prefix in line]
assert len(results) == 1 and results[0]['ok'], results or (root / 'viewer.log').read_text()
assert (root / 'widget-100-last.png').stat().st_size > 1000
config = (root / 'config/plasmoidviewer-appletsrc').read_text()
assert config.count('plugin=org.wproxy.WProxy') == 1, 'Expected exactly one applet'
(root / 'result.json').write_text(json.dumps(results[0], indent=2) + '\n')
print(json.dumps(results[0]))
print('Temporary KPackage install/upgrade/remove/reinstall: PASS')
PY
