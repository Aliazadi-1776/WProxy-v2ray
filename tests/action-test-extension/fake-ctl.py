#!/usr/bin/python3
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ['WPROXY_TEST_ROOT'])
args = sys.argv[1:]
with (root / 'commands.jsonl').open('a') as log:
    log.write(json.dumps(args) + '\n')
program = args.pop(0)
if program == 'pkexec':
    args.pop(0)
elif program.endswith('wproxy-manager'):
    sys.exit(0)
statefile = root / 'fake-state.json'
state = json.loads(statefile.read_text()) if statefile.exists() else {'active': False, 'node_id': None}
nodes = [{'id': '0123456789abcdef', 'name': 'Fixture A'}, {'id': 'fedcba9876543210', 'name': 'Fixture B'}]
if args == ['status', '--json']:
    print(json.dumps({**state, 'name': 'WProxy · Fixture A' if state['active'] else None}))
elif args == ['node', 'list', '--json']:
    print(json.dumps(nodes))
elif args == ['sub', 'list', '--json']:
    print(json.dumps([{'id': 'abc', 'name': 'Fixture', 'remaining_human': '4.84 GB left'}]))
elif args[:2] == ['node', 'ping']:
    time.sleep(0.1)
    print(json.dumps([{'id': row['id'], 'latency_ms': 42} for row in nodes if '--all' in args or row['id'] in args]))
elif args[:2] == ['nm', 'up']:
    missing = root / 'missing-profile'
    if missing.exists():
        missing.unlink()
        print('Unknown connection profile: sync required', file=sys.stderr)
        sys.exit(2)
    state = {'active': True, 'node_id': args[2]}
    statefile.write_text(json.dumps(state))
elif args == ['nm', 'down']:
    statefile.write_text(json.dumps({'active': False, 'node_id': None}))
elif args == ['nm', 'sync']:
    if (root / 'cancel-sync').exists():
        print('Authorization cancelled by fixture', file=sys.stderr)
        sys.exit(126)
elif args[:2] == ['sub', 'add']:
    print('abc')
elif args[:2] == ['sub', 'update']:
    pass
else:
    print('Unexpected fixture command: ' + repr(args), file=sys.stderr)
    sys.exit(99)
