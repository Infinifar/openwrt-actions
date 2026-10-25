#!/usr/bin/env python3
"""Apply reviewed compatibility fixes to the freshly fetched community LuCI UI.

Exact anchors fail closed on upstream changes; never silently use an old package.
No Tailscale identity, live router, firewall backend or relay policy is changed.
"""
import argparse
import json
from pathlib import Path
import shutil

REPO = Path(__file__).resolve().parents[1]
RPC = 'root/usr/share/rpcd/ucode/tailscale.uc'
VIEW = 'htdocs/luci-static/resources/view/tailscale.js'
INIT = 'root/etc/init.d/tailscale-settings'
ACL = 'root/usr/share/rpcd/acl.d/luci-app-tailscale-community.json'
MARKER = '// lede-personal: detached firewall apply v1'

def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Tailscale upstream layout changed; reviewed anchor is missing or ambiguous: ' + old[:90])
    return text.replace(old, new, 1)

def patch_sources(rpc, view, init, acl):
    if MARKER in rpc:
        raise ValueError('Tailscale fixes must be applied only to freshly fetched upstream sources')
    for service in ('network', 'firewall'):
        rpc = once(rpc, f"\n\t\t\t\texec('/etc/init.d/{service} reload');", '')
        rpc = once(rpc, f"\t\t\t\tuci.commit('{service}');",
                   f"\t\t\t\tif (!uci.commit('{service}')) return {{ error: 'Could not commit {service} configuration' }};")
    anchor = "\n\t\t\treturn {\n\t\t\t\tsuccess: true,\n\t\t\t\tchanged_network: changed_network,"
    rpc = once(rpc, anchor, """
            // lede-personal: detached firewall apply v1
            let queued = exec('/usr/libexec/tailscale-community-reload queue '
                + (changed_network ? '1' : '0') + ' ' + (changed_firewall ? '1' : '0'));
            if (queued.code != 0) return { error: 'Could not queue reload; an apply may already be running' };
            return {
                queued: true,
\t\t\t\tsuccess: true,
\t\t\t\tchanged_network: changed_network,"""
    )
    rpc = once(rpc, 'methods.get_logs = {', """methods.get_apply_status = {
    call: function() {
        let status = trim(readfile('/var/run/tailscale-luci-apply/status') || 'unknown');
        return { status: status };
    }
};

methods.get_logs = {"""
    )
    rpc = once(rpc, "let login_cmd = 'tailscale login '+join(' ', loginargs);",
               "let login_cmd = 'tailscale login '+join(' ', loginargs) + ' && /etc/init.d/tailscale-settings reload';")
    view = once(view, "'require tools.widgets as widgets';", "'require tools.widgets as widgets';\n'require tailscale.actions as tailscaleActions';")
    start = view.index('\t\tfwBtn.onclick = function() {')
    end = view.index("\n\t\tconst helpTitle =", start)
    old = view[start:end]
    if old.count('callSetupFirewall()') != 1:
        raise ValueError('Unexpected firewall button implementation')
    view = once(view, old, '\t\tfwBtn.onclick = function() {\n\t\t\treturn tailscaleActions.configureFirewall(map);\n\t\t};\n')
    init = once(init, '\t\t/etc/init.d/tailscale start 2>/dev/null',
                '\t\t# start_service runs tailscaled --cleanup: do not call it on a running daemon.\n'
                '\t\tif ! pidof tailscaled >/dev/null 2>&1; then\n'
                '\t\t\t/etc/init.d/tailscale start 2>/dev/null || return $?\n'
                '\t\tfi')
    init = once(init, '\t"$ts_bin" "$@"', '\ttimeout 30 "$ts_bin" "$@"')
    # Re-enabling the UI setting must undo a previously selected netfilter=off.
    init = once(init, '\t\tset -- "$@" --netfilter-mode=off\n\tfi',
                '\t\tset -- "$@" --netfilter-mode=off\n\telse\n\t\tset -- "$@" --netfilter-mode=on\n\tfi')
    permissions = json.loads(acl)
    read_methods = permissions['luci-app-tailscale-community']['read']['ubus']['tailscale']
    if 'get_apply_status' in read_methods:
        raise ValueError('Unexpected existing apply status method')
    read_methods.append('get_apply_status')
    return rpc, view, init, json.dumps(permissions, indent=2) + '\n'

def prepare(tree):
    package = tree / 'package/luci-app-tailscale-community'
    paths = [package / name for name in (RPC, VIEW, INIT, ACL)]
    # Validate every anchor before touching any file.
    updated = patch_sources(*(p.read_text() for p in paths))
    for path, content in zip(paths, updated):
        path.write_text(content)
    assets = {
        'reload.sh': 'root/usr/libexec/tailscale-community-reload',
        'actions.js': 'htdocs/luci-static/resources/tailscale/actions.js',
    }
    for source, destination in assets.items():
        target = package / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / 'user/common/tailscale' / source, target)
        target.chmod(0o755 if source.endswith('.sh') else 0o644)
    print('Info: Tailscale LuCI detached reload, login reconciliation and running-daemon guard installed')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tree', type=Path)
    args = parser.parse_args()
    prepare(args.tree.resolve())
