#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parent.parent


class NetworkTests(unittest.TestCase):
    def run_shell(self, values, fail=False):
        with tempfile.TemporaryDirectory() as directory:
            curl=Path(directory)/'curl'
            curl.write_text('#!/bin/sh\nexit '+('1' if fail else '0')+'\n')
            curl.chmod(0o755)
            env={key:value for key,value in os.environ.items() if 'proxy' not in key.lower() and not key.startswith('CI_')}
            env.update(values,PATH=directory+os.pathsep+os.environ['PATH'])
            script="""set -e; source scripts/ci-network.sh; python3 -c 'import os,json; print(json.dumps({k:os.environ.get(k) for k in ["HTTP_PROXY","HTTPS_PROXY","http_proxy","https_proxy","NO_PROXY","no_proxy"]}))'"""
            return subprocess.run(['bash','-c',script],cwd=ROOT,env=env,text=True,capture_output=True)

    def test_optional_proxy_does_not_invent_endpoint(self):
        result=self.run_shell({})
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIsNone(json.loads(result.stdout.splitlines()[-1])['HTTP_PROXY'])

    def test_proxy_and_private_bypass(self):
        proxy='http://user:private-example@proxy.invalid:20171'
        result=self.run_shell({'OPENWRT_HTTP_PROXY':proxy,'CI_SERVER_HOST':'gitlab','CI_SERVER_URL':'http://gitlab','CI_PROJECT_URL':'https://gitlab.example/private/openwrt','NO_PROXY':'custom.internal'})
        self.assertEqual(result.returncode,0,result.stderr)
        data=json.loads(result.stdout.splitlines()[-1])
        for key in ['HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy']:
            self.assertEqual(data[key],proxy)
        for host in ['localhost','127.0.0.1','::1','gitlab','gitlab.example','custom.internal']:
            self.assertIn(host,data['NO_PROXY'].split(','))
        self.assertEqual(data['NO_PROXY'],data['no_proxy'])
        self.assertNotIn('private-example','\n'.join(result.stdout.splitlines()[:-1])+result.stderr)

    def test_bad_proxy_fails_closed(self):
        result=self.run_shell({'OPENWRT_HTTP_PROXY':'socks5://invalid'})
        self.assertNotEqual(result.returncode,0)

    def test_unhealthy_proxy_is_not_silently_ignored(self):
        result=self.run_shell({'OPENWRT_HTTP_PROXY':'http://proxy.invalid:20171'},fail=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('health check',result.stderr)


if __name__=='__main__':
    unittest.main()
