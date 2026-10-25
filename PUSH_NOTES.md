# Push notes

Destination: existing public GitHub repository Infinifar/openwrt-actions, master.

Follow-ups: the user explicitly approved LAN 192.168.11.4 and gateway 192.168.11.1, then idempotent deletion of logical WAN/WAN6 and disabling LAN IPv4 DHCP. Only that exact first-boot set is restored, with allowlist/negative tests and isolated mock-UCI execution. LAN6/RA/DHCPv6 and dnsmasq changes remain pending; private GitLab and live devices stay untouched.

This is a reviewed file-level export on top of existing public history, not a private mirror. Accounts, subscriptions, device state, deployment inventory and private GitLab CI are excluded. The private source is read-only and unchanged.

MosDNS is published separately with its original license and attribution; the firmware points at its public commit. Public templates and functional regressions must pass before staging and pushing. No firmware build or continuous monitoring is requested.
