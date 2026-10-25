#!/usr/bin/env python3
"""Keep upstream #80/#81 fixes; apply only remaining firmware compatibility guards.

Always consume fresh master. Missing/changed upstream contracts fail the build;
never restore the legacy local UI/worker or fall back to a cached package.
"""
import argparse
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
RPC = 'root/usr/share/rpcd/ucode/tailscale.uc'
VIEW = 'htdocs/luci-static/resources/view/tailscale.js'
INIT = 'root/etc/init.d/tailscale-settings'
ACL = 'root/usr/share/rpcd/acl.d/luci-app-tailscale-community.json'
WORKER = 'root/usr/libexec/tailscale-setup-firewall'
MARKER = '// firmware compatibility: upstream #81 v2'

def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Tailscale upstream layout changed; reviewed anchor is missing or ambiguous: ' + old[:90])
    return text.replace(old, new, 1)

def require(text, tokens):
    for token in tokens:
        if token not in text:
            raise ValueError('Fresh Tailscale upstream fix contract missing: ' + token)

def patch_sources(rpc, view, init, acl, worker):
    if MARKER in rpc:
        raise ValueError('Tailscale fixes must be applied only to freshly fetched upstream sources')
    require(rpc, ['methods.get_firewall_status =', 'methods.set_service_enabled =',
                  '/usr/libexec/tailscale-setup-firewall', 'run_id: run_id'])
    require(view, ['function unwrapRpc(', 'function pollFirewallJob(',
                   'callGetFirewallStatus', 'callSetServiceEnabled', 'countPending(changes)'])
    require(init, ['tailscale_running()', 'sync_service_enabled()', 'daemon_signature()',
                   'procd_add_reload_trigger "tailscale"'])
    require(worker, ['write_state()', 'lock_age()', 'mkdir "$LOCK_DIR"'])
    permissions = json.loads(acl)['luci-app-tailscale-community']
    if 'get_firewall_status' not in permissions['read']['ubus']['tailscale']:
        raise ValueError('Fresh upstream firewall status ACL is missing')
    # Upstream owns the status RPC, UI, lock and service lifecycle. Never install
    # the former local tailscale.actions/get_apply_status/reload implementation.
    rpc = once(rpc, "'use strict';", "'use strict';\n\n" + MARKER)
    # Upstream's new status-file handoff calls fs.rename; import it explicitly.
    rpc = once(rpc, "import { access, popen, readfile, writefile, unlink } from 'fs';",
               "import { access, popen, readfile, writefile, unlink, rename } from 'fs';")
    for service in ('network', 'firewall'):
        rpc = once(rpc, f"\t\t\t\tuci.commit('{service}');",
                   f"\t\t\t\tif (!uci.commit('{service}')) return {{ error: 'Could not commit {service} configuration' }};")
    rpc = once(rpc, "let login_cmd = 'tailscale login '+join(' ', loginargs);",
               "let login_cmd = 'tailscale login '+join(' ', loginargs) + ' && /etc/init.d/tailscale-settings reload';")
    init = once(init, '\t"$ts_bin" "$@"', '\ttimeout 30 "$ts_bin" "$@"')
    init = once(init, '\t\tset -- "$@" --netfilter-mode=off\n\tfi',
                '\t\tset -- "$@" --netfilter-mode=off\n\telse\n\t\tset -- "$@" --netfilter-mode=on\n\tfi')
    # Bound the upstream worker and delay its first reload until the RPC returns.
    worker = once(worker, 'write_state running network "Reloading network"',
                  'sleep 2\nwrite_state running network "Reloading network"')
    for service in ('network', 'firewall'):
        worker = once(worker, f'if ! /etc/init.d/{service} reload >/dev/null 2>&1; then',
                      f'if ! timeout 45 /etc/init.d/{service} reload >/dev/null 2>&1; then')
    worker = once(worker, 'write_state done done "Firewall configuration applied"',
                  '''write_state running settings "Applying Tailscale settings"
if ! timeout 45 /etc/init.d/tailscale-settings reload >/dev/null 2>&1; then
    write_state failed settings "Tailscale settings reload failed"
    trap - EXIT HUP INT TERM
    rm -rf "$LOCK_DIR"
    exit 1
fi
write_state done done "Firewall configuration applied"''')
    view = once(view, 'return pollFirewallJob(res.run_id);',
                'return pollFirewallJob(res.run_id, 180);')
    return rpc, view, init, acl, worker

def prepare(tree):
    package = tree / 'package/luci-app-tailscale-community'
    paths = [package / name for name in (RPC, VIEW, INIT, ACL, WORKER)]
    updated = patch_sources(*(p.read_text() for p in paths))
    # All contracts/anchors are checked before any source file is changed.
    for path, content in zip(paths, updated):
        path.write_text(content)
    (package / WORKER).chmod(0o755)
    print('Info: upstream Tailscale #80/#81 UI, status and lifecycle retained; bounded firmware guards installed')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tree', type=Path)
    prepare(parser.parse_args().tree.resolve())
