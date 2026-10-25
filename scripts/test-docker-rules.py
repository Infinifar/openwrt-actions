#!/usr/bin/env python3
"""Offline downloader regression tests; never contact the router or GitHub."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().with_name('update-docker-rules.sh')


class DockerRulesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='docker-rules-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.destination = self.root / 'rules'
        self.destination.mkdir()
        self.output = self.destination / 'DockerHubExtra.mrs'
        self.output.write_bytes(b'previous-copy')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        curl = self.bin / 'curl'
        curl.write_text('#!/bin/bash\nset -eu\n'
                        '[[ " $* " == *" --fail "* ]]\n'
                        '[[ " $* " == *" --max-time "* ]]\n'
                        '[[ " $* " == *" https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/docker.mrs "* ]]\n'
                        '[ "${DOCKER_TEST_FAIL:-0}" = 0 ] || exit 22\n'
                        'cp "$DOCKER_TEST_INPUT" "${@: -1}"\n')
        curl.chmod(0o755)
        self.input = self.root / 'input'
        self.env = {**os.environ, 'PATH': f'{self.bin}:{os.environ["PATH"]}',
                    'DOCKER_TEST_INPUT': str(self.input), 'DOCKER_TEST_FAIL': '0'}

    def compress(self, data):
        result = subprocess.run(['zstd', '-q', '-c'], input=data, capture_output=True, check=True)
        self.input.write_bytes(result.stdout)

    def run_script(self, success=False):
        result = subprocess.run(['bash', str(SCRIPT), str(self.destination)], env=self.env, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stderr.decode(errors='replace'))
        self.assertFalse(list(self.destination.glob('.docker-rules.*')))
        if not success:
            self.assertEqual(self.output.read_bytes(), b'previous-copy')

    def test_valid_frame_installed_atomically(self):
        # Structural fixture, not a real domain trie. Actual upstream data is
        # separately loaded by Mihomo during implementation verification.
        self.compress(b'MRS\x01' + b'\x00' * 20)
        self.run_script(success=True)
        self.assertEqual(self.output.read_bytes(), self.input.read_bytes())
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o644)

    def test_http_error_keeps_previous_copy(self):
        self.env['DOCKER_TEST_FAIL'] = '1'
        self.run_script()

    def test_html_error_is_not_installed(self):
        self.input.write_bytes(b'<html>upstream error</html>')
        self.run_script()

    def test_compressed_html_is_not_installed(self):
        self.compress(b'<html>not a ruleset</html>')
        self.run_script()

    def test_truncated_frame_is_not_installed(self):
        self.compress(b'MRS\x01' + b'\x00' * 20)
        self.input.write_bytes(self.input.read_bytes()[:-2])
        self.run_script()

    def test_truncated_mrs_is_not_installed(self):
        self.compress(b'MRS\x01')
        self.run_script()


if __name__ == '__main__':
    if not shutil.which('zstd'):
        raise SystemExit('zstd is required for Docker rules tests')
    unittest.main()
