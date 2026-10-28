# Public OpenWrt template rules

- Select the GitHub host Ruby from .ruby-version with the reviewed, commit-pinned official setup-ruby action after apt cleanup. Verify RUBY_VERSION before the configuration gate; do not confuse this host toolchain with the firmware's Ruby package.
- Keep owned Ruby YAML loaders on safe_load_file with explicit aliases support, never unsafe_load or version-dependent load_file keywords. Run scripts/check-ruby-yaml.rb and AI/US-AI/Docker semantics before publishing; both workflows validate after dependency installation but before swap/disk allocation.
- Refresh Tailscale LuCI master for every build, retaining upstream #80/#81 UI/status/worker/lifecycle. Apply only exact-anchor residual firmware guards; reject missing fix contracts and never reinstall the old local UI/worker. ci/tailscale-luci-upstream.json records review provenance, not a frozen source pin. Keep this public template free of identities/subscriptions/credentials.

- This is the sanitized public repository. Never copy private GitLab history, identities, subscriptions, accounts, production network inventories or raw backups into it.
- Keep public templates empty by default: no Tailscale state/manual restore, proxy nodes, ZeroTier network IDs or Beszel credentials. Keep unconfigured services disabled and management APIs loopback-only.
- Run scripts/validate-public-config.py and the functional regression suite before publishing. Inspect staged files, not only ignore patterns.
- Fetch MosDNS only from the pinned public GitHub submodule. Preserve its GPL license, credits and original copyright headers.
- Preserve attribution to alecthw/openwrt-actions and all directly integrated projects in CREDITS.md.
- Keep firmware workflows manual-only. Ordinary pushes must not compile, release or synchronize upstream automatically.
- Retain existing OpenClash AI/US-AI, scoped QUIC, Docker routing, MosDNS hosts, Tailscale compatibility and Argon dependency gates.
- Keep manual Proxy US-first using an existing country group and offer US-AI exactly once; preserve other choices, their relative order, AI/Google defaults and country Auto/Manual behavior. Update all three public profiles and the idempotent final helper together. Keep stored selections and empty public subscriptions/identities intact; never copy private files or history for this policy.
- Approved public first-boot networking: LAN 192.168.11.4, gateway 192.168.11.1, idempotent deletion of logical WAN/WAN6, and dhcp.lan.ignore=1 (IPv4 DHCP off). Keep exact-allowlist and isolated boot tests.
- Also approved: LAN6 DHCPv6 client on LAN (device/legacy ifname), removal of LAN ip6assign, request address/prefix without peer DNS, LAN-zone membership; dnsmasq port3553, DNS redirection/cache off and local MosDNS upstream127.0.0.1#5335. Keep list additions idempotent.
- RA/DHCPv6 server settings, private MAC/SSH and device identities remain outside the approved public defaults. LAN6 is not the proxy IPv6 switch.
- Do not change private repositories or live routers while maintaining this public template.
