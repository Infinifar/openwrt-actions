#!/usr/bin/env python3
"""Offline tests of actual first-boot hooks with a private filesystem and fake UCI."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
FILES = REPO / "user/common/files"
YAML = """http_proxy: ""
users:
  - name: fixture-only
    password: fixture-hash
dns:
  upstream_dns:
    - 127.0.0.1:7874
querylog:
  dir_path: /var/lib/adguardhome/data
  file_enabled: false
statistics:
  dir_path: /var/lib/adguardhome/data
  interval: 168h
filtering:
  filters_update_interval: 0
  rewrites: []
filters:
  - id: 1234
    url: https://example.invalid/list
"""
UCI = {
    "adguardhome.config": "adguardhome",
    "adguardhome.config.work_dir": "/var/lib/adguardhome",
    "adguardhome.config.jail_mount_rw": ["/var/lib/adguardhome", "/keep-me"],
    "AdGuardHome.AdGuardHome": "AdGuardHome",
    "AdGuardHome.AdGuardHome.workdir": "/var/lib/adguardhome",
    "tailscale.settings": "settings",
    "tailscale.settings.accept_routes": "1",
    "tailscale.settings.fw_mode": "iptables",
    "tailscale.settings.advertise_exit_node": "1",
    "tailscale.settings.advertise_routes": ["192.0.2.0/24", "192.0.2.0/24"],
    "tailscale.settings.dns_mode": "disabled",
}
MOCK_UCI = r"""#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ["MOCK_UCI"])
d=json.loads(p.read_text())
a=[v for v in sys.argv[1:] if v!="-q"]
cmd=a[0]
if cmd=="get":
 if a[1] not in d: sys.exit(1)
 v=d[a[1]]
 print(" ".join(v) if isinstance(v,list) else v)
elif cmd in ("set","add_list","del_list"):
 key,val=a[1].split("=",1)
 if cmd=="set": d[key]=val
 elif cmd=="add_list": d.setdefault(key,[]).append(val)
 else:
  if val not in d.get(key,[]): sys.exit(1)
  d[key].remove(val)
 p.write_text(json.dumps(d))
