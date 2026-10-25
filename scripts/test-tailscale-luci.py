#!/usr/bin/env python3
"""Offline regression checks, plus --upstream against a disposable fresh source tree."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('tailscale_patch', REPO / 'scripts/patch-tailscale-luci.py')
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)

class ReloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='tailscale test ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.runtime = self.root / 'runtime'
        self.log = self.root / 'calls'
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'], CALLS=str(self.log))
        script = (REPO / 'user/common/tailscale/reload.sh').read_text()
        script = script.replace('runtime=/var/run/tailscale-luci-apply', 'runtime="'+str(self.runtime)+'"')
        for name in ('network', 'firewall', 'tailscale-settings'):
            script = script.replace('/etc/init.d/' + name, '"' + str(self.bin / name) + '"')
        self.worker = self.root / 'reload'
        self.worker.write_text(script)
        self.worker.chmod(0o755)
        self.mock('timeout', '#!/bin/sh\nshift\nexec "$@"\n')
        self.mock('logger', '#!/bin/sh\nexit 0\n')
        self.mock('sleep', '#!/bin/sh\nexit 0\n')
        for name in ('network', 'firewall', 'tailscale-settings'):
            self.mock(name, '#!/bin/sh\nprintf "%s\\n" "'+name+' $*" >> "$CALLS"\n[ "${FAIL:-}" != "'+name+'" ]\n')

    def mock(self, name, content):
        p = self.bin / name
        p.write_text(content)
        p.chmod(0o755)

    def run_worker(self, mode='run', network='1', firewall='1', fail=''):
        self.runtime.mkdir(exist_ok=True)
        return subprocess.run([str(self.worker), mode, network, firewall],
                              env=dict(self.env, FAIL=fail), capture_output=True, text=True, timeout=5)

    def test_order_and_success(self):
        self.assertEqual(self.run_worker().returncode, 0)
        self.assertEqual(self.log.read_text().splitlines(), ['network reload', 'firewall reload', 'tailscale-settings reload'])
        self.assertEqual((self.runtime / 'status').read_text().strip(), 'success')

    def test_already_configured_still_applies_settings(self):
        self.assertEqual(self.run_worker(network='0', firewall='0').returncode, 0)
        self.assertEqual(self.log.read_text().strip(), 'tailscale-settings reload')

    def test_each_failure_is_reported_and_stops_later_steps(self):
        for name, status, count in [('network','network_failed',1),('firewall','firewall_failed',2),('tailscale-settings','settings_failed',3)]:
            with self.subTest(name=name):
                self.log.unlink(missing_ok=True)
                self.assertNotEqual(self.run_worker(fail=name).returncode, 0)
                self.assertEqual((self.runtime / 'status').read_text().strip(), status)
                self.assertEqual(len(self.log.read_text().splitlines()), count)

    def test_bad_arguments_are_rejected(self):
        self.assertEqual(self.run_worker(mode='queue', network='1;false').returncode, 64)
        self.assertFalse(self.log.exists())

    def test_queue_does_not_wait_for_child_and_serializes(self):
        import fcntl
        self.runtime.mkdir()
        lock = open(self.runtime / 'lock', 'w')
        self.addCleanup(lock.close)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.assertEqual(self.run_worker(mode='queue').returncode, 75)
        self.assertFalse((self.runtime / 'status').exists())

    def test_queue_returns_before_work_and_holds_lock_until_done(self):
        import time
        self.mock('sleep', '#!/bin/sh\nexec /bin/sleep 0.25\n')
        started = time.monotonic()
        result = self.run_worker(mode='queue')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(time.monotonic() - started, 0.20)
        self.assertEqual((self.runtime / 'status').read_text().strip(), 'queued')
        self.assertEqual(self.run_worker(mode='queue').returncode, 75)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if (self.runtime / 'status').read_text().strip() == 'success': break
            time.sleep(0.01)
        self.assertEqual((self.runtime / 'status').read_text().strip(), 'success')
        self.assertEqual(self.log.read_text().splitlines(), ['network reload', 'firewall reload', 'tailscale-settings reload'])
        # Opening the same lock after success must be possible, not a stale lock.
        import fcntl
        with open(self.runtime / 'lock', 'w') as lock:
            deadline = time.monotonic() + 1
            while True:
                try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); break
                except BlockingIOError:
                    if time.monotonic() > deadline: raise
                    time.sleep(0.01)


class SourceTests(unittest.TestCase):
    def test_exact_anchor_rejects_drift_and_duplicates(self):
        self.assertEqual(patcher.once('abc', 'b', 'x'), 'axc')
        for source in ('ac', 'abbc'):
            with self.assertRaises(ValueError): patcher.once(source, 'b', 'x')

    def test_no_silent_reapplication(self):
        with self.assertRaises(ValueError): patcher.patch_sources(patcher.MARKER, '', '', '{}')

    def test_build_installs_fixes_after_refresh(self):
        hook = (REPO / 'user/common/custom.sh').read_text()
        self.assertLess(hook.index('package/tailscale main'), hook.index('scripts/patch-tailscale-luci.py'))
        self.assertIn('sleep 2;', (REPO / 'user/common/tailscale/reload.sh').read_text())
        self.assertIn('flock -n 9', (REPO / 'user/common/tailscale/reload.sh').read_text())

def verify_upstream(package):
    """Exercise real source functions without running services on any device."""
    rpc, view, init, acl = patcher.patch_sources(*( (package / p).read_text() for p in (patcher.RPC,patcher.VIEW,patcher.INIT,patcher.ACL)))
    assert "exec('/etc/init.d/network reload')" not in rpc
    assert "exec('/etc/init.d/firewall reload')" not in rpc
    assert 'get_apply_status' in json.loads(acl)['luci-app-tailscale-community']['read']['ubus']['tailscale']
    assert 'tailscaleActions.configureFirewall(map)' in view
    assert 'tailscale login ' in rpc and '&& /etc/init.d/tailscale-settings reload' in rpc
    # Isolate the real handle_service_state body with mocked functions. Never
    # execute the full init file or source the host's OpenWrt init machinery.
    body = init.split('handle_service_state() {',1)[1].split('\nstart_service()',1)[0]
    with tempfile.TemporaryDirectory(prefix='tailscale init test ') as tmp:
        tmp = Path(tmp)
        calls = tmp / 'calls'
        initmock = tmp / 'tailscale'
        initmock.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\n')
        initmock.chmod(0o755)
        body = body.replace('/etc/init.d/tailscale', '"'+str(initmock)+'"')
        preamble = '''config_load() { :; }
config_get() { eval "$1=\\\"$ENABLED\\\""; }
logger() { :; }
pidof() { [ "$RUNNING" = 1 ]; }
killall() { :; }
apply_settings() { printf '%s\\n' apply >> "$CALLS"; }
handle_service_state() {'''
        for enabled, running, expected in [('1','1',['enable','apply']), ('1','0',['enable','start','apply']), ('0','1',['stop','disable'])]:
            calls.unlink(missing_ok=True)
            result = subprocess.run(['sh','-c',preamble+body+'\nhandle_service_state\n'],
                env=dict(os.environ,CALLS=str(calls),ENABLED=enabled,RUNNING=running),capture_output=True,text=True)
            assert result.returncode == 0, result.stderr
            assert calls.read_text().splitlines() == expected, calls.read_text()
    print('Fresh-upstream anchors, RPC/ACL wiring, running/cold/disabled service paths: passed')

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--upstream':
        verify_upstream(Path(sys.argv[2]))
    else:
        unittest.main()
