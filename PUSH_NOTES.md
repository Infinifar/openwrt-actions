# Push notes

## 2026-10-25 - refresh Tailscale LuCI after upstream #81

- Adopt fresh master containing upstream #80/#81, retain its UI/status/worker/lifecycle and replace the incompatible legacy patch with narrow firmware guards. Preserve private/public separation and all device policies.
- Trigger one manual x86 build in the appropriate GitLab/GitHub service after pushing; no live-router changes or continuous monitoring. See docs/tailscale-upstream-81.md.

Destination: existing public GitHub repository Infinifar/openwrt-actions, master.

Follow-ups: approved public networking now includes LAN192.168.11.4/gateway192.168.11.1, WAN/WAN6 removal, LAN IPv4 DHCP off, LAN6 DHCPv6 client on LAN and dnsmasq3553 with cache/redirection off and local MosDNS5335 forwarding. Original credentials, identities, MAC/SSH and RA/DHCPv6-server customization remain excluded; private GitLab and live devices stay untouched.

This is a reviewed file-level export on top of existing public history, not a private mirror. Accounts, subscriptions, device state, deployment inventory and private GitLab CI are excluded. The private source is read-only and unchanged.

MosDNS is published separately with its original license and attribution; the firmware points at its public commit. For this follow-up the user requested no extra checks: regression fixtures/allowlist are updated but not executed by the agent. Trigger the manual GitHub x86 build after publishing, without continuous status monitoring.