elif cmd!="commit": sys.exit(2)
"""


class PersistenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lede policy ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.etc = self.root / "etc"
        self.config = self.etc / "AdGuardHome"
        self.config.mkdir(parents=True)
        (self.etc / "config").mkdir()
        self.yaml = self.config / "AdGuardHome.yaml"
        self.yaml.write_text(YAML)
        for name in ("adguardhome", "AdGuardHome", "tailscale"):
            (self.etc / "config" / name).write_text("fixture original " + name)
        self.uci = self.root / "uci.json"
        self.uci.write_text(json.dumps(UCI))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        MOCK_UCI=str(self.uci), MOCK_LOG=str(self.root / "calls"))
        self.executable("uci", MOCK_UCI)
        self.executable("id", "#!/bin/sh\nexit 1\n")
        self.executable("pidof", '#!/bin/sh\n[ "$1" = "$MOCK_RUNNING" ]\n')
        self.executable("logger", "#!/bin/sh\nexit 0\n")
        self.executable("tailscale", '#!/bin/sh\nprintf "%s\\n" "$*" >> "$MOCK_LOG"\nexit 0\n')
        self.executable("adguardhome-storage", '#!/bin/sh\nprintf "storage %s\\n" "$*" >> "$MOCK_LOG"\n')
        self.executable("tailscale-settings", '#!/bin/sh\nprintf "settings %s\\n" "$*" >> "$MOCK_LOG"\n')
        self.hooks = {}
        for name in ("zzzz-adguardhome-persist-v2", "zzzz-tailscale-lan-policy-v1"):
            text = (FILES / "etc/uci-defaults" / name).read_text()
            text = text.replace("config_dir=/etc/AdGuardHome", f'config_dir="{self.config}"')
            text = text.replace("etc_dir=/etc", f'etc_dir="{self.etc}"')
            text = text.replace("config_file=/etc/config/tailscale", f'config_file="{self.etc}/config/tailscale"')
            text = text.replace("awk_script=/usr/share/adguardhome/persist-settings.awk",
                                f'awk_script="{FILES}/usr/share/adguardhome/persist-settings.awk"')
            for init in ("adguardhome-storage", "tailscale-settings"):
                text = text.replace("/etc/init.d/" + init, '"' + str(self.bin / init) + '"')
            hook = self.root / name
            hook.write_text(text)
            self.hooks[name] = hook

    def executable(self, name, text):
        p = self.bin / name
        p.write_text(text)
        p.chmod(0o755)

    def run_hook(self, name, succeeds=True, running=""):
        env = dict(self.env, MOCK_RUNNING=running)
        result = subprocess.run(["sh", str(self.hooks[name])], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, succeeds, result.stderr)

    def test_adguard_restored_config_and_idempotency(self):
        self.run_hook("zzzz-adguardhome-persist-v2")
        text = self.yaml.read_text()
        self.assertIn("http_proxy: http://127.0.0.1:7890", text)
        self.assertEqual(text.count("dir_path: /etc/AdGuardHome/work/data"), 2)
        self.assertIn("filters_update_interval: 24", text)
        owned = ("http_proxy:", "  dir_path:", "  filters_update_interval:")
        strip = lambda s: "\n".join(l for l in s.splitlines() if not l.startswith(owned))
        self.assertEqual(strip(text), strip(YAML))
        d = json.loads(self.uci.read_text())
        self.assertEqual(d["adguardhome.config.work_dir"], "/etc/AdGuardHome/work")
        self.assertEqual(d["AdGuardHome.AdGuardHome.workdir"], "/etc/AdGuardHome/work")
        self.assertEqual(d["adguardhome.config.jail_mount_rw"], ["/keep-me", "/etc/AdGuardHome/work"])
        backup = self.config / ".before-persistence-v2" / "AdGuardHome.yaml"
        self.assertEqual(backup.read_text(), YAML)
        self.run_hook("zzzz-adguardhome-persist-v2")
        self.assertEqual(text, self.yaml.read_text())
        self.assertEqual(backup.read_text(), YAML)
        self.assertEqual((self.etc / "sysupgrade.conf").read_text().count("/etc/AdGuardHome/"), 1)
        self.assertFalse(list(self.config.glob(".persistence.*")))

    def test_reject_unexpected_yaml_without_changing_original_or_uci(self):
        for content in (YAML.replace("http_proxy:", "unexpected_proxy:"),
                        YAML + "http_proxy: duplicate\n"):
            self.yaml.write_text(content)
            self.run_hook("zzzz-adguardhome-persist-v2", succeeds=False)
            self.assertEqual(self.yaml.read_text(), content)
            self.assertEqual(json.loads(self.uci.read_text()), UCI)
            self.assertFalse(list(self.config.glob(".persistence.*")))

    def test_live_adguard_refused(self):
        self.run_hook("zzzz-adguardhome-persist-v2", succeeds=False, running="AdGuardHome")
        self.assertEqual(self.yaml.read_text(), YAML)
        self.assertEqual(json.loads(self.uci.read_text()), UCI)

    def test_tailscale_restored_uci_preserves_other_preferences(self):
        self.run_hook("zzzz-tailscale-lan-policy-v1")
        expected = dict(UCI)
        expected["tailscale.settings.accept_routes"] = "0"
        self.assertEqual(json.loads(self.uci.read_text()), expected)
        calls = (self.root / "calls").read_text()
        self.assertIn("settings enable", calls)
        self.assertNotIn("--advertise", calls)
        self.assertNotIn("set --", calls)
        self.run_hook("zzzz-tailscale-lan-policy-v1", running="tailscaled")
        self.assertIn("set --accept-routes=false", (self.root / "calls").read_text())
        self.assertEqual(json.loads(self.uci.read_text()), expected)
        self.assertEqual((self.etc / "config/tailscale.before-lan-policy-v1").read_text(),
                         "fixture original tailscale")

    def test_keep_list_covers_data_and_identity(self):
        keep = (FILES / "lib/upgrade/keep.d/lede-personal-services").read_text().splitlines()
        for value in ("/etc/AdGuardHome/", "/etc/config/adguardhome",
                      "/etc/config/AdGuardHome", "/etc/config/tailscale", "/etc/tailscale/"):
            self.assertIn(value, keep)


if __name__ == "__main__":
    unittest.main(verbosity=2)
