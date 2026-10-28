#!/usr/bin/env python3
"""Destructive-but-reversible live split-routing check for a Linux workstation.

The test temporarily replaces the current routing policy, synchronizes the
user's WProxy NetworkManager profiles, connects one saved node, and compares
public-IP probes without printing the addresses. The original policy is
restored in a finally block. Run only from the user's normal desktop session.
"""

import argparse
import importlib.util
import ipaddress
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('wproxyctl_live_routing', ROOT / 'cli/wproxyctl.py')
CTL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CTL)
PRIMARY_PROBE = 'https://checkip.amazonaws.com'
SECONDARY_PROBE = 'https://icanhazip.com'


def validate_ip(value):
    return str(ipaddress.ip_address(value.strip()))


def python_probe(url, timeout):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    request = urllib.request.Request(url, headers={'User-Agent': 'WProxy-routing-smoke/1'})
    with opener.open(request, timeout=timeout) as response:
        return validate_ip(response.read(128).decode('ascii'))


def curl_probe(url, timeout):
    curl = shutil.which('curl')
    if not curl:
        raise RuntimeError('curl is required for the live routing smoke test')
    result = subprocess.run(
        [curl, '--silent', '--show-error', '--fail', '--ipv4', '--noproxy', '*',
         '--max-time', str(timeout), url],
        text=True, capture_output=True, timeout=timeout + 3,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or 'curl IP probe failed')
    return validate_ip(result.stdout)


def retry_probe(probe, url, timeout, attempts=2):
    """Retry transient endpoint/TLS failures without masking routing mismatches."""
    last_error = None
    for attempt in range(attempts):
        try:
            return probe(url, timeout)
        except Exception as error:
            last_error = error
            if attempt + 1 < attempts:
                time.sleep(1)
    raise last_error


def sync_profiles():
    helper = Path('/usr/libexec/wproxy-admin')
    command = (['pkexec', str(helper), 'sync'] if helper.is_file() else
               ['pkexec', sys.executable, str(ROOT / 'cli/wproxyctl.py'), 'nm', 'sync'])
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'Profile sync was cancelled')


def apply_policy(store, policy):
    store['routing'] = CTL.normalize_routing_policy(policy)
    CTL.save_store(store)
    sync_profiles()


def connect(store, node_id):
    CTL.nm_up(store, node_id)
    status = CTL.status_json(store)
    if not status.get('active') or status.get('node_id') != node_id:
        raise RuntimeError('NetworkManager did not report the selected WProxy node as active')


def find_working_node(store, candidates, baseline, timeout):
    """Select a node that carries real HTTPS traffic before testing rules."""
    print('Checking saved nodes for a working tunnel…')
    apply_policy(store, {'mode': 'all', 'domains': [], 'apps': []})
    probe_timeout = min(timeout, 10)
    for index, node in enumerate(candidates, start=1):
        try:
            connect(store, node['id'])
            proxied_primary = retry_probe(python_probe, PRIMARY_PROBE, probe_timeout)
            proxied_secondary = retry_probe(python_probe, SECONDARY_PROBE, probe_timeout)
            if (proxied_primary != baseline['primary'] and
                    proxied_secondary != baseline['secondary']):
                print(f'PASS  tunnel preflight: candidate {index} carries both HTTPS probes')
                return node['id']
        except Exception as error:
            print(f'SKIP  tunnel candidate {index}: {error}')
        finally:
            CTL.nm_down()
    raise RuntimeError('None of the selected saved nodes carried HTTPS through the tunnel')


def check_only_empty(store, node_id, baseline, timeout):
    apply_policy(store, {'mode': 'only', 'domains': [], 'apps': []})
    connect(store, node_id)
    python_direct = python_probe(PRIMARY_PROBE, timeout)
    curl_direct = curl_probe(SECONDARY_PROBE, timeout)
    if python_direct != baseline['primary'] or curl_direct != baseline['secondary']:
        raise AssertionError('Only-empty mode was not direct; the saved routing policy was not applied')
    print('PASS  only-empty: unmatched traffic stayed direct')
    CTL.nm_down()


