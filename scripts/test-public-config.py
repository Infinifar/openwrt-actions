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
        for command in [
            "uci set network.lan.ipaddr=\'192.0.2.1\'",
            "uci set network.lan.macaddr=\'02:00:00:00:00:01\'",
            "uci set dhcp.lan.dhcpv6='disabled'",
            "uci set dhcp.@dnsmasq[0].port='53'",
            "uci set network.lan6.proto='static'",
            "uci set dhcp.@dnsmasq[0].server='8.8.8.8'",
            "uci -q delete network.lan",
            "uci set dropbear.main.Port=\'2222\'",
        ]:
            with self.subTest(command=command):
                def edit(t):
                    p=t/'app_config/etc/uci-defaults/zzzz-extra-settings'
                    p.write_text(p.read_text()+"\n"+command+"\n")
                self.check(edit)

    def test_missing_approved_lan_default_is_rejected(self):
        def edit(t):
            p=t/'app_config/etc/uci-defaults/zzzz-extra-settings'
            p.write_text(p.read_text().replace("    uci set network.lan.gateway=\'192.168.11.1\'\n",""))
        self.check(edit)

    def test_approved_boot_block_sets_only_side_router_fields(self):
        source=(ROOT/"app_config/etc/uci-defaults/zzzz-extra-settings").read_text()
        block=source.split("# BEGIN approved public LAN defaults\n",1)[1].split("# END approved public LAN defaults",1)[0]
        mock='uci() { if [ "$1" = "-q" ] && [ "$2" = "get" ]; then case "$3" in firewall.@zone\\[0\\].name) printf lan;; esac; return 0; fi; printf "%s\\n" "$*"; };\n'
        result=subprocess.run(["sh","-s"],input=mock+block,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.splitlines(),["-q delete network.wan","-q delete network.wan6",
            "set network.lan.ipaddr=192.168.11.4","set network.lan.gateway=192.168.11.1",
            "-q delete network.lan.ip6assign","set network.lan6=interface",
            "set network.lan6.device=@lan","set network.lan6.proto=dhcpv6",
            "set network.lan6.reqaddress=try","set network.lan6.reqprefix=auto",
            "set network.lan6.peerdns=0","-q del_list firewall.@zone[0].network=lan6",
            "add_list firewall.@zone[0].network=lan6","commit firewall","commit network",
            "set dhcp.lan.ignore=1","commit dhcp","set dhcp.@dnsmasq[0].port=3553",
            "set dhcp.@dnsmasq[0].dns_redirect=0","set dhcp.@dnsmasq[0].cachesize=0",
            "-q del_list dhcp.@dnsmasq[0].server=127.0.0.1#5335",
            "add_list dhcp.@dnsmasq[0].server=127.0.0.1#5335","commit dhcp"])

    def test_approved_boot_block_skips_missing_lan_and_dhcp(self):
        source=(ROOT/"app_config/etc/uci-defaults/zzzz-extra-settings").read_text()
        block=source.split("# BEGIN approved public LAN defaults\n",1)[1].split("# END approved public LAN defaults",1)[0]
        mock='uci() { if [ "$1" = "-q" ]; then return 1; fi; printf "%s\\n" "$*"; };\n'
        result=subprocess.run(["sh","-s"],input=mock+block,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,"")

    def test_missing_wan_deletions_are_idempotent(self):
        source=(ROOT/"app_config/etc/uci-defaults/zzzz-extra-settings").read_text()
        block=source.split("# BEGIN approved public LAN defaults\n",1)[1].split("# END approved public LAN defaults",1)[0]
        mock='uci() { if [ "$1" = "-q" ] && [ "$2" = "delete" ]; then return 1; fi; printf "%s\\n" "$*"; };\n'
        result=subprocess.run(["sh","-s"],input=mock+block,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("set network.lan.ipaddr=192.168.11.4",result.stdout)
        self.assertIn("set dhcp.lan.ignore=1",result.stdout)

if __name__ == '__main__':
    unittest.main(verbosity=2)
