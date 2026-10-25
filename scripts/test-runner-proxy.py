#!/usr/bin/env python3
import copy
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import yaml

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('proxy', ROOT / 'scripts/configure-runner-proxy.py')
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)
BASE = {'services': {'v2raya': {'image':'example:fixed','environment':['UNCHANGED=1'],
        'ports':['${UI_PORT:-2017}:2017','${HTTP_PORT:-20171}:20171','20170:20170','20177:20177'],
        'volumes':['./data:/etc/v2raya'], 'healthcheck':{'test':['CMD','true']}}}}


class ProxyTests(unittest.TestCase):
    def test_proxy_loopback_and_network(self):
        before = copy.deepcopy(BASE)
        after = proxy.configure_compose(before, 'v2raya', True)
        item = after['services']['v2raya']
        self.assertEqual(item['ports'][0], '${UI_PORT:-2017}:2017')
        self.assertEqual(item['ports'][1], '127.0.0.1:${HTTP_PORT:-20171}:20171')
        self.assertEqual(item['networks'][proxy.NETWORK]['aliases'], [proxy.ALIAS])
        for key in ['image','environment','volumes','healthcheck']:
            self.assertEqual(item[key], before['services']['v2raya'][key])
        self.assertEqual(before, BASE)
        self.assertEqual(proxy.configure_compose(after,'v2raya',True),after)

    def test_runner_retains_existing_network_and_volumes(self):
        before = {'services':{'openwrt-runner':{'networks':['1panel-network'],'volumes':['./config:/etc/gitlab-runner']}},'networks':{'1panel-network':{'external':True}}}
        after = proxy.configure_compose(before,'openwrt-runner')
        self.assertIn('1panel-network',after['services']['openwrt-runner']['networks'])
        self.assertEqual(after['services']['openwrt-runner']['volumes'],before['services']['openwrt-runner']['volumes'])

    def test_unknown_binding_and_network_collision(self):
        broken = copy.deepcopy(BASE)
        broken['services']['v2raya']['ports']=['[::]:20171:20171']
        with self.assertRaises(ValueError):
            proxy.configure_compose(broken,'v2raya',True)
        broken = copy.deepcopy(BASE)
        broken['networks']={proxy.NETWORK:{'internal':False}}
        with self.assertRaises(ValueError):
            proxy.configure_compose(broken,'v2raya',True)

    def test_sharing_preserves_all_other_settings(self):
        before={'portSharing':False,'transparent':'close','other':{'value':'unchanged'}}
        after=json.loads(proxy.sharing_setting(json.dumps(before)))
        self.assertTrue(after.pop('portSharing'))
        before.pop('portSharing')
        self.assertEqual(after,before)
        with self.assertRaises(ValueError):
            proxy.sharing_setting('{}')

    @patch.object(proxy, 'stopped')
    @patch.object(proxy.subprocess, 'run')
    def test_backup_apply_and_rollback(self, compose_check, stopped):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            v2raya=root/'v2raya'
            runner=root/'runner'
            (v2raya/'data').mkdir(parents=True)
            runner.mkdir()
            vf=v2raya/'docker-compose.yml'
            rf=runner/'docker-compose.yml'
            vf.write_text(yaml.safe_dump(BASE))
            rf.write_text(yaml.safe_dump({'services':{'openwrt-runner':{'networks':['1panel-network']}}}))
            originals={vf:vf.read_bytes(),rf:rf.read_bytes()}
            with sqlite3.connect(v2raya/'data/v2raya.db') as db:
                db.execute('CREATE TABLE system_config (key TEXT PRIMARY KEY,value TEXT)')
                db.execute('INSERT INTO system_config VALUES (?,?)',('system:setting',json.dumps({'portSharing':False,'transparent':'close'})))
                db.execute('INSERT INTO system_config VALUES (?,?)',('fixture:identity','never-change'))
            backup=root/'backup'
            proxy.migrate(v2raya,runner,backup)
            self.assertEqual(backup.stat().st_mode & 0o777,0o700)
            self.assertEqual((backup/'v2raya.db').stat().st_mode & 0o777,0o600)
            with sqlite3.connect(v2raya/'data/v2raya.db') as db:
                self.assertTrue(json.loads(db.execute('SELECT value FROM system_config WHERE key="system:setting"').fetchone()[0])['portSharing'])
                self.assertEqual(db.execute('SELECT value FROM system_config WHERE key="fixture:identity"').fetchone()[0],'never-change')
            proxy.rollback(backup)
            for path,data in originals.items():
                self.assertEqual(path.read_bytes(),data)
            with sqlite3.connect(v2raya/'data/v2raya.db') as db:
                self.assertFalse(json.loads(db.execute('SELECT value FROM system_config WHERE key="system:setting"').fetchone()[0])['portSharing'])


if __name__=='__main__':
    unittest.main()
