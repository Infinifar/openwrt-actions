#!/usr/bin/env python3
"""Read-only checks of the public template, not of a personalized deployment."""
from pathlib import Path
import re
import sys
import yaml

ROOT = Path(__file__).resolve().parents[1]

def require(condition, message):
    if not condition:
        raise ValueError(message)

def load(name):
    return yaml.safe_load((ROOT/name).read_text())

def main():
    forbidden = re.compile(rb"(?:glpat-[A-Za-z0-9_-]{12,}|tskey-(?:api|auth)-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9]{25,}|-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----|\$2[aby]\$\d\d\$[./A-Za-z0-9]{45,})")
    checked = 0
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.relative_to(ROOT).parts:
            continue
        rel = path.relative_to(ROOT)
        require(not path.is_symlink(), "Symlink in public payload: "+str(rel))
        require("manual-restore" not in rel.parts and path.suffix not in {".state",".key",".pem",".p12",".pfx"},
                "Forbidden identity/backup file: "+str(rel))
        require(not forbidden.search(path.read_bytes()), "Credential pattern in "+str(rel))
        checked += 1
    a = load("app_config/etc/AdGuardHome/AdGuardHome.yaml")
    require(a["users"] == [], "Public AdGuard users must be empty")
    require(a["filtering"]["rewrites"] == [], "Public AdGuard rewrites must be empty")
    require(a["clients"]["persistent"] == [], "Public AdGuard clients must be empty")
    require(a["http"]["address"].startswith("127.0.0.1:"), "AdGuard management must be loopback-only")
    for path in sorted((ROOT/"app_config/etc/openclash/config").glob("*.yaml")):
        profile = yaml.safe_load(path.read_text())
        require(not profile.get("secret"), "Baked-in controller secret: "+path.name)
        require(profile["external-controller"].startswith("127.0.0.1:"), "Exposed controller: "+path.name)
        require(not profile.get("proxies") and not profile.get("authentication"), "Inline nodes/auth: "+path.name)
        require(all(p.get("type") == "file" for p in profile["proxy-providers"].values()), "Active HTTP subscription")
    require(load("app_config/etc/openclash/proxy_provider/Subscribe.yaml") == {"proxies":[]}, "Provider must be empty")
    for name in ["beszel-agent", "zerotier", "tailscale", "openclash"]:
        text = (ROOT/"app_config/etc/config"/name).read_text()
        require(not re.search(r"(?m)^\s*list\s+(join|advertise_routes)\s+", text), "Active network advertisement/join")
        for line in text.splitlines():
            match = re.match(r"\s*option\s+(password|username|dashboard_password|dashboard_forward_domain|token|public_key|secret|id|fingerprint|hub_url)\s+'([^']*)'", line)
            require(not match or not match[2], "Nonempty account/identity field in "+name)
        flag = {"beszel-agent":"enabled", "zerotier":"enabled", "tailscale":"service_enabled", "openclash":"enable"}[name]
        require(re.search(r"option\s+"+flag+r"\s+'0'",text), "Unconfigured service enabled: "+name)
    tail = (ROOT/"app_config/etc/config/tailscale").read_text()
    require("option advertise_exit_node '0'" in tail and "option enable_relay '0'" in tail, "Pre-enabled exit/relay")
    for path in (ROOT/".github/workflows").glob("*.yml"):
        data = yaml.safe_load(path.read_text())
        events = data.get("on",data.get(True))
        require(isinstance(events,dict) and set(events) == {"workflow_dispatch"}, "Workflow is not manual-only: "+path.name)
    boot = (ROOT/"app_config/etc/uci-defaults/zzzz-extra-settings").read_text()
    approved = [
        "uci -q delete network.wan || true",
        "uci -q delete network.wan6 || true",
        "uci set network.lan.ipaddr='192.168.11.4'",
        "uci set network.lan.gateway='192.168.11.1'",
        "uci -q delete network.lan.ip6assign || true",
        "uci set network.lan6=interface",
        "uci set network.lan6.ifname='@lan'",
        "uci set network.lan6.device='@lan'",
        "uci set network.lan6.proto='dhcpv6'",
        "uci set network.lan6.reqaddress='try'",
        "uci set network.lan6.reqprefix='auto'",
        "uci set network.lan6.peerdns='0'",
        "uci -q del_list firewall.@zone[0].network='lan6' || true",
        "uci add_list firewall.@zone[0].network='lan6'",
        "uci set dhcp.lan.ignore='1'",
        "uci set dhcp.@dnsmasq[0].port='3553'",
        "uci set dhcp.@dnsmasq[0].dns_redirect='0'",
        "uci set dhcp.@dnsmasq[0].cachesize='0'",
        "uci -q del_list dhcp.@dnsmasq[0].server='127.0.0.1#5335' || true",
        "uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5335'",
    ]
    mutations = [line.strip() for line in boot.splitlines()
                 if re.match(r"\s*uci(?:\s+-\S+)*\s+(?:set|add_list|del_list|delete|rename|reorder)\s+(?:network|dhcp|dropbear|firewall)\.",line)]
    require(mutations == approved, "Boot network changes exceed approved side-router defaults")
    print("Public privacy checks passed: "+str(checked)+" files, empty accounts/providers/identities, manual-only workflows")

if __name__ == "__main__":
    try:
        main()
    except (ValueError,KeyError,yaml.YAMLError) as error:
        print("Public validation failed: "+str(error),file=sys.stderr)
        sys.exit(1)
