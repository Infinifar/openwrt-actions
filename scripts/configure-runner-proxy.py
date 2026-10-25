#!/usr/bin/env python3
"""Backed-up infrastructure migration; stop v2rayA before applying or rolling back."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import yaml

NETWORK = 'openwrt-ci-proxy'
ALIAS = 'v2raya-build-proxy'
PROXY_PORTS = {20170, 20171, 20172, 20177}


def configure_compose(original, service, proxy=False):
    config = copy.deepcopy(original)
    item = config['services'][service]
    nets = item.get('networks')
    if nets is None:
        nets = {'default': None}
        config.setdefault('networks', {}).setdefault('default', {})
    if isinstance(nets, list):
        nets = {name: None for name in nets}
    if not isinstance(nets, dict):
        raise ValueError('Unsupported Compose networks declaration')
    entry = nets.get(NETWORK) or {}
    if proxy:
        entry['aliases'] = list(dict.fromkeys(entry.get('aliases', []) + [ALIAS]))
    nets[NETWORK] = entry
    item['networks'] = nets
    existing = config.setdefault('networks', {}).get(NETWORK)
    if existing is not None and existing != {'external': True}:
        raise ValueError('Refusing to overwrite a custom proxy network')
    config['networks'][NETWORK] = {'external': True}
    if proxy:
        ports = []
        for binding in item.get('ports', []):
            if isinstance(binding, dict):
                binding = copy.deepcopy(binding)
                if int(binding['target']) in PROXY_PORTS:
                    binding['host_ip'] = '127.0.0.1'
            elif isinstance(binding, str):
                match = re.fullmatch(r'(?:0\.0\.0\.0:|127\.0\.0\.1:)?(\$\{[^}]+\}|\d+):(20170|20171|20172|20177)(/tcp)?', binding)
                if match:
                    binding = f'127.0.0.1:{match[1]}:{match[2]}{match[3] or ""}'
                elif re.search(r':(?:20170|20171|20172|20177)(?:/tcp)?$', binding):
                    raise ValueError('Unrecognized proxy binding; refuse accidental exposure')
            else:
                raise ValueError('Unsupported Compose port binding')
            ports.append(binding)
        item['ports'] = ports
    return config


def sharing_setting(value):
    setting = json.loads(value)
    if type(setting.get('portSharing')) is not bool:
        raise ValueError('Unsupported v2rayA portSharing setting')
    setting['portSharing'] = True
    return json.dumps(setting, ensure_ascii=False, separators=(',', ':'))


def stopped():
    running = subprocess.check_output(['docker', 'inspect', '--format', '{{.State.Running}}', 'v2raya'], text=True).strip()
    if running != 'false':
        raise ValueError('Stop v2rayA before editing its persistent settings')


def atomic(path, data, mode, uid, gid):
    temporary = path.with_name(path.name + f'.ci-proxy-{os.getpid()}')
    try:
        with temporary.open('xb') as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        temporary.chmod(mode)
        os.chown(temporary, uid, gid)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def migrate(v2raya, runner, backup):
    stopped()
    backup.mkdir(mode=0o700, parents=False, exist_ok=False)
    entries = []
    for directory, service, proxy in [(v2raya, 'v2raya', True), (runner, 'openwrt-runner', False)]:
        path = directory / 'docker-compose.yml'
        if path.is_symlink():
            raise ValueError('Refusing a Compose symlink')
        before = path.read_bytes()
        after = yaml.safe_dump(configure_compose(yaml.safe_load(before), service, proxy), allow_unicode=True, sort_keys=False).encode()
        stat = path.stat()
        saved = backup / (directory.name + '.compose.yml')
        saved.write_bytes(before)
        saved.chmod(0o600)
        staged = directory / f'.compose-ci-proxy-{os.getpid()}.yml'
        staged.write_bytes(after)
        staged.chmod(0o600)
        try:
            subprocess.run(['docker', 'compose', '-f', str(staged), 'config', '--quiet'], check=True)
        finally:
            staged.unlink(missing_ok=True)
        entries.append({'path': str(path), 'saved': str(saved), 'before': hashlib.sha256(before).hexdigest(),
                        'after': hashlib.sha256(after).hexdigest(), 'mode': stat.st_mode & 0o777,
                        'uid': stat.st_uid, 'gid': stat.st_gid, 'bytes': after})
    db = sqlite3.connect('file:' + str(v2raya / 'data/v2raya.db') + '?mode=rw', uri=True)
    saved_db = sqlite3.connect(str(backup / 'v2raya.db'))
    db.backup(saved_db)
    saved_db.close()
    (backup / 'v2raya.db').chmod(0o600)
    setting = db.execute('SELECT value FROM system_config WHERE key=?', ('system:setting',)).fetchone()[0]
    (backup / 'setting.json').write_text(setting)
    (backup / 'setting.json').chmod(0o600)
    manifest = [{key: value for key, value in entry.items() if key != 'bytes'} for entry in entries]
    (backup / 'manifest.json').write_text(json.dumps({'files': manifest, 'v2raya': str(v2raya)}, indent=2))
    updated = sharing_setting(setting)
    written = []
    try:
        for entry in entries:
            path = Path(entry['path'])
            if hashlib.sha256(path.read_bytes()).hexdigest() != entry['before']:
                raise ValueError('Compose changed concurrently; refusing deployment')
        with db:
            count = db.execute('UPDATE system_config SET value=? WHERE key=? AND value=?', (updated, 'system:setting', setting)).rowcount
            if count != 1:
                raise ValueError('v2rayA settings changed concurrently')
            for entry in entries:
                atomic(Path(entry['path']), entry['bytes'], entry['mode'], entry['uid'], entry['gid'])
                written.append(entry)
        print('Proxy sharing enabled; proxy host mappings limited to loopback; both Compose files validated and backed up.')
    except Exception:
        for entry in written:
            if hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest() == entry['after']:
                atomic(Path(entry['path']), Path(entry['saved']).read_bytes(), entry['mode'], entry['uid'], entry['gid'])
        raise
    finally:
        db.close()


def rollback(backup):
    stopped()
    manifest = json.loads((backup / 'manifest.json').read_text())
    for entry in manifest['files']:
        current = hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()
        if current not in {entry['before'], entry['after']}:
            raise ValueError('Compose changed since deployment; manual merge required')
    for entry in manifest['files']:
        atomic(Path(entry['path']), Path(entry['saved']).read_bytes(), entry['mode'], entry['uid'], entry['gid'])
    with sqlite3.connect(str(Path(manifest['v2raya']) / 'data/v2raya.db')) as db:
        current = json.loads(db.execute('SELECT value FROM system_config WHERE key=?', ('system:setting',)).fetchone()[0])
        current['portSharing'] = json.loads((backup / 'setting.json').read_text())['portSharing']
        db.execute('UPDATE system_config SET value=? WHERE key=?', (json.dumps(current), 'system:setting'))
    print('Original Compose files and port-sharing preference restored; accounts/nodes untouched.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['apply', 'rollback'])
    parser.add_argument('--backup', required=True, type=Path)
    parser.add_argument('--v2raya', type=Path)
    parser.add_argument('--runner', type=Path)
    args = parser.parse_args()
    if args.mode == 'apply':
        if not args.v2raya or not args.runner:
            parser.error('apply needs --v2raya and --runner directories')
        migrate(args.v2raya.resolve(), args.runner.resolve(), args.backup.resolve())
    else:
        rollback(args.backup.resolve())
