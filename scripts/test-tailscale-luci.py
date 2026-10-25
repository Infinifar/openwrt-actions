#!/usr/bin/env python3
"""Contract regressions and isolated fresh-source worker checks; no live services."""
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

class SourceTests(unittest.TestCase):
    def test_exact_anchor_rejects_drift_and_duplicates(self):
        self.assertEqual(patcher.once('abc', 'b', 'x'), 'axc')
        for source in ('ac', 'abbc'):
            with self.assertRaises(ValueError):
                patcher.once(source, 'b', 'x')

    def test_no_silent_reapplication(self):
        with self.assertRaises(ValueError):
            patcher.patch_sources(patcher.MARKER, '', '', '{}', '')

    def test_old_upstream_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'contract missing'):
            patcher.patch_sources('', '', '', '{}', '')

    def test_required_contract_is_not_optional(self):
        patcher.require('status worker', ['status', 'worker'])
        with self.assertRaises(ValueError):
            patcher.require('status', ['worker'])

    def test_build_refreshes_before_compatibility(self):
        hook = (REPO / 'user/common/custom.sh').read_text()
        self.assertLess(hook.index('package/tailscale main'), hook.index('scripts/patch-tailscale-luci.py'))
        self.assertIn('luci-app-tailscale-community master', hook)
        script = (REPO / 'scripts/patch-tailscale-luci.py').read_text()
        self.assertNotIn('shutil.copyfile', script)

def verify_upstream(package):
    originals = tuple((package / p).read_text() for p in
                      (patcher.RPC, patcher.VIEW, patcher.INIT, patcher.ACL, patcher.WORKER))
    rpc, view, init, acl, worker = patcher.patch_sources(*originals)
    assert 'get_firewall_status' in json.loads(acl)['luci-app-tailscale-community']['read']['ubus']['tailscale']
    assert 'get_apply_status' not in rpc and 'tailscaleActions.configureFirewall' not in view
    assert "&& /etc/init.d/tailscale-settings reload" in rpc
    assert 'timeout 30 "$ts_bin" "$@"' in init
    assert '--netfilter-mode=on' in init
    assert 'return pollFirewallJob(res.run_id, 180);' in view
    assert acl == originals[3]
    # Execute only the worker with every external service path replaced by a
    # recording stub and all status/lock files placed in a disposable sandbox.
    with tempfile.TemporaryDirectory(prefix='tailscale-upstream-test-') as tmp:
        root = Path(tmp)
        calls = root / 'calls'
        for name in ('network', 'firewall', 'tailscale-settings'):
            stub = root / name
            stub.write_text('#!/bin/sh\nprintf "%s\\n" "' + name + ' $*" >> "$CALLS"\n[ "${FAIL:-}" != "' + name + '" ]\n')
            stub.chmod(0o755)
            worker = worker.replace('/etc/init.d/' + name, '"' + str(stub) + '"')
        worker = worker.replace('STATE_FILE=/var/run/tailscale-fwsetup.status', 'STATE_FILE="' + str(root / 'status') + '"')
        worker = worker.replace('LOCK_FILE=/var/run/tailscale-fwsetup.lock', 'LOCK_FILE="' + str(root / 'lock') + '"')
        worker = worker.replace('sleep 2\n', ': # no delay in isolated test\n')
        candidate = root / 'worker'
        candidate.write_text(worker)
        subprocess.run(['sh', '-n', str(candidate)], check=True)
        for failure, expected in [('', ['network reload', 'firewall reload', 'tailscale-settings reload']),
                                  ('network', ['network reload']),
                                  ('firewall', ['network reload', 'firewall reload']),
                                  ('tailscale-settings', ['network reload', 'firewall reload', 'tailscale-settings reload'])]:
            calls.unlink(missing_ok=True)
            result = subprocess.run(['sh', str(candidate), '1234'],
                env=dict(os.environ, CALLS=str(calls), FAIL=failure), capture_output=True, text=True, timeout=8)
            assert (result.returncode == 0) == (failure == ''), result.stderr
            assert calls.read_text().splitlines() == expected
            status = (root / 'status').read_text().splitlines()
            assert status[0] == ('failed' if failure else 'done'), status
            assert status[-1] == '1234', status
        (root / 'lock.d').mkdir()
        import time
        (root / 'lock.d/ts').write_text(str(int(time.time())))
        calls.unlink()
        result = subprocess.run(['sh', str(candidate), '5678'],
            env=dict(os.environ, CALLS=str(calls)), capture_output=True, text=True, timeout=8)
        assert result.returncode == 0
        assert not calls.exists()
        assert (root / 'status').read_text().splitlines()[0] == 'busy'
    print('Fresh upstream #81 contract and isolated success/failure/busy worker paths: passed')

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--upstream':
        verify_upstream(Path(sys.argv[2]))
    else:
        unittest.main()
