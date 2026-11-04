#!/usr/bin/env python3
"""Exercise the installed manager's Linux helper, full tunnel and YouTube."""

import argparse
import json
import subprocess
import time


CTL = '/usr/bin/wproxyctl'
HELPER = '/usr/libexec/wproxy-admin'


def command(args, timeout=45):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def status():
    result = command([CTL, 'status', '--json', '--telemetry'])
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


def youtube():
    started = time.monotonic()
    result = command([
        'curl', '--noproxy', '*', '--location', '--fail', '--silent', '--show-error',
        '--connect-timeout', '8', '--max-time', '20',
        '--user-agent', 'Mozilla/5.0', 'https://www.youtube.com/',
    ], timeout=23)
    if result.returncode:
        raise RuntimeError('YouTube request failed: ' + result.stderr.strip())
    if 'ytInitialData' not in result.stdout or 'YouTube' not in result.stdout:
        raise RuntimeError('YouTube response did not contain its home page data')
    print(f'PASS YouTube: home page data received ({len(result.stdout)} characters, '
          f'{time.monotonic() - started:.1f}s)', flush=True)


def connect(node):
    started = time.monotonic()
    result = command(['pkexec', HELPER, 'up', node], timeout=65)
    print(f'Installed helper: exit={result.returncode}, elapsed={time.monotonic() - started:.1f}s', flush=True)
    if result.stdout:
        print(result.stdout.strip(), flush=True)
    if result.stderr:
        print(result.stderr.strip(), flush=True)
    if result.returncode:
        raise RuntimeError('Installed manager connection path failed')
    current = status()
    print('Installed status: ' + json.dumps(current), flush=True)
    if not current.get('active') or current.get('node_id') != node:
        raise RuntimeError('Selected node did not become active')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm', action='store_true')
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument('--node')
    selection.add_argument('--quick', action='store_true')
    parser.add_argument('--switch-node')
    parser.add_argument('--hold', type=int, default=0)
    parser.add_argument('--temporary-all', action='store_true')
    args = parser.parse_args()
    if not args.confirm:
        parser.error('--confirm is required for temporary full-tunnel changes')
    initial = status()
    manager = command(['systemctl', 'show', 'NetworkManager', '--property=MainPID', '--value'])
    manager_pid = manager.stdout.strip() if manager.returncode == 0 else None
    if initial.get('active'):
        parser.error('Disconnect the current WProxy session before this test')
    original_mode = initial.get('routing_mode', 'all')
    if original_mode != 'all' and not args.temporary_all:
        parser.error('This test requires the existing All traffic policy')

    if args.quick:
        result = command([CTL, 'node', 'best', '--verify', '--json', '--timeout', '2'], timeout=65)
        if result.returncode:
            raise RuntimeError('Installed Quick Connect selection failed: ' + result.stderr.strip())
        selected = json.loads(result.stdout)
        args.node = selected['id']
        print('Installed Quick Connect: ' + json.dumps(selected), flush=True)

    # This independent process restores connectivity even if the parent or
    # remote session gets stuck while the full-tunnel route is being tested.
    watchdog = subprocess.Popen([
        'bash', '-c', 'sleep 300; /usr/bin/wproxyctl nm down >/dev/null 2>&1; '
        '/usr/bin/wproxyctl routing mode "$1" >/dev/null; '
        'pkexec /usr/libexec/wproxy-admin sync >/dev/null 2>&1', 'watchdog', original_mode,
    ], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    failures = []
    try:
        if original_mode != 'all':
            result = command([CTL, 'routing', 'mode', 'all'])
            if result.returncode:
                raise RuntimeError(result.stderr.strip())
        connect(args.node)
        try:
            youtube()
        except RuntimeError as error:
            failures.append(str(error))
            print('FAIL ' + str(error), flush=True)
        if args.switch_node:
            connect(args.switch_node)
            try:
                youtube()
            except RuntimeError as error:
                failures.append(str(error))
                print('FAIL ' + str(error), flush=True)
        if args.hold:
            print('HOLD: tunnel available for browser validation', flush=True)
            time.sleep(min(45, max(0, args.hold)))
    finally:
        result = command([CTL, 'nm', 'down'], timeout=20)
        print('Cleanup: ' + str(result.returncode), flush=True)
        if original_mode != 'all':
            command([CTL, 'routing', 'mode', original_mode])
            result = command(['pkexec', HELPER, 'sync'])
            if result.returncode:
                raise RuntimeError('Could not restore installed profiles: ' + result.stderr.strip())
        print('Final status: ' + json.dumps(status()), flush=True)
        watchdog.terminate()
        watchdog.wait(timeout=3)
        if manager_pid:
            manager = command(['systemctl', 'show', 'NetworkManager', '--property=MainPID', '--value'])
            if manager.returncode or manager.stdout.strip() != manager_pid:
                raise RuntimeError('NetworkManager restarted during the installed connection test')
            print('PASS NetworkManager: process survived the connection test', flush=True)
    if failures:
        raise RuntimeError('; '.join(failures))


if __name__ == '__main__':
    main()