def check_only_app(store, node_id, baseline, timeout):
    curl_path = str(Path(shutil.which('curl')).resolve())
    apply_policy(store, {'mode': 'only', 'domains': [], 'apps': [curl_path]})
    connect(store, node_id)
    selected = retry_probe(curl_probe, SECONDARY_PROBE, timeout)
    unselected = python_probe(PRIMARY_PROBE, timeout)
    if selected == baseline['secondary']:
        raise AssertionError('Only-app mode did not send curl through the proxy')
    if unselected != baseline['primary']:
        raise AssertionError('Only-app mode unexpectedly proxied the unselected Python process')
    print('PASS  only-app: selected process proxied; unselected process stayed direct')
    CTL.nm_down()


def check_bypass_app(store, node_id, baseline, timeout):
    curl_path = str(Path(shutil.which('curl')).resolve())
    apply_policy(store, {'mode': 'bypass', 'domains': [], 'apps': [curl_path]})
    connect(store, node_id)
    selected = curl_probe(SECONDARY_PROBE, timeout)
    unselected = python_probe(PRIMARY_PROBE, timeout)
    if selected != baseline['secondary']:
        raise AssertionError('Bypass-app mode did not keep curl on the direct route')
    if unselected == baseline['primary']:
        raise AssertionError('Bypass-app mode did not proxy the unselected Python process')
    print('PASS  bypass-app: selected process stayed direct; other traffic was proxied')
    CTL.nm_down()


def check_only_domain(store, node_id, baseline, timeout):
    apply_policy(store, {'mode': 'only', 'domains': ['icanhazip.com'], 'apps': []})
    connect(store, node_id)
    selected = retry_probe(python_probe, SECONDARY_PROBE, timeout)
    unselected = python_probe(PRIMARY_PROBE, timeout)
    if selected == baseline['secondary']:
        raise AssertionError('Only-domain mode did not send the selected hostname through the proxy')
    if unselected != baseline['primary']:
        raise AssertionError('Only-domain mode unexpectedly proxied the unselected hostname')
    print('PASS  only-domain: selected hostname proxied; other hostname stayed direct')
    CTL.nm_down()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm', action='store_true', help='confirm temporary live network changes')
    parser.add_argument('--node', help='saved WProxy node ID; defaults to the first node')
    parser.add_argument('--timeout', type=int, default=12)
    parser.add_argument(
        '--case', choices=('all', 'only-empty', 'bypass-app', 'only-app', 'only-domain'),
        default='all', help='run one routing case after the tunnel preflight',
    )
    args = parser.parse_args()
    if not args.confirm:
        parser.error('--confirm is required because this test temporarily changes live routing')
    if os.name == 'nt' or os.geteuid() == 0:
        parser.error('run as the normal Linux desktop user, not root')
    if not shutil.which('pkexec') or not shutil.which('nmcli'):
        parser.error('pkexec and NetworkManager/nmcli are required')

    store = CTL.load_store()
    if not store['nodes']:
        parser.error('no saved WProxy nodes are available')
    original_policy = CTL.normalize_routing_policy(store.get('routing'))
    if args.node and not any(node['id'] == args.node for node in store['nodes']):
        parser.error('the selected node ID is not in the current user store')
    print('Checking direct baseline (the public IP is intentionally not printed)…')
    baseline = {
        'primary': python_probe(PRIMARY_PROBE, args.timeout),
        'secondary': python_probe(SECONDARY_PROBE, args.timeout),
    }

    try:
        candidates = [node for node in store['nodes'] if not args.node or node['id'] == args.node]
        node_id = find_working_node(store, candidates, baseline, args.timeout)
        cases = {
            'only-empty': check_only_empty,
            'bypass-app': check_bypass_app,
            'only-app': check_only_app,
            'only-domain': check_only_domain,
        }
        selected = cases if args.case == 'all' else {args.case: cases[args.case]}
        for check in selected.values():
            check(store, node_id, baseline, args.timeout)
    finally:
        CTL.nm_down()
        store = CTL.load_store()
        store['routing'] = original_policy
        CTL.save_store(store)
        try:
            sync_profiles()
            print('RESTORED  original routing policy and NetworkManager profiles')
        except Exception as error:
            print(f'RESTORE WARNING  policy was restored locally; profile sync failed: {error}', file=sys.stderr)
            print('Run: sudo wproxyctl nm sync', file=sys.stderr)


if __name__ == '__main__':
    main()
