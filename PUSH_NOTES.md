# Push notes

Destination: existing public GitHub repository Infinifar/openwrt-actions, master.

Follow-ups: approved public networking now includes LAN192.168.11.4/gateway192.168.11.1, WAN/WAN6 removal, LAN IPv4 DHCP off, LAN6 DHCPv6 client on LAN and dnsmasq3553 with cache/redirection off and local MosDNS5335 forwarding. Original credentials, identities, MAC/SSH and RA/DHCPv6-server customization remain excluded; private GitLab and live devices stay untouched.

This is a reviewed file-level export on top of existing public history, not a private mirror. Accounts, subscriptions, device state, deployment inventory and private GitLab CI are excluded. The private source is read-only and unchanged.

MosDNS is published separately with its original license and attribution; the firmware points at its public commit. For this follow-up the user requested no extra checks: regression fixtures/allowlist are updated but not executed by the agent. Trigger the manual GitHub x86 build after publishing, without continuous status monitoring.
