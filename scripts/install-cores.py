#!/usr/bin/env python3
"""Install pinned official sing-box/Mihomo binaries, never an imported profile's URL."""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
MAX_ARCHIVE = 128 * 1024 * 1024
MAX_BINARY = 256 * 1024 * 1024


def binary_bytes(data, name, executable):
    if name.endswith('.tar.gz'):
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
            matches = [item for item in archive.getmembers()
                       if item.isfile() and Path(item.name).name == executable]
            if len(matches) != 1 or matches[0].size > MAX_BINARY:
                raise ValueError('Official archive has no unique bounded core executable')
            with archive.extractfile(matches[0]) as source:
                return source.read(MAX_BINARY + 1)
    if name.endswith('.zip'):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            matches = [item for item in archive.infolist()
                       if not item.is_dir() and (Path(item.filename).name == executable
                           or (executable == 'mihomo.exe' and Path(item.filename).name.startswith('mihomo-')
                               and item.filename.endswith('.exe')))]
            if len(matches) != 1 or matches[0].file_size > MAX_BINARY:
                raise ValueError('Official archive has no unique bounded core executable')
            return archive.read(matches[0])
    if name.endswith('.gz'):
        with gzip.GzipFile(fileobj=io.BytesIO(data)) as source:
            return source.read(MAX_BINARY + 1)
    raise ValueError('Unsupported official archive format')


def install(destination, target):
    manifest = json.loads((ROOT / 'core-versions.json').read_text(encoding='utf-8'))
    destination.mkdir(parents=True, exist_ok=True)
    record_path = destination / 'installed.json'
    try:
        installed = json.loads(record_path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        installed = {}
    # Download and validate every replacement before replacing either installed executable.
    with tempfile.TemporaryDirectory(prefix='wproxy-cores-') as directory:
        pending = []
        for engine, info in manifest.items():
            if target not in info['assets']:
                raise ValueError(f'No pinned {engine} package for {target}')
            asset = info['assets'][target]
            executable = engine + ('.exe' if target.startswith('windows-') else '')
            current = destination / executable
            previous = installed.get(engine, {})
            if (current.is_file() and previous.get('archive_sha256') == asset['sha256']
                    and hashlib.sha256(current.read_bytes()).hexdigest() == previous.get('binary_sha256')):
                print(f'{engine} {info["version"]} already verified')
                continue
            url = f'https://github.com/{info["repository"]}/releases/download/v{info["version"]}/{asset["name"]}'
            request = urllib.request.Request(url, headers={'User-Agent': 'WProxy-core-installer'})
            with urllib.request.urlopen(request, timeout=60) as response:
                if not response.geturl().startswith('https://'):
                    raise ValueError('Core download redirected away from HTTPS')
                data = response.read(MAX_ARCHIVE + 1)
            if len(data) > MAX_ARCHIVE or hashlib.sha256(data).hexdigest() != asset['sha256']:
                raise ValueError(f'{engine} archive checksum mismatch; no core files replaced')
            binary = binary_bytes(data, asset['name'], executable)
            if len(binary) > MAX_BINARY:
                raise ValueError(f'{engine} executable is too large')
            staged = Path(directory) / executable
            staged.write_bytes(binary)
            installed[engine] = {'version': info['version'], 'archive_sha256': asset['sha256'],
                                 'binary_sha256': hashlib.sha256(binary).hexdigest(),
                                 'source_url': info['source_url']}
            pending.append((staged, current))
        for staged, current in pending:
            # Stage on the destination filesystem so rename is atomic even across mounts.
            fd, temporary = tempfile.mkstemp(prefix='.' + current.name + '-', dir=destination)
            try:
                with os.fdopen(fd, 'wb') as output:
                    output.write(staged.read_bytes())
                os.chmod(temporary, 0o755)
                os.replace(temporary, current)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
            print(f'Installed {current.name}')
    licenses = destination / 'licenses'
    licenses.mkdir(exist_ok=True)
    for notice in (ROOT / 'core-licenses').glob('*-LICENSE'):
        shutil.copyfile(notice, licenses / notice.name)
    shutil.copyfile(ROOT / 'core-versions.json', licenses / 'core-versions.json')
    record_path.write_text(json.dumps(installed, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--platform', choices=('linux', 'windows'),
                        default='windows' if os.name == 'nt' else 'linux')
    parser.add_argument('--arch', choices=('amd64', 'arm64'), default={
        'x86_64': 'amd64', 'AMD64': 'amd64', 'aarch64': 'arm64', 'arm64': 'arm64',
    }.get(platform.machine()))
    args = parser.parse_args()
    if args.arch is None:
        parser.error('Unsupported CPU architecture')
    try:
        install(args.destination.resolve(), args.platform + '-' + args.arch)
    except (OSError, ValueError, tarfile.TarError, zipfile.BadZipFile) as error:
        print(f'WProxy core installation failed: {error}', file=sys.stderr)
        sys.exit(2)
