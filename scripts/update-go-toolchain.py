#!/usr/bin/env python3
"""Patch-release upgrade of LEDE's Go recipe; never weaken a module requirement."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def version(value):
    if not re.fullmatch(r'1\.\d+\.\d+', value):
        raise ValueError('Expected a stable Go patch version')
    return tuple(map(int, value.split('.')))


def field(text, name):
    hits = re.findall(r'^' + re.escape(name) + r':=([^\s]+)\s*$', text, re.M)
    if len(hits) != 1:
        raise ValueError('Missing, duplicate or unsupported recipe field: ' + name)
    return hits[0]


def required_go(text):
    hits = re.findall(r'^go\s+(1\.\d+(?:\.\d+)?)\s*$', text, re.M)
    if len(hits) != 1:
        raise ValueError('Tailscale go.mod must declare exactly one Go version')
    return hits[0] if hits[0].count('.') == 2 else hits[0] + '.0'


def upgraded_recipe(text, pin, required):
    pinned = version(pin['version'])
    if not re.fullmatch(r'[0-9a-f]{64}', pin['sha256']):
        raise ValueError('Invalid official Go source checksum')
    if pin['source'] != f"https://go.dev/dl/go{pin['version']}.src.tar.gz":
        raise ValueError('Untrusted Go source URL')
    family = field(text, 'GO_VERSION_MAJOR_MINOR')
    current = version(family + '.' + field(text, 'GO_VERSION_PATCH'))
    current_hash = field(text, 'PKG_HASH')
    if not re.fullmatch(r'[0-9a-f]{64}', current_hash):
        raise ValueError('The Go feed must provide a real source SHA256, not skip')
    selected = max(current, pinned)
    if selected < version(required):
        raise ValueError(f'Tailscale requires Go {required}; update the verified Go pin/recipe before compiling')
    if selected == current:
        return text, '.'.join(map(str, current))
    if family != '.'.join(map(str, pinned[:2])):
        raise ValueError('A Go family migration requires a reviewed OpenWrt recipe, not a version substitution')
    text = re.sub(r'^GO_VERSION_PATCH:=[^\n]+', f'GO_VERSION_PATCH:={pinned[2]}', text, count=1, flags=re.M)
    text = re.sub(r'^PKG_HASH:=[^\n]+', 'PKG_HASH:=' + pin['sha256'], text, count=1, flags=re.M)
    return text, pin['version']


def download(url):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read(8 * 1024 * 1024 + 1)
                if len(data) > 8 * 1024 * 1024:
                    raise ValueError('Upstream metadata response is unexpectedly large')
                return data.decode('utf-8')
        except (OSError, TimeoutError):
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def prepare(tree):
    pin = json.loads((ROOT / 'ci/go-toolchain.json').read_text())
    recipe = tree / 'feeds/packages/lang/golang/golang/Makefile'
    before = recipe.read_text()
    tailscale = field((tree / 'package/tailscale/Makefile').read_text(), 'PKG_VERSION')
    if not re.fullmatch(r'\d+\.\d+\.\d+', tailscale):
        raise ValueError('Tailscale package version must be an exact upstream tag')
    mod_url = f'https://raw.githubusercontent.com/tailscale/tailscale/v{tailscale}/go.mod'
    required = required_go(download(mod_url))
    after, selected = upgraded_recipe(before, pin, required)
    if after != before:
        # Confirm that this pinned checksum still matches the official metadata.
        releases = json.loads(download(pin['metadata']))
        sources = [f for r in releases if r.get('stable') and r.get('version') == 'go' + selected
                   for f in r.get('files', []) if f.get('kind') == 'source']
        if len(sources) != 1 or sources[0].get('sha256') != pin['sha256'] or sources[0].get('filename') != f'go{selected}.src.tar.gz':
            raise ValueError('Official Go release metadata does not match the reviewed pin')
        temporary = recipe.with_name(f'.Makefile.go-upgrade-{os.getpid()}')
        try:
            with temporary.open('x') as output:
                output.write(after)
                output.flush()
                os.fsync(output.fileno())
            temporary.chmod(recipe.stat().st_mode & 0o777)
            if recipe.read_text() != before:
                raise ValueError('Go recipe changed concurrently')
            temporary.replace(recipe)
        finally:
            temporary.unlink(missing_ok=True)
    report = {'go_version': selected, 'tailscale_version': tailscale,
              'tailscale_required_go': required, 'tailscale_go_mod': mod_url,
              'source_sha256': field(after, 'PKG_HASH'), 'toolchain_mode': 'local'}
    logs = ROOT / '.ci-logs'
    logs.mkdir(exist_ok=True)
    (logs / 'go-toolchain.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Info: OpenWrt Go {selected}; Tailscale {tailscale} requires Go >= {required}; SHA256 checked')


def check_built(tree):
    report = json.loads((ROOT / '.ci-logs/go-toolchain.json').read_text())
    binary = tree / 'staging_dir/hostpkg/lib/go-cross/bin/go'
    result = subprocess.check_output([str(binary), 'version'], text=True,
                                    env=dict(os.environ, GOTOOLCHAIN='local', GOENV='off'))
    match = re.search(r'\bgo(1\.\d+\.\d+)\b', result)
    if not match or version(match[1]) < version(report['go_version']) or version(match[1]) < version(report['tailscale_required_go']):
        raise ValueError('The actual OpenWrt host Go compiler is stale or too old')
    print('Verified actual OpenWrt compiler: ' + result.strip())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'check-built'])
    parser.add_argument('tree', type=Path)
    args = parser.parse_args()
    (prepare if args.mode == 'prepare' else check_built)(args.tree.resolve())
