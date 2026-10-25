#!/usr/bin/env python3
"""Exercise the exact startup hook without touching any real services."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('lan_patch', Path(__file__).with_name('patch-mosdns-lan-hosts.py'))
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)
INIT = 'start_service() {\n\tprocd_open_instance mosdns\n\tprintf started\n}\nstart_service\n'

class InitTest(unittest.TestCase):
    def test_idempotent_and_drift_guard(self):
        result = patch.patched(INIT)
        self.assertEqual(result, patch.patched(result))
        for text in ('changed upstream', INIT + INIT, result.replace(' sync ||', ' broken ||')):
            with self.assertRaises(ValueError):
                patch.patched(text)

    def run_hook(self, conf, fail=''):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            helper = root / 'sync-helper'
            helper.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$CALLS"\n[ "$1" != "$FAIL" ]\n')
            helper.chmod(0o755)
            text = patch.patched(INIT).replace('/usr/share/mosdns/sync-adguard-hosts.rb', str(helper))
            import os
            proc = subprocess.run(['sh', '-c', 'procd_open_instance() { :; };\n' + text],
                                  env=dict(os.environ, CONF=conf, FAIL=fail, CALLS=str(root / 'calls')),
                                  capture_output=True, text=True)
            calls = (root / 'calls').read_text().splitlines() if (root / 'calls').exists() else []
            return proc, calls

    def test_custom_path_prepares_before_process(self):
        proc, calls = self.run_hook('/etc/mosdns/config_custom.yaml')
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(calls, ['sync', 'configure'])
        self.assertEqual(proc.stdout, 'started')

    def test_failure_does_not_start_process(self):
        for fail in ('sync', 'configure'):
            proc, _ = self.run_hook('/etc/mosdns/config_custom.yaml', fail)
            self.assertNotEqual(proc.returncode, 0)
            self.assertEqual(proc.stdout, '')

    def test_native_generated_config_not_modified(self):
        proc, calls = self.run_hook('/var/etc/mosdns.json')
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(calls, [])

if __name__ == '__main__':
    unittest.main()
