#!/usr/bin/env python3
"""Negative export fixtures; no device, network or private input is accessed."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]

class PublicTemplateTests(unittest.TestCase):
    def check(self, edit=None):
        with tempfile.TemporaryDirectory(prefix='public-template-test-') as folder:
            tree = Path(folder)/'repo'
            shutil.copytree(ROOT,tree,ignore=shutil.ignore_patterns('.git','__pycache__'))
            if edit:
                edit(tree)
            result = subprocess.run([sys.executable,'-B',str(tree/'scripts/validate-public-config.py')],capture_output=True,text=True)
            self.assertEqual(result.returncode == 0,edit is None,result.stdout+result.stderr)

    def update_yaml(self,tree,rel,edit):
        p=tree/rel
        d=yaml.safe_load(p.read_text())
        edit(d)
        p.write_text(yaml.safe_dump(d,sort_keys=False))

    def test_current_template_passes(self):
        self.check()

    def test_adguard_account_and_rewrite_are_rejected(self):
        for key,value in [('users',[{'name':'fixture','password':'fixture-only'}]),('filtering',{'rewrites':[{'domain':'host.example.com','answer':'192.0.2.1'}]})]:
            with self.subTest(key=key):
                self.check(lambda t:self.update_yaml(t,'app_config/etc/AdGuardHome/AdGuardHome.yaml',lambda d:d.update({key:value})))

    def test_nodes_and_controller_are_rejected(self):
        rel='app_config/etc/openclash/config/APP_Rule_Auto.yaml'
        for update in [{'proxies':[{'name':'fixture','type':'direct'}]},{'secret':'fixture-only'},{'external-controller':'0.0.0.0:9090'}]:
            with self.subTest(update=update):
                self.check(lambda t:self.update_yaml(t,rel,lambda d:d.update(update)))

    def test_nonempty_provider_is_rejected(self):
        rel='app_config/etc/openclash/proxy_provider/Subscribe.yaml'
        self.check(lambda t:self.update_yaml(t,rel,lambda d:d.update(proxies=[{'name':'fixture'}])))

    def test_vpn_identity_file_is_rejected(self):
        def edit(t):
            p=t/'app_config/etc/tailscale/tailscaled.state'
            p.parent.mkdir(parents=True,exist_ok=True)
            p.write_text('{}')
        self.check(edit)

    def test_monitoring_credential_and_enabled_vpn_are_rejected(self):
        def token(t):
            p=t/'app_config/etc/config/beszel-agent'
            p.write_text(p.read_text().replace("option token ''","option token 'fixture-only'"))
        def enabled(t):
            p=t/'app_config/etc/config/tailscale'
            p.write_text(p.read_text().replace("service_enabled '0'","service_enabled '1'"))
        self.check(token)
        self.check(enabled)

    def test_scheduled_workflow_is_rejected(self):
        p='.github/workflows/build-openwrt.yml'
        def edit(t):
            f=t/p
            f.write_text(f.read_text().replace('  workflow_dispatch:','  workflow_dispatch:\n  schedule:\n    - cron: "0 0 * * *"',1))
        self.check(edit)

    def test_network_override_is_rejected(self):
        def edit(t):
            p=t/'app_config/etc/uci-defaults/zzzz-extra-settings'
            p.write_text(p.read_text()+"\nuci set network.lan.ipaddr='192.0.2.1'\n")
        self.check(edit)

if __name__ == '__main__':
    unittest.main(verbosity=2)
